package test

import "core:testing"
import "core:fmt"
import "core:os"
import "core:strings"

import "../src/manifest"

// **Validates: Requirements 3.1.1, 3.1.2**
@(test)
test_basic_manifest_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer manifest.cleanup_module(&module)
    
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
    set_test_timeout(t)
    reset_test_state(t)
    // Property: A minimal manifest with only required fields should parse successfully
    
    toml_content := `[module]
name = "minimal-module"
version = "1.0.0"`
    
    temp_file := "/tmp/test_minimal.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
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
    set_test_timeout(t)
    reset_test_state(t)
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
    defer manifest.cleanup_module(&module)
    
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
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Manifest without required name field should fail to parse
    
    toml_content := `[module]
version = "1.0.0"
description = "Missing name field"`
    
    temp_file := "/tmp/test_missing_name.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should fail
    testing.expect(t, !parse_ok, "Parsing should fail when name field is missing")
}

// **Validates: Requirements 3.1.1**
@(test)
test_empty_name_error :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Manifest with empty name field should fail to parse
    
    toml_content := `[module]
name = ""
version = "1.0.0"`
    
    temp_file := "/tmp/test_empty_name.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should fail
    testing.expect(t, !parse_ok, "Parsing should fail when name field is empty")
}

// **Validates: Requirements 3.1.3**
@(test)
test_dependencies_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Dependencies should be parsed correctly from arrays
    
    toml_content := `[module]
name = "deps-test"
version = "1.0.0"

[dependencies]
required = ["core", "utils", "logging"]
optional = ["fzf", "git-helpers"]`
    
    temp_file := "/tmp/test_dependencies.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for dependencies TOML")
    
    if parse_ok {
        // Property: Required dependencies should be parsed
        testing.expect_value(t, len(module.required), 3)
        testing.expect_value(t, module.required[0], "core")
        testing.expect_value(t, module.required[1], "utils")
        testing.expect_value(t, module.required[2], "logging")
        
        // Property: Optional dependencies should be parsed
        testing.expect_value(t, len(module.optional), 2)
        testing.expect_value(t, module.optional[0], "fzf")
        testing.expect_value(t, module.optional[1], "git-helpers")
    }
}

// **Validates: Requirements 3.1.4**
@(test)
test_platform_filters_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Platform filters should be parsed correctly
    
    toml_content := `[module]
name = "platform-test"
version = "1.0.0"

[platforms]
os = ["linux", "darwin"]
arch = ["x86_64", "arm64"]
shell = "zsh"
min_version = "5.8"`
    
    temp_file := "/tmp/test_platforms.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for platforms TOML")
    
    if parse_ok {
        // Property: Platform OS filters should be parsed
        testing.expect_value(t, len(module.platforms.os), 2)
        testing.expect_value(t, module.platforms.os[0], "linux")
        testing.expect_value(t, module.platforms.os[1], "darwin")
        
        // Property: Platform arch filters should be parsed
        testing.expect_value(t, len(module.platforms.arch), 2)
        testing.expect_value(t, module.platforms.arch[0], "x86_64")
        testing.expect_value(t, module.platforms.arch[1], "arm64")
        
        // Property: Shell and version should be parsed
        testing.expect_value(t, module.platforms.shell, "zsh")
        testing.expect_value(t, module.platforms.min_version, "5.8")
    }
}

// **Validates: Requirements 3.1.5**
@(test)
test_priority_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Priority values should be parsed correctly
    
    toml_content := `[module]
name = "priority-test"
version = "1.0.0"

[load]
priority = 25`
    
    temp_file := "/tmp/test_priority.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for priority TOML")
    
    if parse_ok {
        // Property: Priority should be parsed correctly
        testing.expect_value(t, module.priority, 25)
    }
}

// **Validates: Requirements 3.1.6**
@(test)
test_files_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: File lists should be parsed correctly
    
    toml_content := `[module]
name = "files-test"
version = "1.0.0"

[load]
files = ["init.zsh", "functions.zsh", "aliases.zsh"]`
    
    temp_file := "/tmp/test_files.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for files TOML")
    
    if parse_ok {
        // Property: Files should be parsed correctly
        testing.expect_value(t, len(module.files), 3)
        testing.expect_value(t, module.files[0], "init.zsh")
        testing.expect_value(t, module.files[1], "functions.zsh")
        testing.expect_value(t, module.files[2], "aliases.zsh")
    }
}

