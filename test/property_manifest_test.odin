#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:strings"
import "core:os"

import "../src/manifest"

// Simple counter for generating unique test files
manifest_test_counter := 0

// Generate a unique test file name
generate_test_filename :: proc() -> string {
    manifest_test_counter += 1
    return fmt.tprintf("/tmp/zephyr_manifest_test_%d.toml", manifest_test_counter)
}

// Generate a simple module name
generate_simple_name :: proc(prefix: string, id: int) -> string {
    return fmt.tprintf("%s-%d", prefix, id)
}

// Generate a simple version string
generate_simple_version :: proc(major: int, minor: int = 0, patch: int = 0) -> string {
    return fmt.tprintf("%d.%d.%d", major, minor, patch)
}

// Generate a simple TOML manifest with known values
generate_simple_manifest :: proc(name: string, version: string, priority: int) -> string {
    return fmt.tprintf(`[module]
name = "%s"
version = "%s"
description = "Test module for property testing"
author = "Test Author"
license = "MIT"

[load]
priority = %d
files = ["init.zsh", "functions.zsh"]

[dependencies]
required = ["core", "utils"]
optional = ["extras"]

[hooks]
pre_load = "setup_function"
post_load = "cleanup_function"

[platforms]
os = ["linux", "darwin"]
arch = ["x86_64", "arm64"]
shell = "zsh"
min_version = "5.8"

[settings]
debug = "true"
timeout = "30"`, name, version, priority)
}

// Generate a minimal TOML manifest
generate_minimal_manifest :: proc(name: string, version: string) -> string {
    return fmt.tprintf(`[module]
name = "%s"
version = "%s"`, name, version)
}

// **Validates: Requirements 3.1.1, 3.1.2**
@(test)
test_property_manifest_parsing_roundtrip :: proc(t: ^testing.T) {
    // Property: A valid TOML manifest should parse successfully and contain expected data
    // Property: All parsed fields should match the input values
    
    test_cases := []struct{
        name: string,
        version: string,
        priority: int,
        is_minimal: bool,
    }{
        {"test-module-1", "1.0.0", 10, false},
        {"test-module-2", "2.1.3", 25, false},
        {"minimal-module", "0.1.0", 100, true},
        {"complex-name", "1.2.3", 50, false},
        {"simple", "3.0.0", 75, true},
    }
    
    for test_case in test_cases {
        for iteration in 0..<3 { // 3 iterations per test case
            temp_file := generate_test_filename()
            defer os.remove(temp_file)
            
            // Generate TOML content
            toml_content: string
            if test_case.is_minimal {
                toml_content = generate_minimal_manifest(test_case.name, test_case.version)
            } else {
                toml_content = generate_simple_manifest(test_case.name, test_case.version, test_case.priority)
            }
            
            // Write to temporary file
            write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
            testing.expect(t, write_ok, 
                fmt.tprintf("Failed to write test file for case %s (iter %d)", test_case.name, iteration))
            
            if !write_ok do continue
            
            // Parse the manifest
            module, parse_ok := manifest.parse(temp_file)
            defer manifest.cleanup_module(&module)
            
            // Property: Parsing should succeed for valid TOML
            testing.expect(t, parse_ok, 
                fmt.tprintf("Parsing should succeed for valid TOML (case %s, iter %d)", test_case.name, iteration))
            
            if parse_ok {
                // Property: Required fields should match input
                testing.expect_value(t, module.name, test_case.name)
                testing.expect_value(t, module.version, test_case.version)
                
                if !test_case.is_minimal {
                    // Property: Complex manifest fields should be parsed correctly
                    testing.expect_value(t, module.description, "Test module for property testing")
                    testing.expect_value(t, module.author, "Test Author")
                    testing.expect_value(t, module.license, "MIT")
                    testing.expect_value(t, module.priority, test_case.priority)
                    
                    // Property: Arrays should be parsed correctly
                    testing.expect_value(t, len(module.files), 2)
                    if len(module.files) >= 2 {
                        testing.expect_value(t, module.files[0], "init.zsh")
                        testing.expect_value(t, module.files[1], "functions.zsh")
                    }
                    
                    testing.expect_value(t, len(module.required), 2)
                    if len(module.required) >= 2 {
                        testing.expect_value(t, module.required[0], "core")
                        testing.expect_value(t, module.required[1], "utils")
                    }
                    
                    testing.expect_value(t, len(module.optional), 1)
                    if len(module.optional) >= 1 {
                        testing.expect_value(t, module.optional[0], "extras")
                    }
                    
                    // Property: Hooks should be parsed correctly
                    testing.expect_value(t, module.hooks.pre_load, "setup_function")
                    testing.expect_value(t, module.hooks.post_load, "cleanup_function")
                    
                    // Property: Platform filters should be parsed correctly
                    testing.expect_value(t, len(module.platforms.os), 2)
                    if len(module.platforms.os) >= 2 {
                        testing.expect_value(t, module.platforms.os[0], "linux")
                        testing.expect_value(t, module.platforms.os[1], "darwin")
                    }
                    
                    testing.expect_value(t, len(module.platforms.arch), 2)
                    if len(module.platforms.arch) >= 2 {
                        testing.expect_value(t, module.platforms.arch[0], "x86_64")
                        testing.expect_value(t, module.platforms.arch[1], "arm64")
                    }
                    
                    testing.expect_value(t, module.platforms.shell, "zsh")
                    testing.expect_value(t, module.platforms.min_version, "5.8")
                    
                    // Property: Settings should be parsed correctly
                    testing.expect_value(t, len(module.settings), 2)
                    testing.expect_value(t, module.settings["debug"], "true")
                    testing.expect_value(t, module.settings["timeout"], "30")
                } else {
                    // Property: Minimal manifest should have defaults
                    testing.expect_value(t, module.priority, 100) // Default priority
                    testing.expect_value(t, len(module.required), 0)
                    testing.expect_value(t, len(module.optional), 0)
                    testing.expect_value(t, len(module.files), 0)
                }
            }
        }
    }
}

