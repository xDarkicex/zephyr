package test

import "core:testing"
import "core:fmt"
import "core:os"
import "core:strings"
import "../src/manifest"

// **Validates: Requirements 3.1.1, 3.1.2**
@(test)
test_basic_manifest_parsing :: proc(t: ^testing.T) {
    // Property: A valid TOML manifest should parse successfully and contain expected data
    
    toml_content := `[module]
name = "test-module"
version = "1.0.0"
description = "A test module"
author = "Test Author"
license = "MIT"

[load]
priority = 50

[hooks]
pre_load = "setup_function"
post_load = "cleanup_function"

[platforms]
shell = "zsh"
min_version = "5.8"

[settings]
debug = "true"
timeout = "30"`
    
    temp_file := "/tmp/test_basic.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer {
        delete(module.required)
        delete(module.optional)
        delete(module.files)
        delete(module.platforms.os)
        delete(module.platforms.arch)
        delete(module.settings)
    }
    
    testing.expect(t, parse_ok, "Basic manifest should parse successfully")
    
    if parse_ok {
        testing.expect(t, strings.compare(module.name, "test-module") == 0, fmt.tprintf("Expected name 'test-module', got '%s'", module.name))
        testing.expect(t, strings.compare(module.version, "1.0.0") == 0, fmt.tprintf("Expected version '1.0.0', got '%s'", module.version))
        testing.expect(t, strings.compare(module.description, "A test module") == 0, fmt.tprintf("Expected description 'A test module', got '%s'", module.description))
        testing.expect(t, strings.compare(module.author, "Test Author") == 0, fmt.tprintf("Expected author 'Test Author', got '%s'", module.author))
        testing.expect(t, strings.compare(module.license, "MIT") == 0, fmt.tprintf("Expected license 'MIT', got '%s'", module.license))
        testing.expect_value(t, module.priority, 50)
        testing.expect(t, strings.compare(module.hooks.pre_load, "setup_function") == 0, fmt.tprintf("Expected pre_load 'setup_function', got '%s'", module.hooks.pre_load))
        testing.expect(t, strings.compare(module.hooks.post_load, "cleanup_function") == 0, fmt.tprintf("Expected post_load 'cleanup_function', got '%s'", module.hooks.post_load))
        testing.expect(t, strings.compare(module.platforms.shell, "zsh") == 0, fmt.tprintf("Expected shell 'zsh', got '%s'", module.platforms.shell))
        testing.expect(t, strings.compare(module.platforms.min_version, "5.8") == 0, fmt.tprintf("Expected min_version '5.8', got '%s'", module.platforms.min_version))
        testing.expect(t, strings.compare(module.settings["debug"], "true") == 0, fmt.tprintf("Expected debug 'true', got '%s'", module.settings["debug"]))
        testing.expect(t, strings.compare(module.settings["timeout"], "30") == 0, fmt.tprintf("Expected timeout '30', got '%s'", module.settings["timeout"]))
    }
}

// **Validates: Requirements 3.1.1**
@(test)
test_minimal_manifest_parsing :: proc(t: ^testing.T) {
    // Property: A minimal manifest with just name should parse successfully
    
    toml_content := `[module]
name = "minimal-module"`
    
    temp_file := "/tmp/test_minimal.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write minimal test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer {
        delete(module.required)
        delete(module.optional)
        delete(module.files)
        delete(module.platforms.os)
        delete(module.platforms.arch)
        delete(module.settings)
    }
    
    testing.expect(t, parse_ok, "Minimal manifest should parse successfully")
    
    if parse_ok {
        testing.expect(t, strings.compare(module.name, "minimal-module") == 0, fmt.tprintf("Expected name 'minimal-module', got '%s'", module.name))
        testing.expect(t, strings.compare(module.version, "0.0.0") == 0, fmt.tprintf("Expected version '0.0.0', got '%s'", module.version)) // Default version
        testing.expect_value(t, module.priority, 100)    // Default priority
    }
}

// **Validates: Requirements 4.2.1, 4.2.3**
@(test)
test_missing_name_error :: proc(t: ^testing.T) {
    // Property: Parser should fail gracefully when name is missing
    
    toml_content := `[module]
version = "1.0.0"
description = "Missing name"`
    
    temp_file := "/tmp/test_missing_name.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write missing name test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer {
        delete(module.required)
        delete(module.optional)
        delete(module.files)
        delete(module.platforms.os)
        delete(module.platforms.arch)
        delete(module.settings)
    }
    
    testing.expect(t, !parse_ok, "Should fail when name is missing")
}

// **Validates: Requirements 4.2.1, 4.2.3**
@(test)
test_empty_name_error :: proc(t: ^testing.T) {
    // Property: Parser should fail gracefully when name is empty
    
    toml_content := `[module]
name = ""
version = "1.0.0"`
    
    temp_file := "/tmp/test_empty_name.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write empty name test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer {
        delete(module.required)
        delete(module.optional)
        delete(module.files)
        delete(module.platforms.os)
        delete(module.platforms.arch)
        delete(module.settings)
    }
    
    testing.expect(t, !parse_ok, "Should fail when name is empty")
}

// **Validates: Requirements 4.2.2**
@(test)
test_missing_file_error :: proc(t: ^testing.T) {
    // Property: Parser should handle missing files gracefully
    
    non_existent_file := "/tmp/does_not_exist.toml"
    
    module, parse_ok := manifest.parse(non_existent_file)
    defer {
        delete(module.required)
        delete(module.optional)
        delete(module.files)
        delete(module.platforms.os)
        delete(module.platforms.arch)
        delete(module.settings)
    }
    
    testing.expect(t, !parse_ok, "Should fail gracefully when file doesn't exist")
}

// **Validates: Requirements 3.1.8**
@(test)
test_settings_parsing :: proc(t: ^testing.T) {
    // Property: Settings should be parsed as key-value pairs
    
    toml_content := `[module]
name = "settings-test"

[settings]
debug = "true"
timeout = "30"
log_level = "info"`
    
    temp_file := "/tmp/test_settings.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write settings test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer {
        delete(module.required)
        delete(module.optional)
        delete(module.files)
        delete(module.platforms.os)
        delete(module.platforms.arch)
        delete(module.settings)
    }
    
    testing.expect(t, parse_ok, "Settings test should parse successfully")
    
    if parse_ok {
        testing.expect_value(t, len(module.settings), 3)
        testing.expect(t, strings.compare(module.settings["debug"], "true") == 0, fmt.tprintf("Expected debug 'true', got '%s'", module.settings["debug"]))
        testing.expect(t, strings.compare(module.settings["timeout"], "30") == 0, fmt.tprintf("Expected timeout '30', got '%s'", module.settings["timeout"]))
        testing.expect(t, strings.compare(module.settings["log_level"], "info") == 0, fmt.tprintf("Expected log_level 'info', got '%s'", module.settings["log_level"]))
    }
}