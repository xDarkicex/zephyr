package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "../src/loader"
import "../src/manifest"

// Helper function to remove directory recursively
remove_directory_recursive :: proc(path: string) {
    if !os.exists(path) do return
    
    if os.remove(path) == os.ERROR_NONE do return
    
    handle, err := os.open(path)
    if err != os.ERROR_NONE do return
    defer os.close(handle)
    
    file_infos, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE do return
    defer delete(file_infos)
    
    for info in file_infos {
        child_path := filepath.join({path, info.name})
        defer delete(child_path)
        
        if info.is_dir {
            remove_directory_recursive(child_path)
        } else {
            os.remove(child_path)
        }
    }
    
    os.remove(path)
}

@(test)
test_path_handling_cross_platform :: proc(t: ^testing.T) {
    // Test that path handling works correctly across different path styles
    temp_dir := "test_temp_cross_platform"
    defer remove_directory_recursive(temp_dir)
    
    // Create nested directory structure with various path separators
    os.make_directory(temp_dir)
    
    // Test Unix-style paths
    unix_module_dir := filepath.join({temp_dir, "unix-module"})
    os.make_directory(unix_module_dir)
    
    // Create module with Unix-style file paths
    unix_manifest := `[module]
name = "unix-module"
version = "1.0.0"
description = "Module with Unix-style paths"

[load]
priority = 10
files = ["scripts/init.zsh", "config/settings.zsh"]
`
    
    manifest_path := filepath.join({unix_module_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)unix_manifest)
    testing.expect(t, write_ok, "Should create Unix module manifest")
    
    // Create the referenced files
    scripts_dir := filepath.join({unix_module_dir, "scripts"})
    config_dir := filepath.join({unix_module_dir, "config"})
    os.make_directory(scripts_dir)
    os.make_directory(config_dir)
    
    init_content := "# Unix init script\necho 'Unix module loaded'"
    settings_content := "# Unix settings\nexport UNIX_VAR='unix_value'"
    
    init_path := filepath.join({scripts_dir, "init.zsh"})
    settings_path := filepath.join({config_dir, "settings.zsh"})
    
    os.write_entire_file(init_path, transmute([]u8)init_content)
    os.write_entire_file(settings_path, transmute([]u8)settings_content)
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover Unix-style module")
    
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve Unix-style module")
    
    // Verify the module has correct file paths
    module := resolved_modules[0]
    testing.expect(t, len(module.files) == 2, "Should have 2 files")
    testing.expect(t, module.files[0] == "scripts/init.zsh", "First file path should be correct")
    testing.expect(t, module.files[1] == "config/settings.zsh", "Second file path should be correct")
}

@(test)
test_platform_filtering_simulation :: proc(t: ^testing.T) {
    // Test platform filtering by creating modules with platform constraints
    // Note: Since platform filtering isn't fully implemented, we test the manifest parsing
    temp_dir := "test_temp_platform_filter"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create module with platform filters
    platform_module_dir := filepath.join({temp_dir, "platform-module"})
    os.make_directory(platform_module_dir)
    
    platform_manifest := `[module]
name = "platform-module"
version = "1.0.0"
description = "Module with platform constraints"

[load]
priority = 10
files = ["platform.zsh"]

[platforms]
os = ["linux", "darwin"]
arch = ["x86_64", "arm64"]
shell = "zsh"
min_version = "5.0"
`
    
    manifest_path := filepath.join({platform_module_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)platform_manifest)
    testing.expect(t, write_ok, "Should create platform module manifest")
    
    // Create the shell file
    shell_content := "# Platform-specific script\necho 'Platform module loaded'"
    shell_path := filepath.join({platform_module_dir, "platform.zsh"})
    os.write_entire_file(shell_path, transmute([]u8)shell_content)
    
    // Test discovery
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover platform module")
    
    // Verify platform filters are parsed correctly
    module := modules[0]
    testing.expect(t, len(module.platforms.os) == 2, "Should have 2 OS filters")
    testing.expect(t, len(module.platforms.arch) == 2, "Should have 2 arch filters")
    testing.expect(t, module.platforms.shell == "zsh", "Shell filter should be zsh")
    testing.expect(t, module.platforms.min_version == "5.0", "Min version should be 5.0")
    
    // Check OS filters
    found_linux := false
    found_darwin := false
    for os_name in module.platforms.os {
        if os_name == "linux" do found_linux = true
        if os_name == "darwin" do found_darwin = true
    }
    testing.expect(t, found_linux, "Should find linux in OS filters")
    testing.expect(t, found_darwin, "Should find darwin in OS filters")
    
    // Check arch filters
    found_x86_64 := false
    found_arm64 := false
    for arch_name in module.platforms.arch {
        if arch_name == "x86_64" do found_x86_64 = true
        if arch_name == "arm64" do found_arm64 = true
    }
    testing.expect(t, found_x86_64, "Should find x86_64 in arch filters")
    testing.expect(t, found_arm64, "Should find arm64 in arch filters")
}

