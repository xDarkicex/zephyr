package loader

import "core:os"
import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "../debug"

// FileCache provides caching for frequently accessed files
FileCache :: struct {
    cache: map[string]CachedFile,
    max_size: int,
    current_size: int,
}

// CachedFile represents a cached file with metadata
CachedFile :: struct {
    content: string,
    size: int,
    last_accessed: u64,
    access_count: int,
}

// create_file_cache creates a new file cache with specified max size
create_file_cache :: proc(max_size_bytes: int = 1024 * 1024) -> FileCache { // 1MB default
    return FileCache{
        cache = make(map[string]CachedFile),
        max_size = max_size_bytes,
    }
}

// destroy_file_cache cleans up the file cache.
// Cleanup pattern: nil check, free owned contents, delete container, set to nil/empty.
destroy_file_cache :: proc(cache: ^FileCache) {
    if cache == nil do return

    if cache.cache != nil {
        for key, cached_file in cache.cache {
            if cached_file.content != "" {
                delete(cached_file.content)
            }
            if key != "" {
                delete(key)
            }
        }
        delete(cache.cache)
        cache.cache = nil
    }
    cache.current_size = 0
}

// read_file_cached reads a file with caching support
read_file_cached :: proc(cache: ^FileCache, file_path: string) -> (string, bool) {
    if cache == nil do return "", false

    // Check cache first
    if cache.cache != nil {
        if cached_file, exists := cache.cache[file_path]; exists {
            // Update access statistics
            cached_file.last_accessed += 1
            cached_file.access_count += 1
            cache.cache[file_path] = cached_file
            
            debug.debug_trace("File cache hit: %s", file_path)
            return cached_file.content, true
        }
    }
    
    // Read from disk
    data, ok := os.read_entire_file(file_path)
    if !ok {
        debug.debug_warn("Failed to read file: %s", file_path)
        return "", false
    }
    
    content := string(data)
    file_size := len(content)

    if cache.cache == nil {
        // Caller owns returned content in this path.
        return content, true
    }
    
    // Add to cache if there's space
    if cache.current_size + file_size <= cache.max_size {
        cached_file := CachedFile{
            content = strings.clone(content),
            size = file_size,
            last_accessed = 1,
            access_count = 1,
        }
        
        cache.cache[strings.clone(file_path)] = cached_file
        cache.current_size += file_size

        // Safe to delete read buffer because cached_file has its own copy.
        delete(data)
        
        debug.debug_trace("File cached: %s (%d bytes)", file_path, file_size)
        return cached_file.content, true
    } else {
        // Try to evict least recently used files
        evict_lru_files(cache, file_size)
        
        // Try to add again after eviction
        if cache.current_size + file_size <= cache.max_size {
            cached_file := CachedFile{
                content = strings.clone(content),
                size = file_size,
                last_accessed = 1,
                access_count = 1,
            }
            
            cache.cache[strings.clone(file_path)] = cached_file
            cache.current_size += file_size

            // Safe to delete read buffer because cached_file has its own copy.
            delete(data)
            
            debug.debug_trace("File cached after eviction: %s (%d bytes)", file_path, file_size)
            return cached_file.content, true
        } else {
            debug.debug_trace("File too large for cache: %s (%d bytes)", file_path, file_size)
        }
    }
    
    return content, true
}

// evict_lru_files evicts least recently used files to make space
evict_lru_files :: proc(cache: ^FileCache, needed_space: int) {
    if cache == nil || cache.cache == nil || len(cache.cache) == 0 {
        return
    }
    
    // Find files to evict (simple LRU based on access count and recency)
    FileScore :: struct {
        path: string,
        score: f64, // Lower score = more likely to evict
        size: int,
    }
    
    scores := make([dynamic]FileScore)
    defer delete(scores)
    
    for path, cached_file in cache.cache {
        // Score based on access frequency and recency (higher = keep longer)
        score := f64(cached_file.access_count) * f64(cached_file.last_accessed)
        append(&scores, FileScore{
            path = path,
            score = score,
            size = cached_file.size,
        })
    }
    
    // Sort by score (ascending - lowest scores first for eviction)
    for i in 0..<len(scores) {
        for j in i+1..<len(scores) {
            if scores[i].score > scores[j].score {
                scores[i], scores[j] = scores[j], scores[i]
            }
        }
    }
    
    // Evict files until we have enough space
    freed_space := 0
    for score in scores {
        if freed_space >= needed_space {
            break
        }
        
        if cached_file, exists := cache.cache[score.path]; exists {
            delete_key(&cache.cache, score.path)
            cache.current_size -= cached_file.size
            freed_space += cached_file.size
            if score.path != "" {
                delete(score.path)
            }

            debug.debug_trace("Evicted from cache: %s (%d bytes)", score.path, cached_file.size)
        }
    }
}

