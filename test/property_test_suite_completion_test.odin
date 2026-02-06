package test

import "core:testing"
import "core:time"
import "core:os"

import "../src/loader"
import "../src/manifest"

// **Validates: Requirements 3.1**
@(test)
test_property_test_suite_completion :: proc(t: ^testing.T) {
    set_test_timeout(t, 5 * time.Minute)
    reset_test_state(t)

        test_dir := get_test_modules_dir()
        defer delete(test_dir)
    if !os.exists(test_dir) {
        testing.fail_now(t, "Test modules directory does not exist")
    }

    // Run the core workflow multiple times to ensure no hangs or deadlocks.
    for _ in 0..<3 {
        modules := loader.discover(test_dir)
        resolved, err := loader.resolve(modules)
        defer cleanup_error_message(err)

        testing.expect(t, err == "", "Resolution should succeed")

        if resolved != nil {
            manifest.cleanup_modules(resolved[:])
            delete(resolved)
        }

        manifest.cleanup_modules(modules[:])
        delete(modules)
        loader.reset_global_cache()
    }
}
