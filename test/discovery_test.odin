package test

import "core:testing"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"

import "../src/loader"
import "../src/manifest"

// **Validates: Requirements 3.2.1, 3.2.3**
@(test)
test_discovery_completeness :: proc(t: ^testing.T) {
    // Property: Discovery should find all modules with valid module.toml files in a directory tree
    
    // Create a temporary directory structure for testing
    base_dir := "/tmp/zephyr_test_modules"
    defer cleanup_test_directory(base_dir)
    
    // Setup test directory structure
    setup_test_modules(t, base_dir)
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: All valid modules should be discovered
    testing.expect_value(t, len(modules), 3) // We expect 3 valid modules
    
    // Use arena allocator for temporary test data
    
    // Property: Each discovered module should have a valid name and path
    module_names := make(map[string]bool)
    
    for module in modules {
        testing.expect(t, len(module.name) > 0, "Module should have a non-empty name")
        testing.expect(t, len(module.path) > 0, "Module should have a non-empty path")
        testing.expect(t, os.exists(module.path), fmt.tprintf("Module path should exist: %s", module.path))
        
        // Check for duplicates
        testing.expect(t, !(module.name in module_names), fmt.tprintf("Duplicate module name found: %s", module.name))
        module_names[module.name] = true
    }
    
    // Property: Expected modules should be found
    expected_modules := []string{"core", "utils", "nested-module"}
    for expected in expected_modules {
        found := false
        for module in modules {
            if module.name == expected {
                found = true
                break
            }
        }
        testing.expect(t, found, fmt.tprintf("Expected module '%s' should be discovered", expected))
    }
}

// **Validates: Requirements 3.2.3**
@(test)
test_discovery_recursive_search :: proc(t: ^testing.T) {
    // Property: Discovery should recursively search subdirectories
    
    // Create a nested directory structure
    base_dir := "/tmp/zephyr_test_recursive"
    defer cleanup_test_directory(base_dir)
    
    // Create nested structure: base/level1/level2/module
    os.make_directory(base_dir)
    nested_path := filepath.join({base_dir, "level1", "level2", "deep-module"})
    os.make_directory(filepath.join({base_dir, "level1"}))
    os.make_directory(filepath.join({base_dir, "level1", "level2"}))
    os.make_directory(nested_path)
    
    // Create a module.toml in the deeply nested directory
    toml_content := `[module]
name = "deep-module"
version = "1.0.0"

[load]
files = ["init.zsh"]`
    
    manifest_path := filepath.join({nested_path, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write nested manifest file")
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: Nested module should be discovered
    testing.expect_value(t, len(modules), 1)
    
    if len(modules) > 0 {
        testing.expect_value(t, modules[0].name, "deep-module")
        testing.expect(t, strings.contains(modules[0].path, "level1/level2/deep-module"), 
            fmt.tprintf("Module path should contain nested structure: %s", modules[0].path))
    }
}

// **Validates: Requirements 3.2.4**
@(test)
test_discovery_ignores_invalid_manifests :: proc(t: ^testing.T) {
    // Property: Discovery should ignore directories with invalid or missing manifests
    
    base_dir := "/tmp/zephyr_test_invalid"
    defer cleanup_test_directory(base_dir)
    
    // Create directory with valid module
    valid_dir := filepath.join({base_dir, "valid-module"})
    os.make_directory(base_dir)
    os.make_directory(valid_dir)
    
    valid_toml := `[module]
name = "valid-module"
version = "1.0.0"`
    
    valid_manifest := filepath.join({valid_dir, "module.toml"})
    write_ok := os.write_entire_file(valid_manifest, transmute([]u8)valid_toml)
    testing.expect(t, write_ok, "Failed to write valid manifest")
    
    // Create directory with invalid module (missing name)
    invalid_dir := filepath.join({base_dir, "invalid-module"})
    os.make_directory(invalid_dir)
    
    invalid_toml := `[module]
version = "1.0.0"
# Missing required name field`
    
    invalid_manifest := filepath.join({invalid_dir, "module.toml"})
    write_ok2 := os.write_entire_file(invalid_manifest, transmute([]u8)invalid_toml)
    testing.expect(t, write_ok2, "Failed to write invalid manifest")
    
    // Create directory with no manifest
    no_manifest_dir := filepath.join({base_dir, "no-manifest"})
    os.make_directory(no_manifest_dir)
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: Only valid modules should be discovered
    testing.expect_value(t, len(modules), 1)
    
    if len(modules) > 0 {
        testing.expect_value(t, modules[0].name, "valid-module")
    }
}

// Helper function to setup test modules
setup_test_modules :: proc(t: ^testing.T, base_dir: string) {
    // Clean up any existing test directory
    if os.exists(base_dir) {
        cleanup_test_directory(base_dir)
    }
    
    // Create base directory
    os.make_directory(base_dir)
    
    // Create core module
    core_dir := filepath.join({base_dir, "core"})
    os.make_directory(core_dir)
    
    core_toml := `[module]
name = "core"
version = "1.0.0"
description = "Core utilities"

[load]
priority = 10
files = ["init.zsh"]`
    
    core_manifest := filepath.join({core_dir, "module.toml"})
    write_ok := os.write_entire_file(core_manifest, transmute([]u8)core_toml)
    testing.expect(t, write_ok, "Failed to write core manifest")
    
    // Create utils module
    utils_dir := filepath.join({base_dir, "utils"})
    os.make_directory(utils_dir)
    
    utils_toml := `[module]
name = "utils"
version = "2.0.0"
description = "Utility functions"

[dependencies]
required = ["core"]

[load]
priority = 20
files = ["utils.zsh"]`
    
    utils_manifest := filepath.join({utils_dir, "module.toml"})
    write_ok2 := os.write_entire_file(utils_manifest, transmute([]u8)utils_toml)
    testing.expect(t, write_ok2, "Failed to write utils manifest")
    
    // Create nested module
    nested_dir := filepath.join({base_dir, "category", "nested-module"})
    category_dir := filepath.join({base_dir, "category"})
    os.make_directory(category_dir)
    os.make_directory(nested_dir)
    
    nested_toml := `[module]
name = "nested-module"
version = "1.5.0"
description = "A nested module"

[load]
files = ["nested.zsh"]`
    
    nested_manifest := filepath.join({nested_dir, "module.toml"})
    write_ok3 := os.write_entire_file(nested_manifest, transmute([]u8)nested_toml)
    testing.expect(t, write_ok3, "Failed to write nested manifest")
}

// Helper function to cleanup test directory
cleanup_test_directory :: proc(dir: string) {
    if os.exists(dir) {
        // Remove all files and subdirectories recursively
        remove_directory_recursive(dir)
    }
}

// Helper function to recursively remove directory
remove_directory_recursive :: proc(dir: string) {
    handle, err := os.open(dir)
    if err != os.ERROR_NONE {
        return
    }
    defer os.close(handle)
    
    entries, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        return
    }
    defer os.file_info_slice_delete(entries)
    
    for entry in entries {
        entry_path := filepath.join({dir, entry.name})
        if entry.is_dir {
            remove_directory_recursive(entry_path)
            os.remove(entry_path)
        } else {
            os.remove(entry_path)
        }
    }
    
    os.remove(dir)
}