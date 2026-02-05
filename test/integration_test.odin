package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "../src/loader"
import "../src/manifest"

// Integration tests for Zephyr Shell Loader
// These tests use real module directory structures and test the complete workflow

@(test)
test_real_module_directory_structure :: proc(t: ^testing.T) {
    // Test with the existing test-modules directory
    test_dir := "test-modules"
    
    // Verify test directory exists
    if !os.exists(test_dir) {
        testing.fail_now(t, "Test modules directory does not exist")
    }
    
    // Test discovery with real modules
    modules := loader.discover(test_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Should find both core and git-helpers modules
    testing.expect(t, len(modules) >= 2, "Should discover at least 2 modules")
    
    // Verify specific modules are found
    found_core := false
    found_git_helpers := false
    
    for module in modules {
        switch module.name {
        case "core":
            found_core = true
            testing.expect(t, module.version == "1.0.0", "Core module version should be 1.0.0")
            testing.expect(t, module.priority == 10, "Core module priority should be 10")
            testing.expect(t, len(module.files) == 3, "Core module should have 3 files")
        case "git-helpers":
            found_git_helpers = true
            testing.expect(t, module.version == "1.2.0", "Git-helpers version should be 1.2.0")
            testing.expect(t, module.priority == 50, "Git-helpers priority should be 50")
            testing.expect(t, len(module.required) == 1, "Git-helpers should have 1 dependency")
            testing.expect(t, module.required[0] == "core", "Git-helpers should depend on core")
        }
    }
    
    testing.expect(t, found_core, "Should find core module")
    testing.expect(t, found_git_helpers, "Should find git-helpers module")
}

@(test)
test_dependency_resolution_with_real_modules :: proc(t: ^testing.T) {
    // Test dependency resolution with real module structure
    test_dir := "test-modules"
    
    modules := loader.discover(test_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Resolve dependencies
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", fmt.tprintf("Dependency resolution should succeed, got error: %s", err))
    testing.expect(t, resolved_modules != nil, "Should get resolved modules")
    testing.expect(t, len(resolved_modules) >= 2, "Should resolve at least 2 modules")
    
    // Verify load order: core should come before git-helpers
    core_index := -1
    git_helpers_index := -1
    
    for module, i in resolved_modules {
        switch module.name {
        case "core":
            core_index = i
        case "git-helpers":
            git_helpers_index = i
        }
    }
    
    testing.expect(t, core_index != -1, "Core module should be in resolved list")
    testing.expect(t, git_helpers_index != -1, "Git-helpers module should be in resolved list")
    testing.expect(t, core_index < git_helpers_index, "Core should be loaded before git-helpers")
}

@(test)
test_shell_code_generation_with_real_modules :: proc(t: ^testing.T) {
    // Test shell code generation with real modules
    test_dir := "test-modules"
    
    modules := loader.discover(test_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Dependency resolution should succeed")
    
    // Capture shell code output
    // Note: In a real integration test, we would redirect stdout and capture the output
    // For now, we'll test that emit doesn't crash
    loader.emit(resolved_modules)
    
    // The emit function writes to stdout, so we can't easily capture it in this test
    // In a more sophisticated test setup, we would redirect stdout to a buffer
    // and verify the generated shell code content
}

@(test)
test_missing_dependency_error :: proc(t: ^testing.T) {
    // Create a temporary module structure with missing dependency
    temp_dir := "test_temp_missing_dep"
    defer remove_directory_recursive(temp_dir)
    
    // Create directory structure
    os.make_directory(temp_dir)
    os.make_directory(filepath.join({temp_dir, "broken-module"}))
    
    // Create a module that depends on non-existent module
    manifest_content := `[module]
name = "broken-module"
version = "1.0.0"
description = "Module with missing dependency"

[dependencies]
required = ["non-existent-module"]

[load]
priority = 10
files = ["test.zsh"]
`
    
    manifest_path := filepath.join({temp_dir, "broken-module", "module.toml"})
    os.write_entire_file(manifest_path, transmute([]u8)manifest_content)
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover the broken module")
    
    // Resolution should fail
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err != "", "Should get error for missing dependency")
    testing.expect(t, strings.contains(err, "non-existent-module"), "Error should mention missing module")
}

@(test)
test_integration_circular_dependency_detection :: proc(t: ^testing.T) {
    // Create a temporary module structure with circular dependencies
    temp_dir := "test_temp_circular"
    defer remove_directory_recursive(temp_dir)
    
    // Create directory structure
    os.make_directory(temp_dir)
    os.make_directory(filepath.join({temp_dir, "module-a"}))
    os.make_directory(filepath.join({temp_dir, "module-b"}))
    
    // Module A depends on B
    manifest_a := `[module]
name = "module-a"
version = "1.0.0"
description = "Module A"

[dependencies]
required = ["module-b"]

[load]
priority = 10
files = ["a.zsh"]
`
    
    // Module B depends on A (circular)
    manifest_b := `[module]
name = "module-b"
version = "1.0.0"
description = "Module B"

[dependencies]
required = ["module-a"]

[load]
priority = 20
files = ["b.zsh"]
`
    
    manifest_a_path := filepath.join({temp_dir, "module-a", "module.toml"})
    manifest_b_path := filepath.join({temp_dir, "module-b", "module.toml"})
    
    os.write_entire_file(manifest_a_path, transmute([]u8)manifest_a)
    os.write_entire_file(manifest_b_path, transmute([]u8)manifest_b)
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 2, "Should discover both modules")
    
    // Resolution should fail due to circular dependency
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err != "", "Should get error for circular dependency")
    testing.expect(t, strings.contains(err, "Circular dependency detected"), 
                   fmt.tprintf("Error should mention circular dependency, got: %s", err))
}

