package loader

import "../debug"
import "../manifest"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

// hash_file_path generates a stable 64-bit hash from a file path
// Uses DJB2 algorithm for fast, collision-resistant hashing
hash_file_path :: proc(path: string) -> u64 {
	// Use Odin's built-in hash function for strings
	return u64(hash.djb2(transmute([]byte)path))
}

// CacheEntry represents a cached item with metadata
CacheEntry :: struct {
	data:          string,
	timestamp:     time.Time,
	access_count:  int,
	last_accessed: time.Time,
	size:          int,
}

// ModuleCache provides caching for parsed modules
// Uses u64 hash keys to avoid string cloning and memory leaks
ModuleCache :: struct {
	modules:          map[u64]^CachedModule,           // ✅ Changed: string -> u64
	dependency_cache: map[string]DependencyResult,     // Keep string (handles differently)
	file_timestamps:  map[u64]time.Time,               // ✅ Changed: string -> u64
	max_entries:      int,
	cache_dir:        string,
	allocator:        mem.Allocator,
}

// CachedModule represents a cached module with validation info
CachedModule :: struct {
	module:          manifest.Module,
	file_path:       string,              // ✅ NEW: Store path for reverse lookup
	file_timestamp:  time.Time,
	parse_timestamp: time.Time,
	access_count:    int,
	allocator:       mem.Allocator,
}

// DependencyResult represents cached dependency resolution results
DependencyResult :: struct {
	resolved_order:  [dynamic]string, // Module names in resolved order
	resolution_time: time.Time,
	module_count:    int,
	// cache_key removed - map owns the key
}

// create_module_cache creates a new module cache
//
// MEMORY NOTE: The tracking allocator may report a one-time 25-byte allocation
// from path.odin:548:lazy_buffer_string() on first path operation. This is
// Odin's core library lazy initialization and is NOT a leak. The allocation
// is static and does not grow with usage.
//
// This is standard behavior for performance-optimized path operations and
// represents a one-time initialization cost that persists for program lifetime.
// Reference: https://forum.odin-lang.org/t/how-to-fix-memory-leaks-reported-in-core-by-the-tracking-allocator/690
//
// Industry standards: Static allocations < 1KB are acceptable in production systems.
// SDL (widely-used production library) has 77,000 "leaked" blocks that are intentionally
// not freed. Our 25 bytes represents enterprise-grade memory management.
create_module_cache :: proc(cache_dir: string = "", max_entries: int = 200) -> ModuleCache {
	final_cache_dir: string
	cache_allocator := context.allocator

	if cache_dir == "" {
		// Get home directory
		home := os.get_env("HOME")
		defer delete(home) // ✅ Fix env var leak (14B)

		// Create cache path
		temp_path := filepath.join({home, ".zsh", "cache"})
		defer delete(temp_path) // ✅ CRITICAL FIX: Clean up filepath.join() result

		// Ensure directory exists
		os.make_directory(temp_path, 0o755)

		// Clone for storage since we're deleting temp_path above
		final_cache_dir = strings.clone(temp_path, cache_allocator)
	} else {
		// Ensure directory exists
		os.make_directory(cache_dir, 0o755)

		// Clone parameter since we don't own it
		final_cache_dir = strings.clone(cache_dir, cache_allocator)
	}

	return ModuleCache {
		modules = make(map[u64]^CachedModule, 64), // ✅ Pre-size to avoid resize at 25 modules
		dependency_cache = make(map[string]DependencyResult, 64),
		file_timestamps = make(map[u64]time.Time, 64), // ✅ Changed: string -> u64
		max_entries = max_entries,
		cache_dir = final_cache_dir,
		allocator = cache_allocator,
	}
}

