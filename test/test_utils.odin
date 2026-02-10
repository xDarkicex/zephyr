package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:fmt"
import "core:testing"
import "base:runtime"

import "../src/loader"

DEFAULT_TEST_TIMEOUT :: 30 * time.Second

set_test_timeout :: proc(t: ^testing.T, duration: time.Duration = DEFAULT_TEST_TIMEOUT) {
    reset_test_state(t)
    testing.set_fail_timeout(t, duration)
}

cleanup_test_allocations :: proc() {
    loader.reset_global_cache()
}

cleanup_test_allocations_proc :: proc(_: rawptr) {
    cleanup_test_allocations()
}

reset_test_state :: proc(t: ^testing.T) {
    loader.reset_global_cache()
    testing.cleanup(t, cleanup_test_allocations_proc, nil)
}

// is_stdlib_allocation returns true for known Odin stdlib one-time allocations
// that are outside project control and should not fail memory-stability tests.
is_stdlib_allocation :: proc(loc: runtime.Source_Code_Location) -> bool {
    if strings.contains(loc.file_path, "os_darwin.odin") && loc.line == 1044 {
        return true
    }
    if strings.contains(loc.file_path, "path.odin") && (loc.line == 548 || loc.line == 579 || loc.line == 584) {
        return true
    }
    if strings.contains(loc.file_path, "conversion.odin") && (loc.line == 106) {
        return true
    }
    return false
}

// ✅ CRITICAL FIX: Force cleanup test directories to prevent EEXIST errors
cleanup_test_directory :: proc(dir_path: string) {
    if dir_path == "" do return
    
    // Force remove directory if it exists
    if os.exists(dir_path) {
        remove_directory_recursive(dir_path)
    }
}

// ✅ CRITICAL FIX: Recursive directory removal
remove_directory_recursive :: proc(dir_path: string) {
    if !os.exists(dir_path) do return
    
    // Get directory contents
    handle, open_err := os.open(dir_path)
    if open_err != os.ERROR_NONE {
        return
    }
    defer os.close(handle)
    
    entries, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        return
    }
    defer os.file_info_slice_delete(entries)
    
    // Remove all contents first
    for entry in entries {
        full_path := filepath.join({dir_path, entry.name})
        defer delete(full_path)
        
        if entry.is_dir {
            remove_directory_recursive(full_path)
        } else {
            os.remove(full_path)
        }
    }
    
    // Remove the directory itself
    os.remove(dir_path)
}

// ✅ CRITICAL FIX: Create unique test directory with timestamp
create_unique_test_directory :: proc(base_name: string) -> string {
    timestamp := time.now()._nsec
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%s_%d", base_name, timestamp)
    unique_name := strings.clone(strings.to_string(builder))
    defer delete(unique_name)

    cwd := os.get_current_directory()
    defer delete(cwd)

    absolute_path := filepath.join({cwd, unique_name})
    
    // Ensure it doesn't exist
    cleanup_test_directory(absolute_path)
    
    // Create the directory
    os.make_directory(absolute_path, 0o755)
    
    return absolute_path
}

// ✅ CRITICAL FIX: Setup test with proper cleanup
setup_test_environment :: proc(test_name: string) -> string {
    base_dir := create_unique_test_directory(test_name)
    return base_dir
}

// ✅ CRITICAL FIX: Teardown test with complete cleanup
teardown_test_environment :: proc(test_dir: string) {
    cleanup_test_directory(test_dir)
    if test_dir != "" {
        delete(test_dir)
    }
}

get_test_modules_dir :: proc() -> string {
    cwd := os.get_current_directory()
    defer delete(cwd)
    return filepath.join({cwd, "test-modules"})
}
