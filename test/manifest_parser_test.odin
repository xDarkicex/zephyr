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
    // Note: Module returned by parse() uses its own allocations, so we need to clean it up
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for valid TOML")
    
    if parse_ok {
        // Property: All fields should be parsed correctly
        testing.expect_value(t, module.name, "test-module")
        testing.expect_value(t, module.version, "1.0.0")
        testing.expect_value(t, module.description, "A test module")
        testing.expect_value(t, module.author, "Test Author")
        testing.expect_value(t, module.license, "MIT")
        testing.expect_value(t, module.priority, 50)
        testing.expect_value(t, module.hooks.pre_load, "setup_function")
        testing.expect_value(t, module.hooks.post_load, "cleanup_function")
        testing.expect_value(t, module.platforms.shell, "zsh")
        testing.expect_value(t, module.platforms.min_version, "5.8")
        
        // Property: Settings should be parsed as key-value pairs
        testing.expect_value(t, module.settings["debug"], "true")
        testing.expect_value(t, module.settings["timeout"], "30")
    }
}

// **Validates: Requirements 3.1.1**
@(test)
test_minimal_manifest_parsing :: proc(t: ^testing.T) {
    // Property: A minimal manifest with only required fields should parse successfully
    
    toml_content := `[module]
name = "minimal-module"
version = "1.0.0"`
    
    temp_file := "/tmp/test_minimal.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for minimal valid TOML")
    
    if parse_ok {
        // Property: Required fields should be present
        testing.expect_value(t, module.name, "minimal-module")
        testing.expect_value(t, module.version, "1.0.0")
        
        // Property: Optional fields should have default values
        testing.expect_value(t, module.priority, 100) // Default priority
        testing.expect_value(t, len(module.required), 0)
        testing.expect_value(t, len(module.optional), 0)
        testing.expect_value(t, len(module.files), 0)
    }
}

// **Validates: Requirements 3.1.8**
@(test)
test_settings_parsing :: proc(t: ^testing.T) {
    // Property: Settings section should be parsed as key-value pairs
    
    toml_content := `[module]
name = "settings-test"
version = "1.0.0"

[settings]
debug = "true"
timeout = "30"
max_retries = "5"
log_level = "info"`
    
    temp_file := "/tmp/test_settings.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for settings TOML")
    
    if parse_ok {
        // Property: All settings should be parsed
        testing.expect_value(t, len(module.settings), 4)
        testing.expect_value(t, module.settings["debug"], "true")
        testing.expect_value(t, module.settings["timeout"], "30")
        testing.expect_value(t, module.settings["max_retries"], "5")
        testing.expect_value(t, module.settings["log_level"], "info")
    }
}

// **Validates: Requirements 3.1.1**
@(test)
test_missing_name_error :: proc(t: ^testing.T) {
    // Property: Manifest without required name field should fail to parse
    
    toml_content := `[module]
version = "1.0.0"
description = "Missing name field"`
    
    temp_file := "/tmp/test_missing_name.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    
    // Property: Parsing should fail
    testing.expect(t, !parse_ok, "Parsing should fail when name field is missing")
}

// **Validates: Requirements 3.1.1**
@(test)
test_empty_name_error :: proc(t: ^testing.T) {
    // Property: Manifest with empty name field should fail to parse
    
    toml_content := `[module]
name = ""
version = "1.0.0"`
    
    temp_file := "/tmp/test_empty_name.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    
    // Property: Parsing should fail
    testing.expect(t, !parse_ok, "Parsing should fail when name field is empty")
}