// Generate invalid TOML content for error testing
generate_invalid_manifest :: proc(error_type: string) -> string {
    switch error_type {
    case "missing_name":
        return `[module]
version = "1.0.0"
description = "Missing name field"`
    case "empty_name":
        return `[module]
name = ""
version = "1.0.0"`
    case "malformed_toml":
        return `[module
name = "malformed"
version = "1.0.0"`
    case:
        return ""
    }
}

// **Validates: Requirements 4.2.1**
@(test)
test_property_manifest_parsing_error_handling :: proc(t: ^testing.T) {
    // Property: Invalid TOML should be handled gracefully
    // Property: Error conditions should be detected and reported
    
    error_cases := []string{"missing_name", "empty_name"}
    
    for error_case in error_cases {
        for iteration in 0..<3 { // 3 iterations per error case
            temp_file := generate_test_filename()
            defer os.remove(temp_file)
            
            // Generate invalid TOML content
            toml_content := generate_invalid_manifest(error_case)
            
            // Write to temporary file
            write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
            testing.expect(t, write_ok, 
                fmt.tprintf("Failed to write test file for error case %s (iter %d)", error_case, iteration))
            
            if !write_ok do continue
            
            // Parse the manifest
            module, parse_ok := manifest.parse(temp_file)
            defer manifest.cleanup_module(&module)
            
            // Property: Parsing should fail for invalid TOML
            testing.expect(t, !parse_ok, 
                fmt.tprintf("Parsing should fail for invalid TOML (case %s, iter %d)", error_case, iteration))
        }
    }
}

// **Validates: Requirements 4.2.2**
@(test)
test_property_manifest_parsing_nonexistent_file :: proc(t: ^testing.T) {
    // Property: Non-existent files should be handled gracefully
    
    nonexistent_files := []string{
        "/tmp/nonexistent_manifest_1.toml",
        "/tmp/nonexistent_manifest_2.toml",
        "/tmp/does_not_exist.toml",
    }
    
    for nonexistent_file in nonexistent_files {
        for iteration in 0..<2 { // 2 iterations per file
            // Ensure file doesn't exist
            if os.exists(nonexistent_file) {
                os.remove(nonexistent_file)
            }
            
            // Parse the non-existent manifest
            module, parse_ok := manifest.parse(nonexistent_file)
            defer manifest.cleanup_module(&module)
            
            // Property: Parsing should fail gracefully for non-existent files
            testing.expect(t, !parse_ok, 
                fmt.tprintf("Parsing should fail for non-existent file %s (iter %d)", nonexistent_file, iteration))
        }
    }
}

// Generate manifests with various field combinations
generate_field_combination_manifest :: proc(include_description: bool, include_author: bool, include_hooks: bool) -> string {
    base := `[module]
name = "field-test"
version = "1.0.0"`
    
    if include_description {
        base = fmt.tprintf("%s\ndescription = \"Test description\"", base)
    }
    
    if include_author {
        base = fmt.tprintf("%s\nauthor = \"Test Author\"", base)
    }
    
    if include_hooks {
        base = fmt.tprintf("%s\n\n[hooks]\npre_load = \"test_hook\"", base)
    }
    
    return base
}

// **Validates: Requirements 3.1.1, 3.1.2**
@(test)
test_property_manifest_parsing_field_combinations :: proc(t: ^testing.T) {
    // Property: Various combinations of optional fields should parse correctly
    
    field_combinations := []struct{
        description: bool,
        author: bool,
        hooks: bool,
    }{
        {true, false, false},
        {false, true, false},
        {false, false, true},
        {true, true, false},
        {true, false, true},
        {false, true, true},
        {true, true, true},
    }
    
    for combo in field_combinations {
        for iteration in 0..<2 { // 2 iterations per combination
            temp_file := generate_test_filename()
            defer os.remove(temp_file)
            
            // Generate TOML content with field combination
            toml_content := generate_field_combination_manifest(combo.description, combo.author, combo.hooks)
            
            // Write to temporary file
            write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
            testing.expect(t, write_ok, 
                fmt.tprintf("Failed to write test file for combination (iter %d)", iteration))
            
            if !write_ok do continue
            
            // Parse the manifest
            module, parse_ok := manifest.parse(temp_file)
            defer manifest.cleanup_module(&module)
            
            // Property: Parsing should succeed for valid field combinations
            testing.expect(t, parse_ok, 
                fmt.tprintf("Parsing should succeed for valid field combination (iter %d)", iteration))
            
            if parse_ok {
                // Property: Required fields should always be present
                testing.expect_value(t, module.name, "field-test")
                testing.expect_value(t, module.version, "1.0.0")
                
                // Property: Optional fields should match inclusion flags
                if combo.description {
                    testing.expect_value(t, module.description, "Test description")
                } else {
                    testing.expect_value(t, len(module.description), 0)
                }
                
                if combo.author {
                    testing.expect_value(t, module.author, "Test Author")
                } else {
                    testing.expect_value(t, len(module.author), 0)
                }
                
                if combo.hooks {
                    testing.expect_value(t, module.hooks.pre_load, "test_hook")
                } else {
                    testing.expect_value(t, len(module.hooks.pre_load), 0)
                }
            }
        }
    }
}