// **Validates: Requirements 3.1.7**
@(test)
test_hooks_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Pre-load and post-load hooks should be parsed correctly
    
    toml_content := `[module]
name = "hooks-test"
version = "1.0.0"

[hooks]
pre_load = "setup_environment"
post_load = "finalize_setup"`
    
    temp_file := "/tmp/test_hooks.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for hooks TOML")
    
    if parse_ok {
        // Property: Hooks should be parsed correctly
        testing.expect_value(t, module.hooks.pre_load, "setup_environment")
        testing.expect_value(t, module.hooks.post_load, "finalize_setup")
    }
}

// **Validates: Requirements 4.2.1**
@(test)
test_malformed_toml_error :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Malformed TOML should be handled gracefully
    
    toml_content := `[module
name = "malformed-test"
version = "1.0.0"
# Missing closing bracket for [module] section`
    
    temp_file := "/tmp/test_malformed.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should fail gracefully
    testing.expect(t, !parse_ok, "Parsing should fail for malformed TOML")
}

// **Validates: Requirements 4.2.1**
@(test)
test_nonexistent_file_error :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Non-existent files should be handled gracefully
    
    nonexistent_file := "/tmp/nonexistent_manifest.toml"
    
    module, parse_ok := manifest.parse(nonexistent_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should fail gracefully
    testing.expect(t, !parse_ok, "Parsing should fail for non-existent file")
}

// **Validates: Requirements 3.1.1, 3.1.2**
@(test)
test_complete_manifest_parsing :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: A complete manifest with all fields should parse correctly
    
    toml_content := `[module]
name = "complete-module"
version = "2.1.0"
description = "A complete test module with all fields"
author = "Test Author <test@example.com>"
license = "MIT"

[dependencies]
required = ["core", "utils"]
optional = ["extras"]

[platforms]
os = ["linux", "darwin"]
arch = ["x86_64", "arm64"]
shell = "zsh"
min_version = "5.8"

[load]
priority = 15
files = ["main.zsh", "helpers.zsh"]

[hooks]
pre_load = "pre_setup"
post_load = "post_setup"

[settings]
debug = "false"
log_level = "info"
timeout = "60"`
    
    temp_file := "/tmp/test_complete.toml"
    defer os.remove(temp_file)
    
    write_ok := os.write_entire_file(temp_file, transmute([]u8)toml_content)
    testing.expect(t, write_ok, "Failed to write test file")
    
    module, parse_ok := manifest.parse(temp_file)
    defer manifest.cleanup_module(&module)
    
    // Property: Parsing should succeed
    testing.expect(t, parse_ok, "Parsing should succeed for complete TOML")
    
    if parse_ok {
        // Property: All metadata fields should be parsed
        testing.expect_value(t, module.name, "complete-module")
        testing.expect_value(t, module.version, "2.1.0")
        testing.expect_value(t, module.description, "A complete test module with all fields")
        testing.expect_value(t, module.author, "Test Author <test@example.com>")
        testing.expect_value(t, module.license, "MIT")
        
        // Property: Dependencies should be parsed
        testing.expect_value(t, len(module.required), 2)
        testing.expect_value(t, len(module.optional), 1)
        
        // Property: Platform filters should be parsed
        testing.expect_value(t, len(module.platforms.os), 2)
        testing.expect_value(t, len(module.platforms.arch), 2)
        testing.expect_value(t, module.platforms.shell, "zsh")
        testing.expect_value(t, module.platforms.min_version, "5.8")
        
        // Property: Load configuration should be parsed
        testing.expect_value(t, module.priority, 15)
        testing.expect_value(t, len(module.files), 2)
        
        // Property: Hooks should be parsed
        testing.expect_value(t, module.hooks.pre_load, "pre_setup")
        testing.expect_value(t, module.hooks.post_load, "post_setup")
        
        // Property: Settings should be parsed
        testing.expect_value(t, len(module.settings), 3)
        testing.expect_value(t, module.settings["debug"], "false")
        testing.expect_value(t, module.settings["log_level"], "info")
        testing.expect_value(t, module.settings["timeout"], "60")
    }
}