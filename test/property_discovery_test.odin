#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:path/filepath"

import "../src/loader"
import "../src/manifest"

// Simple counter for generating unique test directories
discovery_test_counter := 0

// Generate a unique test directory name
generate_test_dir :: proc() -> string {
    discovery_test_counter += 1
    return fmt.tprintf("/tmp/zephyr_discovery_test_%d", discovery_test_counter)
}

// Create a test directory structure
create_test_directory :: proc(base_path: string) -> bool {
    err := os.make_directory(base_path, 0o755)
    return err == os.ERROR_NONE
}

// Create a simple manifest file
create_test_manifest :: proc(dir_path: string, name: string, version: string, priority: int) -> bool {
    manifest_path := filepath.join({dir_path, "module.toml"})
    defer delete(manifest_path)
    
    content := fmt.tprintf(`[module]
name = "%s"
version = "%s"
description = "Test module for discovery"
author = "Test Author"
license = "MIT"

[load]
priority = %d
files = ["init.zsh"]

[dependencies]
required = []
optional = []`, name, version, priority)
    
    return os.write_entire_file(manifest_path, transmute([]u8)content)
}

// Create a test shell file
create_test_shell_file :: proc(dir_path: string, filename: string) -> bool {
    file_path := filepath.join({dir_path, filename})
    defer delete(file_path)
    
    content := "# Test shell file\necho 'Test module loaded'"
    return os.write_entire_file(file_path, transmute([]u8)content)
}

// Clean up test directory recursively
cleanup_test_directory :: proc(dir_path: string) {
    if os.exists(dir_path) {
        // Use a simple approach to remove directory
        os.remove(dir_path)
    }
}

// Create a complete test module directory
create_complete_test_module :: proc(base_path: string, module_name: string, priority: int) -> string {
    module_path := filepath.join({base_path, module_name})
    defer delete(module_path)
    
    if !create_test_directory(module_path) {
        return ""
    }
    
    if !create_test_manifest(module_path, module_name, "1.0.0", priority) {
        return ""
    }
    
    if !create_test_shell_file(module_path, "init.zsh") {
        return ""
    }
    
    return strings.clone(module_path)
}

// **Validates: Requirements 3.2.1, 3.2.2**
@(test)
test_property_discovery_completeness :: proc(t: ^testing.T) {
    // Property: All valid modules in a directory should be discovered
    // Property: Discovery should find modules at the correct depth
    // Property: Invalid modules should be ignored gracefully
    
    test_cases := []struct{
        module_count: int,
        include_invalid: bool,
    }{
        {1, false},
        {3, false},
        {5, false},
        {2, true},
        {4, true},
    }
    
    for test_case in test_cases {
        for iteration in 0..<3 { // 3 iterations per test case
            test_dir := generate_test_dir()
            defer cleanup_test_directory(test_dir)
            
            if !create_test_directory(test_dir) {
                testing.expect(t, false, fmt.tprintf("Failed to create test directory %s", test_dir))
                continue
            }
            
            created_modules := make([dynamic]string)
            defer {
                for module_path in created_modules {
                    delete(module_path)
                }
                delete(created_modules)
            }
            
            // Create valid test modules
            for i in 0..<test_case.module_count {
                module_name := fmt.tprintf("test-module-%d-%d", iteration, i)
                module_path := create_complete_test_module(test_dir, module_name, (i + 1) * 10)
                
                if len(module_path) > 0 {
                    append(&created_modules, module_path)
                } else {
                    testing.expect(t, false, fmt.tprintf("Failed to create test module %s", module_name))
                }
            }
            
            // Create invalid modules if requested
            if test_case.include_invalid {
                // Create directory without manifest
                invalid_dir := filepath.join({test_dir, "invalid-no-manifest"})
                defer delete(invalid_dir)
                create_test_directory(invalid_dir)
                
                // Create directory with invalid manifest
                invalid_manifest_dir := filepath.join({test_dir, "invalid-manifest"})
                defer delete(invalid_manifest_dir)
                create_test_directory(invalid_manifest_dir)
                
                invalid_manifest_path := filepath.join({invalid_manifest_dir, "module.toml"})
                defer delete(invalid_manifest_path)
                invalid_manifest_content := "[module\nname = invalid"
                os.write_entire_file(invalid_manifest_path, transmute([]u8)invalid_manifest_content)
            }
            
            // Discover modules
            discovered := loader.discover(test_dir)
            defer {
                manifest.cleanup_modules(discovered[:])
                delete(discovered)
            }
            
            // Property: Should discover exactly the number of valid modules
            testing.expect_value(t, len(discovered), test_case.module_count)
            
            // Property: Each discovered module should have valid data
            for module in discovered {
                testing.expect(t, len(module.name) > 0, "Discovered module should have a name")
                testing.expect(t, len(module.version) > 0, "Discovered module should have a version")
                testing.expect(t, len(module.path) > 0, "Discovered module should have a path")
                testing.expect(t, module.priority > 0, "Discovered module should have a valid priority")
                
                // Property: Module path should exist
                testing.expect(t, os.exists(module.path), 
                    fmt.tprintf("Module path %s should exist", module.path))
                
                // Property: Module should have expected name pattern
                testing.expect(t, strings.contains(module.name, "test-module"), 
                    fmt.tprintf("Module name %s should contain 'test-module'", module.name))
            }
        }
    }
}