@(test)
test_empty_directory :: proc(t: ^testing.T) {
    // Test with empty directory
    temp_dir := "test_temp_empty"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 0, "Should find no modules in empty directory")
    
    // Resolution should succeed with empty list
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Resolution should succeed with empty module list")
    testing.expect(t, len(resolved_modules) == 0, "Should get empty resolved list")
}

@(test)
test_nested_module_discovery :: proc(t: ^testing.T) {
    // Test discovery with nested directory structure
    temp_dir := "test_temp_nested"
    defer remove_directory_recursive(temp_dir)
    
    // Create nested structure
    os.make_directory(temp_dir)
    os.make_directory(filepath.join({temp_dir, "category1"}))
    os.make_directory(filepath.join({temp_dir, "category1", "module1"}))
    os.make_directory(filepath.join({temp_dir, "category2"}))
    os.make_directory(filepath.join({temp_dir, "category2", "module2"}))
    
    // Create modules in nested directories
    manifest1 := `[module]
name = "module1"
version = "1.0.0"
description = "Nested module 1"

[load]
priority = 10
files = ["mod1.zsh"]
`
    
    manifest2 := `[module]
name = "module2"
version = "1.0.0"
description = "Nested module 2"

[dependencies]
required = ["module1"]

[load]
priority = 20
files = ["mod2.zsh"]
`
    
    manifest1_path := filepath.join({temp_dir, "category1", "module1", "module.toml"})
    manifest2_path := filepath.join({temp_dir, "category2", "module2", "module.toml"})
    
    os.write_entire_file(manifest1_path, transmute([]u8)manifest1)
    os.write_entire_file(manifest2_path, transmute([]u8)manifest2)
    
    // Test discovery
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 2, "Should discover modules in nested directories")
    
    // Test resolution
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve nested modules successfully")
    testing.expect(t, len(resolved_modules) == 2, "Should resolve both nested modules")
    
    // Verify load order
    testing.expect(t, resolved_modules[0].name == "module1", "Module1 should load first")
    testing.expect(t, resolved_modules[1].name == "module2", "Module2 should load second")
}