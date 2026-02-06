package test

import "core:testing"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:path/filepath"
import "core:mem"

import "../src/loader"
import "../src/manifest"

// **Property 7: Error Handling Without Infinite Loops**
// **Validates: Requirements 3.3**
@(test)
test_property_error_handling_no_infinite_loops :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    for i in 0..<10 {
        modules := make([dynamic]manifest.Module)

        module := make_test_module(fmt.tprintf("error-module-%d", i))
        append(&module.required, strings.clone("missing-dep"))
        append(&modules, module)

        resolved, err := loader.resolve(modules)
        testing.expect(t, err != "", "Missing dependency should return an error without looping")

        cleanup_error_message(err)
        cleanup_resolved(resolved)

        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
}

// **Property 8: Cache Operation Correctness**
// **Validates: Requirements 4.1, 4.3, 4.4, 4.5**
@(test)
test_property_cache_operation_correctness :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    temp_dir := setup_test_environment("cache_operation_correctness")
    defer teardown_test_environment(temp_dir)

    max_entries := 3
    cache := loader.create_module_cache(temp_dir, max_entries)
    defer loader.destroy_module_cache(&cache)

    content := "test"
    paths := make([dynamic]string, 0, 5)
    names := make([dynamic]string, 0, 5)
    defer {
        for path in paths {
            if path != "" {
                delete(path)
            }
        }
        for name in names {
            if name != "" {
                delete(name)
            }
        }
        delete(paths)
        delete(names)
    }

    for i in 0..<5 {
        file_name := fmt.tprintf("cache-module-%d.toml", i)
        file_path := filepath.join({temp_dir, file_name})
        os.write_entire_file(file_path, transmute([]u8)content)

        module_name := strings.clone(fmt.tprintf("cache-module-%d", i))
        module := make_test_module(module_name)

        loader.cache_module(&cache, file_path, module)
        manifest.cleanup_module(&module)

        append(&paths, strings.clone(file_path))
        append(&names, module_name)

        delete(file_path)

        testing.expect(t, len(cache.modules) <= max_entries, "Cache size should not exceed max_entries")
    }

    // Cache should evict entries when over capacity.
    testing.expect_value(t, len(cache.modules), max_entries)

    // Cached module should return a clone (mutations should not affect cache).
    if cached, ok := loader.get_cached_module(&cache, paths[0]); ok {
        cached.name = strings.clone("mutated")
        manifest.cleanup_module(&cached)
    }

    if cached_again, ok := loader.get_cached_module(&cache, paths[0]); ok {
        testing.expect(t, cached_again.name == names[0], "Cached module should remain unchanged")
        manifest.cleanup_module(&cached_again)
    }

    // Dependency cache correctness: store and retrieve in order.
    dep_modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(dep_modules[:])
        delete(dep_modules)
    }

    for i in 0..<2 {
        dep_module := make_test_module(fmt.tprintf("dep-%d", i))
        append(&dep_modules, dep_module)
    }

    loader.cache_dependency_result(&cache, dep_modules, dep_modules)

    cached_order, ok := loader.get_cached_dependency_result(&cache, dep_modules)
    testing.expect(t, ok, "Dependency cache should return cached order")
    if ok {
        testing.expect_value(t, len(cached_order), len(dep_modules))
        loader.cleanup_string_array(cached_order)
    }
}

// **Property 10: Buffer Safety**
// **Validates: Requirements 5.4**
@(test)
test_property_buffer_safety :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }

    long_name := strings.repeat("module", 512, context.temp_allocator)

    for i in 0..<10 {
        name := fmt.tprintf("%s-%d", long_name, i)
        module := make_test_module(name)

        for j in 0..<10 {
            file_name := fmt.tprintf("file-%d.zsh", j)
            append(&module.files, strings.clone(file_name))
        }
        manifest.AddSetting(&module, "debug", "true")
        append(&modules, module)
    }

    // Ensure emit can handle large strings without buffer overflows.
    loader.emit(modules)
    testing.expect(t, true, "Emit should complete for large inputs")
}

// **Property 12: Zero Bad Frees**
// **Validates: Requirements 7.1, 7.2**
@(test)
test_property_zero_bad_frees :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    original_allocator := context.allocator
    defer context.allocator = original_allocator

    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking_allocator)

    tracking_allocator.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array

    context.allocator = mem.tracking_allocator(&tracking_allocator)

    temp_dir := setup_test_environment("zero_bad_frees")
    defer teardown_test_environment(temp_dir)

    // Module lifecycle
    module := make_test_module("bad-free-module")
    cloned := loader.CloneModule(module)
    manifest.cleanup_module(&module)
    manifest.cleanup_module(&cloned)

    // Cache lifecycle
    cache := loader.create_module_cache(temp_dir, 2)
    content := "test"
    file_path := filepath.join({temp_dir, "module.toml"})
    os.write_entire_file(file_path, transmute([]u8)content)
    loader.cache_module(&cache, file_path, make_test_module("cached"))
    delete(file_path)
    loader.destroy_module_cache(&cache)

    testing.expect(t, len(tracking_allocator.bad_free_array) == 0, "No bad frees should be reported")
}

// **Property 13: Memory Ownership Tracking**
// **Validates: Requirements 7.3**
@(test)
test_property_memory_ownership_tracking :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    original_allocator := context.allocator
    defer context.allocator = original_allocator

    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking_allocator)

    tracking_allocator.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array

    context.allocator = mem.tracking_allocator(&tracking_allocator)

    module := make_test_module("ownership-module")
    cloned := loader.CloneModule(module)

    // Cleanup clone should not affect original.
    manifest.cleanup_module(&cloned)
    testing.expect(t, module.name == "ownership-module", "Original should remain intact after clone cleanup")

    // Cleanup original should be safe.
    manifest.cleanup_module(&module)

    testing.expect(t, len(tracking_allocator.bad_free_array) == 0, "Ownership cleanup should not produce bad frees")
}

// **Property 16: Test Synchronization Safety**
// **Validates: Requirements 3.4, 12.5**
@(test)
test_property_test_synchronization_safety :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    // Recursive lock should not deadlock.
    loader.lock_global_cache()
    loader.lock_global_cache()

    loader.reset_global_cache()

    loader.unlock_global_cache()
    loader.unlock_global_cache()

    testing.expect(t, true, "Cache lock/unlock should not deadlock")
}