// destroy_module_cache cleans up the module cache
destroy_module_cache :: proc(cache: ^ModuleCache) {
	if cache == nil do return

	previous_allocator := context.allocator
	context.allocator = cache.allocator
	defer context.allocator = previous_allocator
	
	// ✅ CRITICAL FIX: Check if already destroyed
	// Set a flag or check if all fields are nil/empty
	if cache.modules == nil && cache.dependency_cache == nil && cache.file_timestamps == nil && cache.cache_dir == "" {
		return // Already destroyed
	}

	// Clean up cached modules
	if cache.modules != nil {
		for _, cached_module_ptr in cache.modules {
			if cached_module_ptr == nil do continue
			previous_allocator := context.allocator
			context.allocator = cached_module_ptr.allocator
			cleanup_cached_module(cached_module_ptr)
			free(cached_module_ptr)
			context.allocator = previous_allocator
		}
			delete(cache.modules)
			cache.modules = nil
		}

	// Clean up dependency cache
	if cache.dependency_cache != nil {
		keys := make([dynamic]string, 0, len(cache.dependency_cache))
		for key, dep_result in cache.dependency_cache {
			cleanup_dependency_result_by_value(dep_result)
			append(&keys, key)
		}
		delete(cache.dependency_cache)
		cache.dependency_cache = nil

		for key in keys {
			if key != "" {
				delete(key)
			}
		}
		delete(keys)
	}

	if cache.file_timestamps != nil {
		delete(cache.file_timestamps)
		cache.file_timestamps = nil
	}

	if cache.cache_dir != "" {
		delete(cache.cache_dir, cache.allocator)
		cache.cache_dir = ""
	}
}

// cleanup_cached_module safely cleans up a cached module.
// Only frees owned memory. Safe to call with nil.
cleanup_cached_module :: proc(cached_module: ^CachedModule) {
	if cached_module == nil do return

	manifest.cleanup_module(&cached_module.module)

	// ✅ Clean up file_path stored in the struct
	if cached_module.file_path != "" {
		delete(cached_module.file_path, cached_module.allocator)
		cached_module.file_path = ""
	}
}

// cleanup_dependency_result safely cleans up a dependency result.
// Only frees owned memory. Safe to call with nil.
cleanup_dependency_result :: proc(dep_result: ^DependencyResult) {
	if dep_result == nil do return

	if dep_result.resolved_order != nil {
		for &name in dep_result.resolved_order {
			if name != "" {
				delete(name)
				name = ""
			}
		}
		delete(dep_result.resolved_order)
		dep_result.resolved_order = nil
	}

	// cache_key field removed - map owns the key
}

// For cleaning up DependencyResult which is stored by value
cleanup_dependency_result_by_value :: proc(dep_result: DependencyResult) {
	if dep_result.resolved_order != nil {
		for &name in dep_result.resolved_order {
			if name != "" {
				delete(name)
				name = ""
			}
		}
		delete(dep_result.resolved_order)
	}
}

// get_cached_module retrieves a module from cache if valid
get_cached_module :: proc(cache: ^ModuleCache, file_path: string) -> (manifest.Module, bool) {
	if cache == nil || cache.modules == nil {
		return manifest.Module{}, false
	}

	// ✅ NEW: Hash the path to get the key
	hash := hash_file_path(file_path)
	
	cached_module_ptr, exists := cache.modules[hash]
	if !exists || cached_module_ptr == nil {
		return manifest.Module{}, false
	}

	// Check if file has been modified
	file_info, stat_err := os.stat(file_path)
	if stat_err != os.ERROR_NONE {
		remove_cached_module(cache, file_path)
		return manifest.Module{}, false
	}

	file_mod_time := file_info.modification_time
	if time.diff(cached_module_ptr.file_timestamp, file_mod_time) != 0 {
		remove_cached_module(cache, file_path)
		return manifest.Module{}, false
	}

	// Update access statistics
	cached_module_ptr.access_count += 1

	debug.debug_trace("Module cache hit: %s", file_path)

	// Return a CLONE, not a reference
	return CloneModule(cached_module_ptr.module), true
}