// BatchFileReader provides efficient batch reading of multiple files
BatchFileReader :: struct {
    files: [dynamic]string,
    results: map[string]string,
    errors: map[string]string,
}

// create_batch_file_reader creates a new batch file reader
create_batch_file_reader :: proc() -> BatchFileReader {
    return BatchFileReader{
        files = make([dynamic]string),
        results = make(map[string]string),
        errors = make(map[string]string),
    }
}

// destroy_batch_file_reader cleans up the batch file reader.
// Cleanup pattern: nil check, free owned contents, delete container, set to nil/empty.
destroy_batch_file_reader :: proc(reader: ^BatchFileReader) {
    if reader == nil do return

    if reader.files != nil {
        for &file in reader.files {
            if file != "" {
                delete(file)
                file = ""
            }
        }
        delete(reader.files)
        reader.files = nil
    }
    
    if reader.results != nil {
        for key, value in reader.results {
            if value != "" {
                delete(value)
            }
            if key != "" {
                delete(key)
            }
        }
        delete(reader.results)
        reader.results = nil
    }

    if reader.errors != nil {
        // Values are string literals; only keys are owned.
        for key in reader.errors {
            if key != "" {
                delete(key)
            }
        }
        delete(reader.errors)
        reader.errors = nil
    }
}

// add_file adds a file to the batch reading queue
add_file :: proc(reader: ^BatchFileReader, file_path: string) {
    if reader == nil do return

    append(&reader.files, strings.clone(file_path))
}

// read_all_files reads all queued files in batch
read_all_files :: proc(reader: ^BatchFileReader) {
    if reader == nil do return

    if reader.results == nil {
        reader.results = make(map[string]string)
    }
    if reader.errors == nil {
        reader.errors = make(map[string]string)
    }

    debug.debug_info("Batch reading %d files", len(reader.files))
    
    for file_path in reader.files {
        data, ok := os.read_entire_file(file_path)
        if ok {
            reader.results[strings.clone(file_path)] = string(data)
            debug.debug_trace("Batch read success: %s", file_path)
        } else {
            reader.errors[strings.clone(file_path)] = "Failed to read file"
            debug.debug_warn("Batch read failed: %s", file_path)
        }
    }
}

// get_file_content gets the content of a file from batch results
get_file_content :: proc(reader: ^BatchFileReader, file_path: string) -> (string, bool) {
    if reader == nil || reader.results == nil {
        return "", false
    }

    if content, exists := reader.results[file_path]; exists {
        return content, true
    }
    return "", false
}

// DirectoryScanner provides optimized directory scanning
DirectoryScanner :: struct {
    base_path: string,
    pattern: string,
    max_depth: int,
    current_depth: int,
    results: [dynamic]string,
}

// create_directory_scanner creates a new directory scanner
create_directory_scanner :: proc(base_path: string, pattern: string = "module.toml", max_depth: int = 10) -> DirectoryScanner {
    return DirectoryScanner{
        base_path = strings.clone(base_path),
        pattern = strings.clone(pattern),
        max_depth = max_depth,
        results = make([dynamic]string),
    }
}

// destroy_directory_scanner cleans up the directory scanner.
// Cleanup pattern: nil check, free owned contents, delete container, set to nil/empty.
destroy_directory_scanner :: proc(scanner: ^DirectoryScanner) {
    if scanner == nil do return
    
    if scanner.base_path != "" {
        delete(scanner.base_path)
        scanner.base_path = ""
    }
    if scanner.pattern != "" {
        delete(scanner.pattern)
        scanner.pattern = ""
    }
    
    if scanner.results != nil {
        for &result in scanner.results {
            if result != "" {
                delete(result)
                result = ""
            }
        }
        delete(scanner.results)
        scanner.results = nil
    }
}

