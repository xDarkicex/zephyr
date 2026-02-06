package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:testing"

import "../src/loader"
import "../src/manifest"

// **Validates: Requirements 2.4**
@(test)
test_property_cache_cleanup_safety :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    temp_dir := setup_test_environment("test_cache_cleanup")
    defer teardown_test_environment(temp_dir)

    cache := loader.create_module_cache(temp_dir, 8)

    content := "test"
    for i in 0..<2 {
        module_name := fmt.tprintf("cache_module_%02d", i)
        file_name := fmt.tprintf("cache_module_%02d.toml", i)
        file_path := filepath.join({temp_dir, file_name})

        os.write_entire_file(file_path, transmute([]u8)content)

        module := make_test_module(module_name)
        loader.cache_module(&cache, file_path, module)

        manifest.cleanup_module(&module)

        delete(file_path)
    }

    // Cache cleanup should free all cached modules without bad frees
    loader.destroy_module_cache(&cache)
    testing.expect(t, cache.modules == nil, "Cache modules map should be nil after destroy")
    testing.expect(t, cache.dependency_cache == nil, "Dependency cache should be nil after destroy")
    testing.expect(t, cache.file_timestamps == nil, "File timestamps map should be nil after destroy")
    testing.expect(t, cache.cache_dir == "", "Cache dir should be empty after destroy")

    // Idempotent cleanup
    loader.destroy_module_cache(&cache)
}

// **Validates: Requirements 2.5**
@(test)
test_unit_cache_operations :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    temp_dir := setup_test_environment("test_cache_ops")
    defer teardown_test_environment(temp_dir)

    cache := loader.create_module_cache(temp_dir, 4)

    module_name := "cache-ops-module"
    file_path := filepath.join({temp_dir, "cache_ops_module.toml"})
    defer delete(file_path)

    content := "test"
    os.write_entire_file(file_path, transmute([]u8)content)

    module := make_test_module(module_name)
    loader.cache_module(&cache, file_path, module)

    cached_module, ok := loader.get_cached_module(&cache, file_path)
    testing.expect(t, ok, "Should retrieve cached module")
    if ok {
        testing.expect_value(t, cached_module.name, module_name)
        manifest.cleanup_module(&cached_module)
    }

    manifest.cleanup_module(&module)

    loader.destroy_module_cache(&cache)
}

// **Validates: Requirements 8.2**
@(test)
test_property_cache_bounds_module_cache :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    temp_dir := setup_test_environment("test_cache_bounds_modules")
    defer teardown_test_environment(temp_dir)

    max_entries := 3
    cache := loader.create_module_cache(temp_dir, max_entries)

    content := "test"
    total_modules := 5
    paths := make([dynamic]string, 0, total_modules)
    defer {
        for path in paths {
            if path != "" {
                delete(path)
            }
        }
        delete(paths)
    }

    for i in 0..<total_modules {
        file_name := fmt.tprintf("cache_bound_%02d.toml", i)
        file_path := filepath.join({temp_dir, file_name})

        os.write_entire_file(file_path, transmute([]u8)content)
        append(&paths, strings.clone(file_path))

        module_name := fmt.tprintf("cache-bound-%d", i)
        module := make_test_module(module_name)
        loader.cache_module(&cache, file_path, module)
        manifest.cleanup_module(&module)

        delete(file_path)

        testing.expect(t, len(cache.modules) <= max_entries, "Cache size should not exceed max_entries")

        if i == max_entries-1 {
            // Increase access count for the first entry to make it the most-recently-used.
            if cached, ok := loader.get_cached_module(&cache, paths[0]); ok {
                manifest.cleanup_module(&cached)
            }
        }
    }

    testing.expect_value(t, len(cache.modules), max_entries)

    // The most-accessed entry should survive eviction.
    if cached, ok := loader.get_cached_module(&cache, paths[0]); ok {
        manifest.cleanup_module(&cached)
        testing.expect(t, ok, "Most-accessed module should remain after eviction")
    } else {
        testing.expect(t, false, "Most-accessed module should remain after eviction")
    }

    // At least one of the earliest entries should be evicted once we exceed max_entries.
    survivors := 0
    for i in 0..<max_entries {
        if cached, ok := loader.get_cached_module(&cache, paths[i]); ok {
            manifest.cleanup_module(&cached)
            survivors += 1
        }
    }
    testing.expect(t, survivors < max_entries, "Older entries should be evicted when cache exceeds max_entries")

    loader.destroy_module_cache(&cache)
}

// **Validates: Requirements 8.2**
@(test)
test_property_cache_bounds_dependency_cache :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    temp_dir := setup_test_environment("test_cache_bounds_dependencies")
    defer teardown_test_environment(temp_dir)

    max_entries := 2
    cache := loader.create_module_cache(temp_dir, max_entries)

    keys := make([dynamic]string, 0, max_entries+1)
    defer {
        for key in keys {
            if key != "" {
                delete(key)
            }
        }
        delete(keys)
    }

    for i in 0..<max_entries+1 {
        modules := make([dynamic]manifest.Module)

        module_name := fmt.tprintf("dep-%d", i)
        module := make_test_module(module_name)
        append(&modules, module)

        key := loader.generate_cache_key(modules)
        append(&keys, key)

        loader.cache_dependency_result(&cache, modules, modules)

        manifest.cleanup_modules(modules[:])
        delete(modules)

        testing.expect(t, len(cache.dependency_cache) <= max_entries, "Dependency cache size should not exceed max_entries")

        // Ensure time advances so eviction order is deterministic.
        start := time.now()
        for time.since(start) < time.Millisecond {
        }
    }

    testing.expect_value(t, len(cache.dependency_cache), max_entries)

    // At least one entry should be evicted once we exceed max_entries.
    remaining := 0
    for key in keys {
        if _, exists := cache.dependency_cache[key]; exists {
            remaining += 1
        }
    }
    testing.expect(t, remaining < len(keys), "Dependency cache should evict entries when over max_entries")

    loader.destroy_module_cache(&cache)
}