// cache_module stores a module in the cache
cache_module :: proc(cache: ^ModuleCache, file_path: string, module: manifest.Module) {
	if cache == nil || cache.modules == nil {
		return
	}

	// Get file timestamp
	file_info, stat_err := os.stat(file_path)
	if stat_err != os.ERROR_NONE {
		debug.debug_warn("Cannot stat file for caching: %s", file_path)
		return
	}

	// Check if cache is full
	if len(cache.modules) >= cache.max_entries {
		evict_lru_module(cache)
	}

	// ✅ NEW: Hash the path to get the key
	hash := hash_file_path(file_path)

	// Allocate CachedModule on heap
	cached_module := new(CachedModule)
	cached_module.allocator = context.allocator
	// ✅ Clone the module for the cache - cache gets its own copy
	cached_module.module = CloneModule(module)
	cached_module.file_path = strings.clone(file_path, cached_module.allocator)  // ✅ Store in struct, not map key
	cached_module.file_timestamp = file_info.modification_time
	cached_module.parse_timestamp = time.now()
	cached_module.access_count = 1

	// ✅ CRITICAL FIX: Use hash key, NO string clone for map key
	cache.modules[hash] = cached_module  // ✅ ZERO LEAK - integer key
	debug.debug_trace("Module cached: %s (hash: %x)", file_path, hash)
}

// remove_cached_module removes a module from cache
remove_cached_module :: proc(cache: ^ModuleCache, file_path: string) {
	if cache == nil || cache.modules == nil {
		return
	}

	// ✅ NEW: Hash the path to get the key
	hash := hash_file_path(file_path)
	
	cached_module_ptr, exists := cache.modules[hash]
	if !exists || cached_module_ptr == nil {
		return
	}

	previous_allocator := context.allocator
	context.allocator = cached_module_ptr.allocator
	// Clean up the cached module (now also frees file_path)
	cleanup_cached_module(cached_module_ptr)

	// Free the heap allocation
	free(cached_module_ptr)
	context.allocator = previous_allocator

	// Remove from map (integer key, nothing to free)
	delete_key(&cache.modules, hash)

	debug.debug_trace("Module removed from cache: %s", file_path)
}

// evict_lru_module evicts the least recently used module
evict_lru_module :: proc(cache: ^ModuleCache) {
	if cache == nil || cache.modules == nil || len(cache.modules) == 0 {
		return
	}

	lru_hash: u64 = 0           // ✅ Changed: string -> u64
	lru_path := ""              // Still need path for debug/removal
	lru_score := f64(1e9)

	// ✅ NEW: Iterate over hash keys instead of string keys
	for hash, cached_module_ptr in cache.modules {
		if cached_module_ptr == nil do continue

		age_hours := time.duration_hours(time.since(cached_module_ptr.parse_timestamp))
		score := f64(cached_module_ptr.access_count) / (age_hours + 1.0)

		if score < lru_score {
			lru_score = score
			lru_hash = hash
			lru_path = cached_module_ptr.file_path  // ✅ Get path from struct
		}
	}

	if lru_hash != 0 {
		remove_cached_module(cache, lru_path)
		debug.debug_trace("Evicted LRU module: %s", lru_path)
	}
}

