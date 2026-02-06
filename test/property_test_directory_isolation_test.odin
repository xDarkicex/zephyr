package test

import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:strings"

// **Property 11: Test Directory Isolation**
// **Validates: Requirements 6.1, 6.2, 6.3, 6.5**
@(test)
test_property_test_directory_isolation :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)

    base_name := "test_directory_isolation"

    dir_a := setup_test_environment(base_name)
    dir_b := setup_test_environment(base_name)

    // Preserve paths for post-teardown checks (teardown deletes the strings).
    dir_a_copy := strings.clone(dir_a)
    dir_b_copy := strings.clone(dir_b)
    defer {
        if dir_a_copy != "" {
            delete(dir_a_copy)
        }
        if dir_b_copy != "" {
            delete(dir_b_copy)
        }
    }

    testing.expect(t, dir_a != dir_b, "Test directories should be unique per setup")
    testing.expect(t, os.exists(dir_a), "First test directory should exist")
    testing.expect(t, os.exists(dir_b), "Second test directory should exist")

    file_in_a := filepath.join({dir_a, "sentinel.txt"})
    content := "a"
    os.write_entire_file(file_in_a, transmute([]u8)content)
    testing.expect(t, os.exists(file_in_a), "File in first directory should exist")
    delete(file_in_a)

    file_in_b := filepath.join({dir_b, "sentinel.txt"})
    testing.expect(t, !os.exists(file_in_b), "File should not appear in second directory")
    delete(file_in_b)

    teardown_test_environment(dir_a)
    teardown_test_environment(dir_b)

    testing.expect(t, !os.exists(dir_a_copy), "First test directory should be removed on teardown")
    testing.expect(t, !os.exists(dir_b_copy), "Second test directory should be removed on teardown")
}