@(test)
test_file_encoding_handling :: proc(t: ^testing.T) {
    // Test that the system handles different file encodings gracefully
    temp_dir := "test_temp_encoding"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create module with various content types
    encoding_module_dir := filepath.join({temp_dir, "encoding-module"})
    os.make_directory(encoding_module_dir)
    
    encoding_manifest := `[module]
name = "encoding-module"
version = "1.0.0"
description = "Module with various content encodings"

[load]
priority = 10
files = ["ascii.zsh", "utf8.zsh", "special.zsh"]

[settings]
unicode_setting = "café"
special_chars = "!@#$%^&*()"
`
    
    manifest_path := filepath.join({encoding_module_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)encoding_manifest)
    testing.expect(t, write_ok, "Should create encoding module manifest")
    
    // Create files with different content
    ascii_content := "# ASCII content\necho 'Basic ASCII text'"
    utf8_content := "# UTF-8 content\necho 'Unicode: café, naïve, résumé'"
    special_content := "# Special characters\necho 'Special: !@#$%^&*()'"
    
    ascii_path := filepath.join({encoding_module_dir, "ascii.zsh"})
    utf8_path := filepath.join({encoding_module_dir, "utf8.zsh"})
    special_path := filepath.join({encoding_module_dir, "special.zsh"})
    
    os.write_entire_file(ascii_path, transmute([]u8)ascii_content)
    os.write_entire_file(utf8_path, transmute([]u8)utf8_content)
    os.write_entire_file(special_path, transmute([]u8)special_content)
    
    // Test discovery and parsing
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover encoding module")
    
    // Verify settings with special characters are parsed correctly
    module := modules[0]
    testing.expect(t, module.settings["unicode_setting"] == "café", "Unicode setting should be parsed correctly")
    testing.expect(t, module.settings["special_chars"] == "!@#$%^&*()", "Special chars should be parsed correctly")
    
    // Test resolution
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve encoding module")
    testing.expect(t, len(resolved_modules[0].files) == 3, "Should have all 3 files")
}

