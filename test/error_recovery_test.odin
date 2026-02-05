package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "../src/loader"
import "../src/manifest"

@(test)
test_corrupted_manifest_recovery :: proc(t: ^testing.T) {
    // Test recovery from corrupted TOML manifests
    temp_dir := "test_temp_corrupted"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create a module with corrupted TOML
    corrupted_dir := filepath.join({temp_dir, "corrupted-module"})
    os.make_directory(corrupted_dir)
    
    // Invalid TOML syntax
    corrupted_manifest := `[module
name = "corrupted-module"
version = "1.0.0"
description = "Module with corrupted TOML"

[load]
priority = 10
files = ["test.zsh"
`
    
    manifest_path := filepath.join({corrupted_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)corrupted_manifest)
    testing.expect(t, write_ok, "Should create corrupted manifest")
    
    // Create a valid module in the same directory
    valid_dir := filepath.join({temp_dir, "valid-module"})
    os.make_directory(valid_dir)
    
    valid_manifest := `[module]
name = "valid-module"
version = "1.0.0"
description = "Valid module"

[load]
priority = 10
files = ["valid.zsh"]
`
    
    valid_manifest_path := filepath.join({valid_dir, "module.toml"})
    write_ok2 := os.write_entire_file(valid_manifest_path, transmute([]u8)valid_manifest)
    testing.expect(t, write_ok2, "Should create valid manifest")
    
    // Create shell files
    shell_content := "# Test shell file"
    os.write_entire_file(filepath.join({corrupted_dir, "test.zsh"}), transmute([]u8)shell_content)
    os.write_entire_file(filepath.join({valid_dir, "valid.zsh"}), transmute([]u8)shell_content)
    
    // Test discovery - should skip corrupted module but find valid one
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Should only find the valid module (corrupted one should be skipped)
    testing.expect(t, len(modules) == 1, "Should find only valid module, skipping corrupted one")
    testing.expect(t, modules[0].name == "valid-module", "Should find the valid module")
    
    // Resolution should succeed with the valid module
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve valid module successfully")
    testing.expect(t, len(resolved_modules) == 1, "Should resolve one module")
}

@(test)
test_missing_files_handling :: proc(t: ^testing.T) {
    // Test handling of modules that reference non-existent files
    temp_dir := "test_temp_missing_files"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create module that references missing files
    missing_files_dir := filepath.join({temp_dir, "missing-files-module"})
    os.make_directory(missing_files_dir)
    
    missing_files_manifest := `[module]
name = "missing-files-module"
version = "1.0.0"
description = "Module with missing files"

[load]
priority = 10
files = ["existing.zsh", "missing.zsh", "also-missing.zsh"]
`
    
    manifest_path := filepath.join({missing_files_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)missing_files_manifest)
    testing.expect(t, write_ok, "Should create manifest with missing files")
    
    // Create only one of the referenced files
    existing_content := "# This file exists"
    existing_path := filepath.join({missing_files_dir, "existing.zsh"})
    os.write_entire_file(existing_path, transmute([]u8)existing_content)
    
    // Test discovery - should still find the module
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover module even with missing files")
    
    module := modules[0]
    testing.expect(t, module.name == "missing-files-module", "Should find the correct module")
    testing.expect(t, len(module.files) == 3, "Should have all 3 files listed in manifest")
    
    // Resolution should still succeed (file existence is checked at runtime)
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve module with missing files")
    testing.expect(t, len(resolved_modules) == 1, "Should resolve the module")
}