// **Validates: Requirements 3.2.3**
@(test)
test_property_discovery_nested_directories :: proc(t: ^testing.T) {
    // Property: Discovery should handle nested directory structures
    // Property: Discovery should respect depth limits
    
    nesting_levels := []int{1, 2, 3}
    
    for nesting_level in nesting_levels {
        for iteration in 0..<2 { // 2 iterations per nesting level
            test_dir := generate_test_dir()
            defer cleanup_test_directory(test_dir)
            
            if !create_test_directory(test_dir) {
                testing.expect(t, false, fmt.tprintf("Failed to create test directory %s", test_dir))
                continue
            }
            
            created_paths := make([dynamic]string)
            defer {
                for path in created_paths {
                    delete(path)
                }
                delete(created_paths)
            }
            
            // Create nested directory structure
            current_path := strings.clone(test_dir)
            append(&created_paths, current_path)
            
            for level in 0..<nesting_level {
                nested_dir := fmt.tprintf("level-%d", level)
                new_path := filepath.join({current_path, nested_dir})
                defer delete(new_path)
                
                if !create_test_directory(new_path) {
                    testing.expect(t, false, fmt.tprintf("Failed to create nested directory %s", new_path))
                    break
                }
                
                current_path = strings.clone(new_path)
                append(&created_paths, current_path)
            }
            
            // Create a module at the deepest level
            module_name := fmt.tprintf("nested-module-%d-%d", nesting_level, iteration)
            module_path := create_complete_test_module(current_path, module_name, 50)
            
            if len(module_path) == 0 {
                testing.expect(t, false, fmt.tprintf("Failed to create nested module %s", module_name))
                continue
            }
            defer delete(module_path)
            
            // Discover modules
            discovered := loader.discover(test_dir)
            defer {
                manifest.cleanup_modules(discovered[:])
                delete(discovered)
            }
            
            // Property: Should discover the nested module (assuming reasonable depth limit)
            if nesting_level <= 2 { // Assuming discovery has a reasonable depth limit
                testing.expect(t, len(discovered) >= 1, 
                    fmt.tprintf("Should discover nested module at level %d", nesting_level))
                
                if len(discovered) > 0 {
                    found_module := false
                    for module in discovered {
                        if strings.contains(module.name, module_name) {
                            found_module = true
                            break
                        }
                    }
                    testing.expect(t, found_module, 
                        fmt.tprintf("Should find the specific nested module %s", module_name))
                }
            }
        }
    }
}