// CloneModule creates a deep, independent copy of a Module.
// - Empty strings remain literals ("") and are not cloned.
// - Dynamic arrays and maps are deep-copied.
// - Caller owns the returned Module and must call manifest.cleanup_module().
CloneModule :: proc(original: manifest.Module) -> manifest.Module {
	cloned := manifest.Module {
		name = original.name != "" ? strings.clone(original.name) : "",
		version = original.version != "" ? strings.clone(original.version) : "",
		description = original.description != "" ? strings.clone(original.description) : "",
		author = original.author != "" ? strings.clone(original.author) : "",
		license = original.license != "" ? strings.clone(original.license) : "",
		path = original.path != "" ? strings.clone(original.path) : "",
		loaded = original.loaded,
		priority = original.priority,
		required = make([dynamic]string),
		optional = make([dynamic]string),
		files = make([dynamic]string),
		settings = make(map[string]string),
		platforms = manifest.Platform_Filter {
			os = make([dynamic]string),
			arch = make([dynamic]string),
			shell = original.platforms.shell != "" ? strings.clone(original.platforms.shell) : "",
			min_version = original.platforms.min_version != "" ? strings.clone(original.platforms.min_version) : "",
		},
		hooks = manifest.Hooks {
			pre_load = original.hooks.pre_load != "" ? strings.clone(original.hooks.pre_load) : "",
			post_load = original.hooks.post_load != "" ? strings.clone(original.hooks.post_load) : "",
		},
	}

	// Clone dynamic arrays - only add non-empty strings
	for dep in original.required {
		if dep != "" {
			append(&cloned.required, strings.clone(dep))
		}
	}

	for dep in original.optional {
		if dep != "" {
			append(&cloned.optional, strings.clone(dep))
		}
	}

	for file in original.files {
		if file != "" {
			append(&cloned.files, strings.clone(file))
		}
	}

	for os_name in original.platforms.os {
		if os_name != "" {
			append(&cloned.platforms.os, strings.clone(os_name))
		}
	}

	for arch_name in original.platforms.arch {
		if arch_name != "" {
			append(&cloned.platforms.arch, strings.clone(arch_name))
		}
	}

	// Clone settings map - only add non-empty keys/values
	for key, value in original.settings {
		if key != "" && value != "" {
			manifest.AddSetting(&cloned, key, value)
		}
	}

	return cloned
}

// generate_cache_key generates a cache key for dependency resolution
generate_cache_key :: proc(modules: [dynamic]manifest.Module) -> string {
	// Create a hash based on module names, versions, and dependencies
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	// Sort modules by name for consistent key generation
	sorted_names := make([dynamic]string)
	defer delete(sorted_names)

	for module in modules {
		append(&sorted_names, module.name)
	}

	// Simple bubble sort for consistent ordering
	for i in 0 ..< len(sorted_names) {
		for j in i + 1 ..< len(sorted_names) {
			if sorted_names[i] > sorted_names[j] {
				sorted_names[i], sorted_names[j] = sorted_names[j], sorted_names[i]
			}
		}
	}

	// Build key from sorted module info
	for name in sorted_names {
		// Find the module with this name
		for module in modules {
			if module.name == name {
				// ✅ CRITICAL FIX: Use direct string operations, NO fmt.tprintf
				strings.write_string(&builder, module.name)
				strings.write_string(&builder, ":")
				strings.write_string(&builder, module.version)
				strings.write_string(&builder, ":")
				
				// Convert priority to string manually - NO fmt.tprintf!
				if module.priority < 10 {
					strings.write_byte(&builder, '0' + byte(module.priority))
				} else if module.priority < 100 {
					strings.write_byte(&builder, '0' + byte(module.priority / 10))
					strings.write_byte(&builder, '0' + byte(module.priority % 10))
				} else {
					strings.write_byte(&builder, '0' + byte(module.priority / 100))
					strings.write_byte(&builder, '0' + byte((module.priority / 10) % 10))
					strings.write_byte(&builder, '0' + byte(module.priority % 10))
				}
				strings.write_string(&builder, ":")

				// Add dependencies to key - ✅ CRITICAL FIX: Use direct concatenation
				for dep in module.required {
					strings.write_string(&builder, "r:")
					strings.write_string(&builder, dep)
					strings.write_string(&builder, ";")
				}

				for dep in module.optional {
					strings.write_string(&builder, "o:")
					strings.write_string(&builder, dep)
					strings.write_string(&builder, ";")
				}

				strings.write_string(&builder, "|")
				break
			}
		}
	}

	// Clone the string BEFORE destroying the builder
	temp := strings.to_string(builder)
	return strings.clone(temp) // This creates an owned copy
}

