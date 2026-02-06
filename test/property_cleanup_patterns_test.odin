package test

import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../src/manifest"
import "../src/loader"

// **Property 15: Consistent Cleanup Patterns**
// **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5**
@(test)
test_property_cleanup_patterns_consistency :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    // Module cleanup is nil-safe and idempotent.
    {
        module := make_test_module("cleanup-pattern-module")
        manifest.cleanup_module(&module)
        manifest.cleanup_module(&module)

        testing.expect(t, module.name == "", "Module name should be empty after cleanup")
        testing.expect(t, module.version == "", "Module version should be empty after cleanup")
        testing.expect(t, module.required == nil, "Module required should be nil after cleanup")
        testing.expect(t, module.optional == nil, "Module optional should be nil after cleanup")
        testing.expect(t, module.files == nil, "Module files should be nil after cleanup")
        testing.expect(t, module.settings == nil, "Module settings should be nil after cleanup")
    }

    temp_dir := setup_test_environment("cleanup_pattern")
    defer teardown_test_environment(temp_dir)

    // Module cache cleanup is idempotent.
    {
        cache := loader.create_module_cache(temp_dir, 2)
        loader.destroy_module_cache(&cache)
        loader.destroy_module_cache(&cache)

        testing.expect(t, cache.modules == nil, "Cache modules should be nil after destroy")
        testing.expect(t, cache.dependency_cache == nil, "Dependency cache should be nil after destroy")
        testing.expect(t, cache.file_timestamps == nil, "File timestamps should be nil after destroy")
        testing.expect(t, cache.cache_dir == "", "Cache dir should be empty after destroy")
    }

    // File cache cleanup frees owned content and keys.
    {
        cache := loader.create_file_cache(1024)
        content := "test content"
        cached := loader.CachedFile{
            content = strings.clone(content),
            size = len(content),
            last_accessed = 1,
            access_count = 1,
        }
        cache.cache[strings.clone("file_cache_test.txt")] = cached
        cache.current_size = cached.size

        loader.destroy_file_cache(&cache)
        loader.destroy_file_cache(&cache)

        testing.expect(t, cache.cache == nil, "File cache map should be nil after destroy")
        testing.expect(t, cache.current_size == 0, "File cache size should be zero after destroy")
    }

    // Batch file reader cleanup is idempotent.
    {
        reader := loader.create_batch_file_reader()
        existing := filepath.join({temp_dir, "batch_exists.txt"})
        missing := filepath.join({temp_dir, "batch_missing.txt"})
        content := "ok"
        os.write_entire_file(existing, transmute([]u8)content)

        loader.add_file(&reader, existing)
        loader.add_file(&reader, missing)
        loader.read_all_files(&reader)

        delete(existing)
        delete(missing)

        loader.destroy_batch_file_reader(&reader)
        loader.destroy_batch_file_reader(&reader)

        testing.expect(t, reader.files == nil, "Batch reader files should be nil after destroy")
        testing.expect(t, reader.results == nil, "Batch reader results should be nil after destroy")
        testing.expect(t, reader.errors == nil, "Batch reader errors should be nil after destroy")
    }

    // Directory scanner cleanup is idempotent.
    {
        scanner := loader.create_directory_scanner(temp_dir)
        loader.destroy_directory_scanner(&scanner)
        loader.destroy_directory_scanner(&scanner)

        testing.expect(t, scanner.base_path == "", "Scanner base_path should be empty after destroy")
        testing.expect(t, scanner.pattern == "", "Scanner pattern should be empty after destroy")
        testing.expect(t, scanner.results == nil, "Scanner results should be nil after destroy")
    }

    // File existence cache cleanup clears owned keys and is idempotent.
    {
        existence := loader.create_file_existence_cache(8)
        file_path := filepath.join({temp_dir, "exists.txt"})
        content := "ok"
        os.write_entire_file(file_path, transmute([]u8)content)

        _ = loader.file_exists_cached(&existence, file_path)
        loader.clear_file_existence_cache(&existence)
        loader.destroy_file_existence_cache(&existence)
        loader.destroy_file_existence_cache(&existence)

        delete(file_path)

        testing.expect(t, existence.cache == nil, "Existence cache map should be nil after destroy")
    }
}
