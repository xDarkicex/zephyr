package test

import "core:testing"
import "core:strings"
import "core:os"

import "../src/loader"
import "../src/manifest"

collect_module_names :: proc(modules: [dynamic]manifest.Module) -> [dynamic]string {
    names := make([dynamic]string)
    for module in modules {
        if module.name != "" {
            append(&names, strings.clone(module.name))
        }
    }
    return names
}

cleanup_names :: proc(names: ^[dynamic]string) {
    if names == nil || names^ == nil do return

    for &name in names^ {
        if name != "" {
            delete(name)
            name = ""
        }
    }
    delete(names^)
    names^ = nil
}

names_match_as_sets :: proc(a: [dynamic]string, b: [dynamic]string) -> bool {
    if len(a) != len(b) do return false

    for name in a {
        found := false
        for other in b {
            if name == other {
                found = true
                break
            }
        }
        if !found do return false
    }

    return true
}

// **Validates: Requirements 3.2, 12.1, 12.2, 12.3, 12.4**
@(test)
test_property_test_state_isolation :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    loader.lock_global_cache()
    defer loader.unlock_global_cache()

    test_dir := get_test_modules_dir()
    defer delete(test_dir)
    if !os.exists(test_dir) {
        testing.fail_now(t, "Test modules directory does not exist")
    }

    // Global cache should be clean at start of test
    module_count, _, _, initialized := loader.get_global_cache_stats()
    testing.expect(t, !initialized && module_count == 0, "Global cache should be reset at test start")

    // First run
    modules_a := loader.discover(test_dir)
    resolved_a, err_a := loader.resolve(modules_a)
    defer cleanup_error_message(err_a)
    testing.expect(t, err_a == "", "Resolution should succeed in first run")

    names_a := collect_module_names(resolved_a)

    if resolved_a != nil {
        manifest.cleanup_modules(resolved_a[:])
        delete(resolved_a)
    }
    manifest.cleanup_modules(modules_a[:])
    delete(modules_a)

    // Reset cache and verify clean state
    loader.reset_global_cache()
    module_count, _, _, initialized = loader.get_global_cache_stats()
    testing.expect(t, !initialized && module_count == 0, "Global cache should reset between runs")

    // Second run
    modules_b := loader.discover(test_dir)
    resolved_b, err_b := loader.resolve(modules_b)
    defer cleanup_error_message(err_b)
    testing.expect(t, err_b == "", "Resolution should succeed in second run")

    names_b := collect_module_names(resolved_b)

    testing.expect(t, names_match_as_sets(names_a, names_b), "Module results should match across isolated runs")

    if resolved_b != nil {
        manifest.cleanup_modules(resolved_b[:])
        delete(resolved_b)
    }
    manifest.cleanup_modules(modules_b[:])
    delete(modules_b)

    cleanup_names(&names_a)
    cleanup_names(&names_b)

    loader.reset_global_cache()
}