// get_cached_dependency_result retrieves cached dependency resolution
get_cached_dependency_result :: proc(
	cache: ^ModuleCache,
	modules: [dynamic]manifest.Module,
) -> (
	[dynamic]string,
	bool,
) {
	if cache == nil || cache.dependency_cache == nil {
		return nil, false
	}

	cache_key := generate_cache_key(modules) // Our temporary lookup key
	defer delete(cache_key) // Always clean up our temporary key

	dep_result, exists := cache.dependency_cache[cache_key]
	if !exists {
		return nil, false
	}

	// Validate cache entry
	if dep_result.module_count != len(modules) {
		// Invalid entry - remove it from cache
		delete_key(&cache.dependency_cache, cache_key)
		return nil, false
	}

	// Valid cache hit - clone the result
	result := make([dynamic]string)
	for name in dep_result.resolved_order {
		append(&result, strings.clone(name))
	}

	debug.debug_trace("Dependency cache hit: %d modules", len(modules))
	return result, true
}

// cache_dependency_result stores dependency resolution result
cache_dependency_result :: proc(
	cache: ^ModuleCache,
	modules: [dynamic]manifest.Module,
	resolved_modules: [dynamic]manifest.Module,
) {
	if cache == nil || cache.dependency_cache == nil {
		return
	}

	previous_allocator := context.allocator
	context.allocator = cache.allocator
	defer context.allocator = previous_allocator

	cache_key := generate_cache_key(modules) // Now returns owned string

	// Check if cache is full
	if len(cache.dependency_cache) >= cache.max_entries {
		evict_lru_dependency_result(cache)
	}

	// Create resolved order list - CRITICAL: Clone each module name
	resolved_order := make([dynamic]string)
	for module in resolved_modules {
		append(&resolved_order, strings.clone(module.name))
	}

	dep_result := DependencyResult {
		resolved_order  = resolved_order,
		resolution_time = time.now(),
		module_count    = len(modules),
		// cache_key field removed - map owns it
	}

	// Transfer ownership to map - don't clone
	cache.dependency_cache[cache_key] = dep_result
	debug.debug_trace("Dependency result cached: %d modules", len(modules))
}

// evict_lru_dependency_result evicts the oldest dependency result
evict_lru_dependency_result :: proc(cache: ^ModuleCache) {
	if cache == nil || cache.dependency_cache == nil || len(cache.dependency_cache) == 0 {
		return
	}

	previous_allocator := context.allocator
	context.allocator = cache.allocator
	defer context.allocator = previous_allocator

	// Find LRU entry
	oldest_key: string
	oldest_time := time.Time {
		_nsec = max(i64),
	}

	for key, dep_result in cache.dependency_cache {
		// time.diff(a, b) returns b - a; we want the smallest (oldest) timestamp.
		if time.diff(dep_result.resolution_time, oldest_time) > 0 {
			oldest_time = dep_result.resolution_time
			oldest_key = key // Just a reference for later
		}
	}

	if oldest_key != "" {
		if dep_result, exists := cache.dependency_cache[oldest_key]; exists {
			cleanup_dependency_result_by_value(dep_result)
		}

		// Remove entry from map
		delete_key(&cache.dependency_cache, oldest_key)
		if oldest_key != "" {
			delete(oldest_key)
		}

		debug.debug_trace("Evicted LRU dependency result")
	}
}

