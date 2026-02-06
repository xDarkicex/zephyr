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
    set_test_timeout(t)
    reset_test_state(t)
    // Test with the existing test-modules directory
    test_dir := get_test_modules_dir()
    defer delete(test_dir)
    
    // Verify test directory exists
    if !os.exists(test_dir) {
        testing.fail_now(t, "Test modules directory does not exist")
    }
    
    // Test discovery with real modules
    modules := loader.discover(test_dir)
    defer delete(modules)
    
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

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_dependency_resolution_with_real_modules :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test dependency resolution with real module structure
    test_dir := get_test_modules_dir()
    defer delete(test_dir)
    
    modules := loader.discover(test_dir)
    defer delete(modules)
    
    // Resolve dependencies
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
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

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_shell_code_generation_with_real_modules :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test shell code generation with real modules
    test_dir := get_test_modules_dir()
    defer delete(test_dir)
    
    modules := loader.discover(test_dir)
    defer delete(modules)
    
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err == "", "Dependency resolution should succeed")
    
    // Capture shell code output
    // Note: In a real integration test, we would redirect stdout and capture the output
    // For now, we'll test that emit doesn't crash
    loader.emit(resolved_modules)
    
    // The emit function writes to stdout, so we can't easily capture it in this test
    // In a more sophisticated test setup, we would redirect stdout to a buffer
    // and verify the generated shell code content

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_missing_dependency_error :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Create a temporary module structure with missing dependency
    temp_dir := setup_test_environment("test_temp_missing_dep")
    defer teardown_test_environment(temp_dir)
    
    // Create directory structure
    broken_dir := filepath.join({temp_dir, "broken-module"})
    defer delete(broken_dir)
    os.make_directory(broken_dir)
    
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
    defer delete(manifest_path)
    os.write_entire_file(manifest_path, transmute([]u8)manifest_content)
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer delete(modules)
    
    testing.expect(t, len(modules) == 1, "Should discover the broken module")
    
    // Resolution should fail
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err != "", "Should get error for missing dependency")
    testing.expect(t, strings.contains(err, "non-existent-module"), "Error should mention missing module")

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_integration_circular_dependency_detection :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Create a temporary module structure with circular dependencies
    temp_dir := setup_test_environment("test_temp_circular")
    defer teardown_test_environment(temp_dir)
    
    // Create directory structure
    module_a_dir := filepath.join({temp_dir, "module-a"})
    defer delete(module_a_dir)
    module_b_dir := filepath.join({temp_dir, "module-b"})
    defer delete(module_b_dir)
    os.make_directory(module_a_dir)
    os.make_directory(module_b_dir)
    
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
    defer delete(manifest_a_path)
    manifest_b_path := filepath.join({temp_dir, "module-b", "module.toml"})
    defer delete(manifest_b_path)
    
    os.write_entire_file(manifest_a_path, transmute([]u8)manifest_a)
    os.write_entire_file(manifest_b_path, transmute([]u8)manifest_b)
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer delete(modules)
    
    testing.expect(t, len(modules) == 2, "Should discover both modules")
    
    // Resolution should fail due to circular dependency
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err != "", "Should get error for circular dependency")
    testing.expect(t, strings.contains(err, "Circular dependency detected"), 
                   fmt.tprintf("Error should mention circular dependency, got: %s", err))

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_empty_directory :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test with empty directory
    temp_dir := setup_test_environment("test_temp_empty")
    defer teardown_test_environment(temp_dir)
    
    modules := loader.discover(temp_dir)
    defer delete(modules)
    
    testing.expect(t, len(modules) == 0, "Should find no modules in empty directory")
    
    // Resolution should succeed with empty list
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err == "", "Resolution should succeed with empty module list")
    testing.expect(t, len(resolved_modules) == 0, "Should get empty resolved list")

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_nested_module_discovery :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test discovery with nested directory structure
    temp_dir := setup_test_environment("test_temp_nested")
    defer teardown_test_environment(temp_dir)
    
    // Create nested structure
    category1_dir := filepath.join({temp_dir, "category1"})
    defer delete(category1_dir)
    category1_module1_dir := filepath.join({temp_dir, "category1", "module1"})
    defer delete(category1_module1_dir)
    category2_dir := filepath.join({temp_dir, "category2"})
    defer delete(category2_dir)
    category2_module2_dir := filepath.join({temp_dir, "category2", "module2"})
    defer delete(category2_module2_dir)
    os.make_directory(category1_dir)
    os.make_directory(category1_module1_dir)
    os.make_directory(category2_dir)
    os.make_directory(category2_module2_dir)
    
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
    defer delete(manifest1_path)
    manifest2_path := filepath.join({temp_dir, "category2", "module2", "module.toml"})
    defer delete(manifest2_path)
    
    os.write_entire_file(manifest1_path, transmute([]u8)manifest1)
    os.write_entire_file(manifest2_path, transmute([]u8)manifest2)
    
    // Test discovery
    modules := loader.discover(temp_dir)
    defer delete(modules)
    
    testing.expect(t, len(modules) == 2, "Should discover modules in nested directories")
    
    // Test resolution
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err == "", "Should resolve nested modules successfully")
    testing.expect(t, len(resolved_modules) == 2, "Should resolve both nested modules")
    
    // Verify load order
    testing.expect(t, resolved_modules[0].name == "module1", "Module1 should load first")
    testing.expect(t, resolved_modules[1].name == "module2", "Module2 should load second")

    cleanup_modules_and_cache(modules[:])
}
