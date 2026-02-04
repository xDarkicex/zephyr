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
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Property: All valid modules should be discovered
    testing.expect_value(t, len(modules), 3) // We expect 3 valid modules
    
    // Property: Each discovered module should have a valid name and path
    module_names := make(map[string]bool)
    defer delete(module_names)
    
    for module in modules {
        testing.expect(t, len(module.name) > 0, "Module should have a non-empty name")
        testing.expect(t, len(module.path) > 0, "Module should have a non-empty path")
        testing.expect(t, os.exists(module.path), fmt.tprintf("Module path should exist: %s", module.path))
        
        // Check for duplicates
        testing.expect(t, !(module.name in module_names), fmt.tprintf("Duplicate module name found: %s", module.name))
        module_names[module.name] = true
    }
    
    // Property: Expected modules should be found
    expected_modules := []string{"core", "git-helpers", "nested-module"}
    for expected in expected_modules {
        found := false
        for module in modules {
            if strings.compare(module.name, expected) == 0 {
                found = true
                break
            }
        }
        testing.expect(t, found, fmt.tprintf("Expected module '%s' should be discovered", expected))
    }
}

// **Validates: Requirements 3.2.4**
@(test)
test_discovery_missing_directory :: proc(t: ^testing.T) {
    // Property: Discovery should handle missing directories gracefully
    
    non_existent_dir := "/tmp/does_not_exist_zephyr_test"
    
    modules := loader.discover(non_existent_dir)
    defer delete(modules)
    
    // Property: Should return empty list for non-existent directory
    testing.expect_value(t, len(modules), 0)
}

// **Validates: Requirements 3.2.3**
@(test)
test_discovery_recursive_search :: proc(t: ^testing.T) {
    // Property: Discovery should recursively find modules in subdirectories
    
    base_dir := "/tmp/zephyr_test_recursive"
    defer cleanup_test_directory(base_dir)
    
    // Create nested directory structure
    setup_recursive_test_modules(t, base_dir)
    
    modules := loader.discover(base_dir)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Property: Should find modules at different nesting levels
    testing.expect(t, len(modules) >= 2, "Should find modules in nested directories")
    
    // Check that we found modules at different depths
    depths := make(map[int]bool)
    defer delete(depths)
    
    for module in modules {
        // Count directory separators to determine depth
        relative_path := strings.trim_prefix(module.path, base_dir)
        depth := strings.count(relative_path, "/")
        depths[depth] = true
    }
    
    // Should have modules at different depths
    testing.expect(t, len(depths) > 1, "Should find modules at different directory depths")
}

// **Validates: Requirements 3.2.1**
@(test)
test_discovery_ignores_invalid_manifests :: proc(t: ^testing.T) {
    // Property: Discovery should skip modules with invalid manifests but continue processing
    
    base_dir := "/tmp/zephyr_test_invalid"
    defer cleanup_test_directory(base_dir)
    
    // Create test structure with one valid and one invalid module
    setup_mixed_validity_modules(t, base_dir)
    
    modules := loader.discover(base_dir)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Property: Should find only the valid module
    testing.expect_value(t, len(modules), 1)
    
    if len(modules) > 0 {
        testing.expect(t, strings.compare(modules[0].name, "valid-module") == 0, 
                      fmt.tprintf("Expected 'valid-module', got '%s'", modules[0].name))
    }
}

// Helper function to setup test modules
setup_test_modules :: proc(t: ^testing.T, base_dir: string) {
    // Create base directory
    os.make_directory(base_dir)
    
    // Module 1: core
    core_dir := filepath.join({base_dir, "core"})
    os.make_directory(core_dir)
    core_manifest := filepath.join({core_dir, "module.toml"})
    core_content := `[module]
name = "core"
version = "1.0.0"
description = "Core module"

[load]
priority = 10`
    
    write_ok := os.write_entire_file(core_manifest, transmute([]u8)core_content)
    testing.expect(t, write_ok, "Failed to write core manifest")
    
    // Module 2: git-helpers
    git_dir := filepath.join({base_dir, "git-helpers"})
    os.make_directory(git_dir)
    git_manifest := filepath.join({git_dir, "module.toml"})
    git_content := `[module]
name = "git-helpers"
version = "2.1.0"
description = "Git utility functions"`
    
    write_ok = os.write_entire_file(git_manifest, transmute([]u8)git_content)
    testing.expect(t, write_ok, "Failed to write git-helpers manifest")
    
    // Module 3: nested-module (in subdirectory)
    nested_parent := filepath.join({base_dir, "utilities"})
    os.make_directory(nested_parent)
    nested_dir := filepath.join({nested_parent, "nested-module"})
    os.make_directory(nested_dir)
    nested_manifest := filepath.join({nested_dir, "module.toml"})
    nested_content := `[module]
name = "nested-module"
version = "0.5.0"`
    
    write_ok = os.write_entire_file(nested_manifest, transmute([]u8)nested_content)
    testing.expect(t, write_ok, "Failed to write nested-module manifest")
}

// Helper function to setup recursive test modules
setup_recursive_test_modules :: proc(t: ^testing.T, base_dir: string) {
    os.make_directory(base_dir)
    
    // Level 1 module
    level1_dir := filepath.join({base_dir, "level1"})
    os.make_directory(level1_dir)
    level1_manifest := filepath.join({level1_dir, "module.toml"})
    level1_content := `[module]
name = "level1-module"`
    
    write_ok := os.write_entire_file(level1_manifest, transmute([]u8)level1_content)
    testing.expect(t, write_ok, "Failed to write level1 manifest")
    
    // Level 2 module (deeper nesting)
    level2_parent := filepath.join({base_dir, "deep"})
    os.make_directory(level2_parent)
    level2_dir := filepath.join({level2_parent, "level2"})
    os.make_directory(level2_dir)
    level2_manifest := filepath.join({level2_dir, "module.toml"})
    level2_content := `[module]
name = "level2-module"`
    
    write_ok = os.write_entire_file(level2_manifest, transmute([]u8)level2_content)
    testing.expect(t, write_ok, "Failed to write level2 manifest")
}

// Helper function to setup modules with mixed validity
setup_mixed_validity_modules :: proc(t: ^testing.T, base_dir: string) {
    os.make_directory(base_dir)
    
    // Valid module
    valid_dir := filepath.join({base_dir, "valid"})
    os.make_directory(valid_dir)
    valid_manifest := filepath.join({valid_dir, "module.toml"})
    valid_content := `[module]
name = "valid-module"`
    
    write_ok := os.write_entire_file(valid_manifest, transmute([]u8)valid_content)
    testing.expect(t, write_ok, "Failed to write valid manifest")
    
    // Invalid module (missing name)
    invalid_dir := filepath.join({base_dir, "invalid"})
    os.make_directory(invalid_dir)
    invalid_manifest := filepath.join({invalid_dir, "module.toml"})
    invalid_content := `[module]
version = "1.0.0"`  // Missing required name field
    
    write_ok = os.write_entire_file(invalid_manifest, transmute([]u8)invalid_content)
    testing.expect(t, write_ok, "Failed to write invalid manifest")
}

// Helper function to cleanup test directories
cleanup_test_directory :: proc(dir: string) {
    if os.exists(dir) {
        // Recursively remove directory contents
        remove_directory_recursive(dir)
    }
}

// Helper to recursively remove directory
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
        }
        os.remove(entry_path)
    }
    
    os.remove(dir)
}