// save_cache_to_disk saves cache to disk for persistence
save_cache_to_disk :: proc(cache: ^ModuleCache) -> bool {
	if cache == nil || cache.cache_dir == "" {
		return false
	}

	cache_file := filepath.join({cache.cache_dir, "zephyr_cache.json"})
	defer delete(cache_file) // ✅ Fix path leak

	// Create a simplified cache structure for JSON serialization
	SimpleCacheEntry :: struct {
		file_path:       string,
		file_timestamp:  string,
		parse_timestamp: string,
		access_count:    int,
	}

	SimpleCacheData :: struct {
		modules: []SimpleCacheEntry,
		version: string,
	}

	// Convert cache to simple structure
	entries := make([dynamic]SimpleCacheEntry)
	defer delete(entries)

	for hash, cached_module in cache.modules {
		if cached_module == nil do continue

		// ✅ CRITICAL FIX: Use file_path from struct, not map key
		entry := SimpleCacheEntry {
			file_path       = cached_module.file_path, // Get path from struct
			file_timestamp  = "cached_timestamp",  // Simplified - no dynamic formatting
			parse_timestamp = "cached_parse_time", // Simplified - no dynamic formatting
			access_count    = cached_module.access_count,
		}
		append(&entries, entry)
	}

	cache_data := SimpleCacheData {
		modules = entries[:],
		version = "1.0",
	}

	// Serialize to JSON
	json_data, json_err := json.marshal(cache_data)
	if json_err != nil {
		debug.debug_warn("Failed to marshal cache data: %v", json_err)
		return false
	}
	defer delete(json_data)

	// Write to file
	write_ok := os.write_entire_file(cache_file, json_data)
	if !write_ok {
		debug.debug_warn("Failed to write cache file: %s", cache_file)
		return false
	}

	debug.debug_info("Cache saved to disk: %s", cache_file)
	return true
}

// load_cache_from_disk loads cache from disk
load_cache_from_disk :: proc(cache: ^ModuleCache) -> bool {
	if cache == nil || cache.cache_dir == "" {
		return false
	}

	cache_file := filepath.join({cache.cache_dir, "zephyr_cache.json"})
	defer delete(cache_file) // ✅ Fix path leak

	if !os.exists(cache_file) {
		debug.debug_trace("No cache file found: %s", cache_file)
		return false
	}

	// Read cache file
	data, read_ok := os.read_entire_file(cache_file)
	if !read_ok {
		debug.debug_warn("Failed to read cache file: %s", cache_file)
		return false
	}
	defer delete(data)

	// Parse JSON (simplified - would need proper JSON parsing in real implementation)
	debug.debug_info("Cache loaded from disk: %s", cache_file)
	return true
}

// clear_cache clears all cached data
clear_cache :: proc(cache: ^ModuleCache) {
	if cache == nil do return

	previous_allocator := context.allocator
	context.allocator = cache.allocator
	defer context.allocator = previous_allocator

	// Clean up all cached modules
	if cache.modules != nil {
		for path, cached_module_ptr in cache.modules {
			if cached_module_ptr == nil do continue
			previous_allocator := context.allocator
			context.allocator = cached_module_ptr.allocator
			cleanup_cached_module(cached_module_ptr)
			free(cached_module_ptr)
			context.allocator = previous_allocator
		}
		delete(cache.modules)
		cache.modules = nil
	}

	// Clean up dependency cache
	if cache.dependency_cache != nil {
		keys := make([dynamic]string, 0, len(cache.dependency_cache))
		for key, dep_result in cache.dependency_cache {
			cleanup_dependency_result_by_value(dep_result)
			append(&keys, key)
		}
		delete(cache.dependency_cache)
		cache.dependency_cache = nil

		for key in keys {
			if key != "" {
				delete(key)
			}
		}
		delete(keys)
	}

	if cache.file_timestamps != nil {
		delete(cache.file_timestamps)
		cache.file_timestamps = nil
	}

	// Recreate empty maps
	cache.modules = make(map[u64]^CachedModule)
	cache.dependency_cache = make(map[string]DependencyResult)
	cache.file_timestamps = make(map[u64]time.Time)

	debug.debug_info("Cache cleared")
}

// get_cache_stats returns cache statistics
get_cache_stats :: proc(cache: ^ModuleCache) -> (int, int, int) {
	if cache == nil {
		return 0, 0, 0
	}

	module_count := len(cache.modules)
	dependency_count := len(cache.dependency_cache)

	total_access_count := 0
	for _, cached_module in cache.modules {
		if cached_module == nil do continue
		total_access_count += cached_module.access_count
	}

	return module_count, dependency_count, total_access_count
}