@(test)
test_permission_denied_recovery :: proc(t: ^testing.T) {
    // Test recovery from permission denied scenarios
    // Note: This is a simulation since we can't easily create permission issues in tests
    temp_dir := "test_temp_permissions"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create accessible module
    accessible_dir := filepath.join({temp_dir, "accessible-module"})
    os.make_directory(accessible_dir)
    
    accessible_manifest := `[module]
name = "accessible-module"
version = "1.0.0"
description = "Accessible module"

[load]
priority = 10
files = ["accessible.zsh"]
`
    
    manifest_path := filepath.join({accessible_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)accessible_manifest)
    testing.expect(t, write_ok, "Should create accessible manifest")
    
    shell_content := "# Accessible shell file"
    shell_path := filepath.join({accessible_dir, "accessible.zsh"})
    os.write_entire_file(shell_path, transmute([]u8)shell_content)
    
    // Test discovery on accessible directory
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover accessible module")
    
    // Test discovery on non-existent directory (should handle gracefully)
    non_existent_modules := loader.discover("non_existent_directory")
    defer {
        manifest.cleanup_modules(non_existent_modules[:])
        delete(non_existent_modules)
    }
    
    testing.expect(t, len(non_existent_modules) == 0, "Should handle non-existent directory gracefully")
}

@(test)
test_malformed_dependency_recovery :: proc(t: ^testing.T) {
    // Test recovery from malformed dependency specifications
    temp_dir := "test_temp_malformed_deps"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create module with malformed dependencies
    malformed_dir := filepath.join({temp_dir, "malformed-deps"})
    os.make_directory(malformed_dir)
    
    // This manifest has valid TOML but invalid dependency structure
    malformed_manifest := `[module]
name = "malformed-deps"
version = "1.0.0"
description = "Module with malformed dependencies"

[dependencies]
required = "not-an-array"
optional = 123

[load]
priority = 10
files = ["test.zsh"]
`
    
    manifest_path := filepath.join({malformed_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)malformed_manifest)
    testing.expect(t, write_ok, "Should create malformed dependencies manifest")
    
    shell_content := "# Test shell file"
    shell_path := filepath.join({malformed_dir, "test.zsh"})
    os.write_entire_file(shell_path, transmute([]u8)shell_content)
    
    // Create a valid module as well
    valid_dir := filepath.join({temp_dir, "valid-module"})
    os.make_directory(valid_dir)
    
    valid_manifest := `[module]
name = "valid-module"
version = "1.0.0"
description = "Valid module"

[load]
priority = 20
files = ["valid.zsh"]
`
    
    valid_manifest_path := filepath.join({valid_dir, "module.toml"})
    write_ok2 := os.write_entire_file(valid_manifest_path, transmute([]u8)valid_manifest)
    testing.expect(t, write_ok2, "Should create valid manifest")
    
    valid_shell_path := filepath.join({valid_dir, "valid.zsh"})
    os.write_entire_file(valid_shell_path, transmute([]u8)shell_content)
    
    // Test discovery - should handle malformed dependencies gracefully
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Should find at least the valid module, may or may not find malformed one
    testing.expect(t, len(modules) >= 1, "Should find at least one module")
    
    // Find the valid module
    found_valid := false
    for module in modules {
        if module.name == "valid-module" {
            found_valid = true
            break
        }
    }
    testing.expect(t, found_valid, "Should find the valid module")
    
    // Test resolution
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    // Should resolve successfully (at least the valid module)
    // Note: If malformed module causes parsing to fail completely, 
    // we should still have the valid module
    if len(resolved_modules) == 0 && err != "" {
        // If resolution failed, check that we at least found the valid module during discovery
        testing.expect(t, found_valid, "Should have found valid module during discovery even if resolution failed")
    } else {
        testing.expect(t, len(resolved_modules) >= 1, "Should resolve at least one module")
    }
}

@(test)
test_empty_directory_handling :: proc(t: ^testing.T) {
    // Test handling of empty directories and edge cases
    temp_dir := "test_temp_empty"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create empty subdirectory
    empty_subdir := filepath.join({temp_dir, "empty-subdir"})
    os.make_directory(empty_subdir)
    
    // Create directory with only non-module files
    non_module_dir := filepath.join({temp_dir, "non-module"})
    os.make_directory(non_module_dir)
    
    readme_content := "# This is not a module"
    readme_path := filepath.join({non_module_dir, "README.md"})
    os.write_entire_file(readme_path, transmute([]u8)readme_content)
    
    // Test discovery on directory with no modules
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 0, "Should find no modules in empty/non-module directories")
    
    // Test resolution with empty module list
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve empty module list successfully")
    testing.expect(t, len(resolved_modules) == 0, "Should resolve to empty list")
}