// scan_directories scans directories for files matching the pattern
scan_directories :: proc(scanner: ^DirectoryScanner) -> []string {
    if scanner == nil do return nil

    debug.debug_info("Scanning directories from: %s (pattern: %s, max_depth: %d)", 
                     scanner.base_path, scanner.pattern, scanner.max_depth)
    
    scan_directory_recursive(scanner, scanner.base_path, 0)
    
    debug.debug_info("Directory scan completed: found %d files", len(scanner.results))
    return scanner.results[:]
}

// scan_directory_recursive recursively scans a directory
scan_directory_recursive :: proc(scanner: ^DirectoryScanner, dir_path: string, depth: int) {
    if scanner == nil do return

    if depth > scanner.max_depth {
        debug.debug_trace("Max depth reached: %s (depth: %d)", dir_path, depth)
        return
    }
    
    handle, err := os.open(dir_path)
    if err != os.ERROR_NONE {
        debug.debug_warn("Cannot open directory: %s", dir_path)
        return
    }
    defer os.close(handle)
    
    // Read directory in batches for better memory usage
    batch_size := 50
    for {
        entries, read_err := os.read_dir(handle, batch_size)
        if read_err != os.ERROR_NONE {
            if entries != nil {
                os.file_info_slice_delete(entries)
            }
            debug.debug_warn("Cannot read directory: %s", dir_path)
            break
        }
        
        if len(entries) == 0 {
            os.file_info_slice_delete(entries)
            break
        }
        
        for entry in entries {
            entry_path := filepath.join({dir_path, entry.name})
            
            if entry.is_dir {
                // Recursively scan subdirectories
                scan_directory_recursive(scanner, entry_path, depth + 1)
            } else if entry.name == scanner.pattern {
                // Found matching file
                append(&scanner.results, strings.clone(entry_path))
                debug.debug_trace("Found matching file: %s", entry_path)
            }

            if entry_path != "" {
                delete(entry_path)
            }
        }
        
        os.file_info_slice_delete(entries)
        
        if len(entries) < batch_size {
            break
        }
    }
}

// FileExistenceCache provides caching for file existence checks
FileExistenceCache :: struct {
    cache: map[string]bool,
    max_entries: int,
}

// create_file_existence_cache creates a new file existence cache
create_file_existence_cache :: proc(max_entries: int = 1000) -> FileExistenceCache {
    return FileExistenceCache{
        cache = make(map[string]bool),
        max_entries = max_entries,
    }
}

// destroy_file_existence_cache cleans up the file existence cache.
// Cleanup pattern: nil check, free owned contents, delete container, set to nil/empty.
destroy_file_existence_cache :: proc(cache: ^FileExistenceCache) {
    if cache == nil do return

    if cache.cache != nil {
        for key in cache.cache {
            if key != "" {
                delete(key)
            }
        }
        delete(cache.cache)
        cache.cache = nil
    }
}

// file_exists_cached checks if a file exists with caching
file_exists_cached :: proc(cache: ^FileExistenceCache, file_path: string) -> bool {
    if cache == nil do return false

    // Check cache first
    if cache.cache != nil {
        if exists, cached := cache.cache[file_path]; cached {
            return exists
        }
    }
    
    // Check filesystem
    exists := os.exists(file_path)
    
    // Add to cache if there's space
    if cache.cache != nil && len(cache.cache) < cache.max_entries {
        cache.cache[strings.clone(file_path)] = exists
    }
    
    return exists
}

// clear_file_existence_cache clears the file existence cache.
// Frees owned keys and resets the map to empty.
clear_file_existence_cache :: proc(cache: ^FileExistenceCache) {
    if cache == nil || cache.cache == nil do return

    for key in cache.cache {
        if key != "" {
            delete(key)
        }
    }
    clear(&cache.cache)
}
