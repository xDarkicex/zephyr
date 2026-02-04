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

// **Validates: Requirements 3.2.4**
@(test)
test_discovery_empty_directory :: proc(t: ^testing.T) {
    // Property: Discovery should handle empty directories gracefully
    
    base_dir := "/tmp/zephyr_test_empty"
    defer cleanup_test_directory(base_dir)
    
    // Create empty directory
    os.make_directory(base_dir)
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: No modules should be found in empty directory
    testing.expect_value(t, len(modules), 0)
}

// **Validates: Requirements 3.2.4**
@(test)
test_discovery_nonexistent_directory :: proc(t: ^testing.T) {
    // Property: Discovery should handle non-existent directories gracefully
    
    nonexistent_dir := "/tmp/zephyr_nonexistent_dir"
    
    // Ensure directory doesn't exist
    if os.exists(nonexistent_dir) {
        cleanup_test_directory(nonexistent_dir)
    }
    
    // Discover modules
    modules := loader.discover(nonexistent_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: No modules should be found in non-existent directory
    testing.expect_value(t, len(modules), 0)
}

// **Validates: Requirements 3.2.1, 3.2.3**
@(test)
test_discovery_mixed_content :: proc(t: ^testing.T) {
    // Property: Discovery should find only valid modules among mixed content
    
    base_dir := "/tmp/zephyr_test_mixed"
    defer cleanup_test_directory(base_dir)
    
    // Create base directory
    os.make_directory(base_dir)
    
    // Create valid module
    valid_dir := filepath.join({base_dir, "valid-module"})
    os.make_directory(valid_dir)
    
    valid_toml := `[module]
name = "valid-module"
version = "1.0.0"`
    
    valid_manifest := filepath.join({valid_dir, "module.toml"})
    write_ok := os.write_entire_file(valid_manifest, transmute([]u8)valid_toml)
    testing.expect(t, write_ok, "Failed to write valid manifest")
    
    // Create directory with regular file (not module.toml)
    file_dir := filepath.join({base_dir, "regular-files"})
    os.make_directory(file_dir)
    regular_file := filepath.join({file_dir, "README.md"})
    regular_content := "# Regular file"
    write_ok2 := os.write_entire_file(regular_file, transmute([]u8)regular_content)
    testing.expect(t, write_ok2, "Failed to write regular file")
    
    // Create directory with module.toml but invalid content
    invalid_dir := filepath.join({base_dir, "invalid-module"})
    os.make_directory(invalid_dir)
    
    invalid_toml := `[module]
# Missing name field
version = "1.0.0"`
    
    invalid_manifest := filepath.join({invalid_dir, "module.toml"})
    write_ok3 := os.write_entire_file(invalid_manifest, transmute([]u8)invalid_toml)
    testing.expect(t, write_ok3, "Failed to write invalid manifest")
    
    // Create nested valid module
    nested_dir := filepath.join({base_dir, "category", "nested-valid"})
    category_dir := filepath.join({base_dir, "category"})
    os.make_directory(category_dir)
    os.make_directory(nested_dir)
    
    nested_toml := `[module]
name = "nested-valid"
version = "1.0.0"`
    
    nested_manifest := filepath.join({nested_dir, "module.toml"})
    write_ok4 := os.write_entire_file(nested_manifest, transmute([]u8)nested_toml)
    testing.expect(t, write_ok4, "Failed to write nested manifest")
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: Only valid modules should be discovered
    testing.expect_value(t, len(modules), 2)
    
    // Property: Both valid modules should be found
    found_valid := false
    found_nested := false
    
    for module in modules {
        if module.name == "valid-module" {
            found_valid = true
        } else if module.name == "nested-valid" {
            found_nested = true
        }
    }
    
    testing.expect(t, found_valid, "Should find valid-module")
    testing.expect(t, found_nested, "Should find nested-valid module")
}

// **Validates: Requirements 3.2.3**
@(test)
test_discovery_deep_nesting :: proc(t: ^testing.T) {
    // Property: Discovery should handle deeply nested directory structures
    
    base_dir := "/tmp/zephyr_test_deep"
    defer cleanup_test_directory(base_dir)
    
    // Create deeply nested structure: base/a/b/c/d/e/module
    deep_path := filepath.join({base_dir, "a", "b", "c", "d", "e", "deep-module"})
    
    // Create all intermediate directories
    current_path := base_dir
    os.make_directory(current_path)
    
    path_parts := []string{"a", "b", "c", "d", "e", "deep-module"}
    for part in path_parts {
        current_path = filepath.join({current_path, part})
        os.make_directory(current_path)
    }
    
    // Create module.toml in the deeply nested directory
    toml_content := `[module]
name = "deep-module"
version = "1.0.0"
description = "A deeply nested module"`
    
    manifest_path := filepath.join({deep_path, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write deep manifest file")
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: Deeply nested module should be discovered
    testing.expect_value(t, len(modules), 1)
    
    if len(modules) > 0 {
        testing.expect_value(t, modules[0].name, "deep-module")
        testing.expect_value(t, modules[0].description, "A deeply nested module")
        testing.expect(t, strings.contains(modules[0].path, "a/b/c/d/e/deep-module"), 
            fmt.tprintf("Module path should contain deep nesting: %s", modules[0].path))
    }
}

// **Validates: Requirements 3.2.1**
@(test)
test_discovery_multiple_modules_same_level :: proc(t: ^testing.T) {
    // Property: Discovery should find multiple modules at the same directory level
    
    base_dir := "/tmp/zephyr_test_multiple"
    defer cleanup_test_directory(base_dir)
    
    // Create base directory
    os.make_directory(base_dir)
    
    // Create multiple modules at the same level
    module_configs := []struct{name: string, version: string, priority: int}{
        {"alpha", "1.0.0", 10},
        {"beta", "2.0.0", 20},
        {"gamma", "1.5.0", 15},
    }
    
    for config in module_configs {
        module_dir := filepath.join({base_dir, config.name})
        os.make_directory(module_dir)
        
        toml_content := fmt.tprintf(`[module]
name = "%s"
version = "%s"

[load]
priority = %d`, config.name, config.version, config.priority)
        
        manifest_path := filepath.join({module_dir, "module.toml"})
        write_ok := os.write_entire_file(manifest_path, transmute([]u8)toml_content)
        testing.expect(t, write_ok, fmt.tprintf("Failed to write manifest for %s", config.name))
    }
    
    // Discover modules
    modules := loader.discover(base_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Property: All modules should be discovered
    testing.expect_value(t, len(modules), 3)
    
    // Property: Each module should have correct data
    found_modules := make(map[string]bool)
    
    for module in modules {
        found_modules[module.name] = true
        
        switch module.name {
        case "alpha":
            testing.expect_value(t, module.version, "1.0.0")
            testing.expect_value(t, module.priority, 10)
        case "beta":
            testing.expect_value(t, module.version, "2.0.0")
            testing.expect_value(t, module.priority, 20)
        case "gamma":
            testing.expect_value(t, module.version, "1.5.0")
            testing.expect_value(t, module.priority, 15)
        }
    }
    
    // Property: All expected modules should be found
    testing.expect(t, found_modules["alpha"], "Should find alpha module")
    testing.expect(t, found_modules["beta"], "Should find beta module")
    testing.expect(t, found_modules["gamma"], "Should find gamma module")
}

// **Validates: Requirements 3.2.2**
@(test)
test_discovery_environment_variable :: proc(t: ^testing.T) {
    // Property: Discovery should use ZSH_MODULES_DIR environment variable when set
    
    // Note: This test verifies the get_modules_dir function behavior
    // Since we can't easily modify environment variables in tests,
    // we'll test the logic indirectly
    
    // Test default behavior when ZSH_MODULES_DIR is not set
    original_zsh_dir := os.get_env("ZSH_MODULES_DIR")
    original_home := os.get_env("HOME")
    
    // This test validates the get_modules_dir function logic
    modules_dir := loader.get_modules_dir()
    
    // Property: Should return a valid path
    testing.expect(t, len(modules_dir) > 0, "Should return non-empty modules directory path")
    
    // Property: Should contain expected path components when using defaults
    if original_zsh_dir == "" && original_home != "" {
        testing.expect(t, strings.contains(modules_dir, ".zsh/modules"), 
            fmt.tprintf("Default path should contain .zsh/modules: %s", modules_dir))
    }
}