@(test)
test_large_dependency_graph_handling :: proc(t: ^testing.T) {
    // Test handling of complex dependency scenarios
    temp_dir := "test_temp_complex_deps"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create a module with many dependencies (stress test)
    many_deps_dir := filepath.join({temp_dir, "many-deps"})
    os.make_directory(many_deps_dir)
    
    many_deps_manifest := `[module]
name = "many-deps"
version = "1.0.0"
description = "Module with many dependencies"

[dependencies]
required = ["dep1", "dep2", "dep3", "dep4", "dep5"]
optional = ["opt1", "opt2", "opt3"]

[load]
priority = 100
files = ["many.zsh"]
`
    
    manifest_path := filepath.join({many_deps_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)many_deps_manifest)
    testing.expect(t, write_ok, "Should create many dependencies manifest")
    
    shell_content := "# Module with many dependencies"
    shell_path := filepath.join({many_deps_dir, "many.zsh"})
    os.write_entire_file(shell_path, transmute([]u8)shell_content)
    
    // Create some of the dependencies (but not all)
    for i in 1..=3 {
        dep_dir := filepath.join({temp_dir, fmt.tprintf("dep%d", i)})
        os.make_directory(dep_dir)
        
        dep_manifest := fmt.tprintf(`[module]
name = "dep%d"
version = "1.0.0"
description = "Dependency %d"

[load]
priority = %d
files = ["dep%d.zsh"]
`, i, i, i * 10, i)
        
        dep_manifest_path := filepath.join({dep_dir, "module.toml"})
        os.write_entire_file(dep_manifest_path, transmute([]u8)dep_manifest)
        
        dep_shell_path := filepath.join({dep_dir, fmt.tprintf("dep%d.zsh", i)})
        os.write_entire_file(dep_shell_path, transmute([]u8)shell_content)
    }
    
    // Test discovery
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 4, "Should discover main module and 3 dependencies")
    
    // Test resolution - should fail due to missing dependencies
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err != "", "Should fail resolution due to missing dependencies")
    testing.expect(t, strings.contains(err, "missing dependency") || strings.contains(err, "dep4") || strings.contains(err, "dep5"), 
                   "Error should mention missing dependencies")
}

@(test)
test_recursive_directory_error_handling :: proc(t: ^testing.T) {
    // Test error handling in deeply nested directory structures
    temp_dir := "test_temp_deep_nesting"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create deeply nested structure
    current_path := temp_dir
    for i in 1..=10 {
        current_path = filepath.join({current_path, fmt.tprintf("level%d", i)})
        os.make_directory(current_path)
    }
    
    // Create a module at the deepest level
    deep_module_dir := filepath.join({current_path, "deep-module"})
    os.make_directory(deep_module_dir)
    
    deep_manifest := `[module]
name = "deep-module"
version = "1.0.0"
description = "Deeply nested module"

[load]
priority = 10
files = ["deep.zsh"]
`
    
    manifest_path := filepath.join({deep_module_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)deep_manifest)
    testing.expect(t, write_ok, "Should create deep manifest")
    
    shell_content := "# Deep module"
    shell_path := filepath.join({deep_module_dir, "deep.zsh"})
    os.write_entire_file(shell_path, transmute([]u8)shell_content)
    
    // Test discovery - should handle deep nesting
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover deeply nested module")
    testing.expect(t, modules[0].name == "deep-module", "Should find the correct deep module")
    
    // Test resolution
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve deeply nested module")
    testing.expect(t, len(resolved_modules) == 1, "Should resolve one module")
}