@(test)
test_directory_structure_variations :: proc(t: ^testing.T) {
    // Test different directory structure patterns that might exist on different platforms
    temp_dir := "test_temp_dir_structure"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Test 1: Flat structure (common on Windows)
    flat_dir := filepath.join({temp_dir, "flat-module"})
    os.make_directory(flat_dir)
    
    flat_manifest := `[module]
name = "flat-module"
version = "1.0.0"
description = "Flat directory structure"

[load]
priority = 10
files = ["init.zsh", "config.zsh", "utils.zsh"]
`
    
    flat_manifest_path := filepath.join({flat_dir, "module.toml"})
    os.write_entire_file(flat_manifest_path, transmute([]u8)flat_manifest)
    
    // Create flat files
    flat_init_content := "# Flat init"
    flat_config_content := "# Flat config"
    flat_utils_content := "# Flat utils"
    
    os.write_entire_file(filepath.join({flat_dir, "init.zsh"}), transmute([]u8)flat_init_content)
    os.write_entire_file(filepath.join({flat_dir, "config.zsh"}), transmute([]u8)flat_config_content)
    os.write_entire_file(filepath.join({flat_dir, "utils.zsh"}), transmute([]u8)flat_utils_content)
    
    // Test 2: Deep nested structure (common on Unix)
    nested_dir := filepath.join({temp_dir, "nested-module"})
    os.make_directory(nested_dir)
    
    nested_manifest := `[module]
name = "nested-module"
version = "1.0.0"
description = "Deep nested structure"

[load]
priority = 20
files = ["src/core/init.zsh", "config/env/settings.zsh", "lib/utils/helpers.zsh"]
`
    
    nested_manifest_path := filepath.join({nested_dir, "module.toml"})
    os.write_entire_file(nested_manifest_path, transmute([]u8)nested_manifest)
    
    // Create nested directories and files
    src_core_dir := filepath.join({nested_dir, "src", "core"})
    config_env_dir := filepath.join({nested_dir, "config", "env"})
    lib_utils_dir := filepath.join({nested_dir, "lib", "utils"})
    
    os.make_directory(filepath.join({nested_dir, "src"}))
    os.make_directory(src_core_dir)
    os.make_directory(filepath.join({nested_dir, "config"}))
    os.make_directory(config_env_dir)
    os.make_directory(filepath.join({nested_dir, "lib"}))
    os.make_directory(lib_utils_dir)
    
    nested_init_content := "# Nested init"
    nested_settings_content := "# Nested settings"
    nested_helpers_content := "# Nested helpers"
    
    os.write_entire_file(filepath.join({src_core_dir, "init.zsh"}), transmute([]u8)nested_init_content)
    os.write_entire_file(filepath.join({config_env_dir, "settings.zsh"}), transmute([]u8)nested_settings_content)
    os.write_entire_file(filepath.join({lib_utils_dir, "helpers.zsh"}), transmute([]u8)nested_helpers_content)
    
    // Test discovery
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 2, "Should discover both flat and nested modules")
    
    // Test resolution
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve both modules")
    testing.expect(t, len(resolved_modules) == 2, "Should resolve both modules")
    
    // Verify both modules have correct file counts
    for module in resolved_modules {
        testing.expect(t, len(module.files) == 3, 
                       fmt.tprintf("Module %s should have 3 files", module.name))
    }
}

@(test)
test_case_sensitivity_handling :: proc(t: ^testing.T) {
    // Test handling of case sensitivity (important for cross-platform compatibility)
    temp_dir := "test_temp_case_sensitivity"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir)
    
    // Create module with mixed case names
    case_module_dir := filepath.join({temp_dir, "Case-Sensitive-Module"})
    os.make_directory(case_module_dir)
    
    case_manifest := `[module]
name = "Case-Sensitive-Module"
version = "1.0.0"
description = "Module with mixed case names"

[load]
priority = 10
files = ["Init.zsh", "CONFIG.zsh", "utilities.ZSH"]

[settings]
CamelCase = "value1"
UPPERCASE = "value2"
lowercase = "value3"
`
    
    manifest_path := filepath.join({case_module_dir, "module.toml"})
    write_ok := os.write_entire_file(manifest_path, transmute([]u8)case_manifest)
    testing.expect(t, write_ok, "Should create case-sensitive module manifest")
    
    // Create files with mixed case names
    init_file_content := "# Init file"
    config_file_content := "# Config file"
    utilities_file_content := "# Utilities file"
    
    os.write_entire_file(filepath.join({case_module_dir, "Init.zsh"}), transmute([]u8)init_file_content)
    os.write_entire_file(filepath.join({case_module_dir, "CONFIG.zsh"}), transmute([]u8)config_file_content)
    os.write_entire_file(filepath.join({case_module_dir, "utilities.ZSH"}), transmute([]u8)utilities_file_content)
    
    // Test discovery
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == 1, "Should discover case-sensitive module")
    
    // Verify case preservation in module name and settings
    module := modules[0]
    testing.expect(t, module.name == "Case-Sensitive-Module", "Module name case should be preserved")
    testing.expect(t, module.settings["CamelCase"] == "value1", "CamelCase setting should be preserved")
    testing.expect(t, module.settings["UPPERCASE"] == "value2", "UPPERCASE setting should be preserved")
    testing.expect(t, module.settings["lowercase"] == "value3", "lowercase setting should be preserved")
    
    // Verify file names are preserved
    testing.expect(t, module.files[0] == "Init.zsh", "Init.zsh case should be preserved")
    testing.expect(t, module.files[1] == "CONFIG.zsh", "CONFIG.zsh case should be preserved")
    testing.expect(t, module.files[2] == "utilities.ZSH", "utilities.ZSH case should be preserved")
}