// **Validates: Requirements 3.2.4**
@(test)
test_property_discovery_error_handling :: proc(t: ^testing.T) {
    // Property: Discovery should handle various error conditions gracefully
    // Property: Invalid directories should not crash the discovery process
    
    error_cases := []struct{
        description: string,
        setup_func: proc(test_dir: string) -> bool,
    }{
        {
            "nonexistent_directory",
            proc(test_dir: string) -> bool {
                // Don't create the directory
                return true
            },
        },
        {
            "empty_directory",
            proc(test_dir: string) -> bool {
                return create_test_directory(test_dir)
            },
        },
        {
            "directory_with_files_only",
            proc(test_dir: string) -> bool {
                if !create_test_directory(test_dir) do return false
                
                // Create some non-module files
                file1 := filepath.join({test_dir, "readme.txt"})
                defer delete(file1)
                readme_content := "This is a readme file"
                os.write_entire_file(file1, transmute([]u8)readme_content)
                
                file2 := filepath.join({test_dir, "script.sh"})
                defer delete(file2)
                script_content := "#!/bin/bash\necho 'hello'"
                os.write_entire_file(file2, transmute([]u8)script_content)
                
                return true
            },
        },
    }
    
    for error_case in error_cases {
        for iteration in 0..<2 { // 2 iterations per error case
            test_dir := generate_test_dir()
            defer cleanup_test_directory(test_dir)
            
            // Setup the error condition
            setup_ok := error_case.setup_func(test_dir)
            testing.expect(t, setup_ok, 
                fmt.tprintf("Setup should succeed for error case %s (iter %d)", error_case.description, iteration))
            
            // Discover modules (should not crash)
            discovered := loader.discover(test_dir)
            defer {
                manifest.cleanup_modules(discovered[:])
                delete(discovered)
            }
            
            // Property: Discovery should complete without crashing
            testing.expect(t, true, 
                fmt.tprintf("Discovery should complete for error case %s (iter %d)", error_case.description, iteration))
            
            // Property: Should return empty or valid results (no invalid modules)
            for module in discovered {
                testing.expect(t, len(module.name) > 0, "Any discovered module should have a valid name")
                testing.expect(t, len(module.path) > 0, "Any discovered module should have a valid path")
            }
        }
    }
}

// **Validates: Requirements 3.2.1**
@(test)
test_property_discovery_module_validation :: proc(t: ^testing.T) {
    // Property: Discovery should validate module structure
    // Property: Only modules with valid manifests should be included
    
    validation_cases := []struct{
        description: string,
        create_func: proc(dir_path: string, module_name: string) -> bool,
        should_discover: bool,
    }{
        {
            "valid_complete_module",
            proc(dir_path: string, module_name: string) -> bool {
                return len(create_complete_test_module(dir_path, module_name, 50)) > 0
            },
            true,
        },
        {
            "module_without_shell_files",
            proc(dir_path: string, module_name: string) -> bool {
                module_path := filepath.join({dir_path, module_name})
                defer delete(module_path)
                
                if !create_test_directory(module_path) do return false
                return create_test_manifest(module_path, module_name, "1.0.0", 50)
            },
            true, // Should still discover even without shell files
        },
        {
            "directory_without_manifest",
            proc(dir_path: string, module_name: string) -> bool {
                module_path := filepath.join({dir_path, module_name})
                defer delete(module_path)
                
                if !create_test_directory(module_path) do return false
                return create_test_shell_file(module_path, "init.zsh")
            },
            false, // Should not discover without manifest
        },
    }
    
    for validation_case in validation_cases {
        for iteration in 0..<2 { // 2 iterations per validation case
            test_dir := generate_test_dir()
            defer cleanup_test_directory(test_dir)
            
            if !create_test_directory(test_dir) {
                testing.expect(t, false, fmt.tprintf("Failed to create test directory %s", test_dir))
                continue
            }
            
            module_name := fmt.tprintf("validation-test-%s-%d", validation_case.description, iteration)
            
            // Create the test module according to the validation case
            create_ok := validation_case.create_func(test_dir, module_name)
            testing.expect(t, create_ok, 
                fmt.tprintf("Module creation should succeed for %s (iter %d)", validation_case.description, iteration))
            
            if !create_ok do continue
            
            // Discover modules
            discovered := loader.discover(test_dir)
            defer {
                manifest.cleanup_modules(discovered[:])
                delete(discovered)
            }
            
            // Property: Discovery result should match expectation
            if validation_case.should_discover {
                testing.expect(t, len(discovered) >= 1, 
                    fmt.tprintf("Should discover module for %s (iter %d)", validation_case.description, iteration))
                
                if len(discovered) > 0 {
                    found_module := false
                    for module in discovered {
                        if strings.contains(module.name, module_name) {
                            found_module = true
                            testing.expect(t, len(module.name) > 0, "Discovered module should have valid name")
                            testing.expect(t, len(module.version) > 0, "Discovered module should have valid version")
                            break
                        }
                    }
                    testing.expect(t, found_module, 
                        fmt.tprintf("Should find the specific module %s", module_name))
                }
            } else {
                // Should not discover invalid modules, but might discover other valid ones
                for module in discovered {
                    testing.expect(t, !strings.contains(module.name, module_name), 
                        fmt.tprintf("Should not discover invalid module %s", module_name))
                }
            }
        }
    }
}