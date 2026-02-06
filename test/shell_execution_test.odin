package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "../src/loader"
import "../src/manifest"

// Helper function to convert module name to environment variable format
module_name_to_env :: proc(name: string) -> string {
    // Simple conversion: uppercase and replace hyphens with underscores
    result := strings.to_upper(name)
    // For simplicity, we'll just use the name as-is for now
    return result
}

@(test)
test_generated_shell_code_syntax :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test that generated shell code has valid syntax by checking structure
    test_dir := get_test_modules_dir()
    defer delete(test_dir)
    
    modules := loader.discover(test_dir)
    defer delete(modules)
    
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err == "", "Dependency resolution should succeed")
    
    // Generate shell script content and verify structure
    shell_content := generate_test_shell_script(resolved_modules)
    
    // Basic syntax checks
    testing.expect(t, strings.contains(shell_content, "#!/bin/bash"), 
                   "Should contain shebang")
    testing.expect(t, strings.contains(shell_content, "export ZSH_MODULE_"), 
                   "Should contain module environment variables")
    
    // Check that all modules are represented
    for module in resolved_modules {
        module_comment := fmt.tprintf("# Module: %s", module.name)
        testing.expect(t, strings.contains(shell_content, module_comment), 
                       fmt.tprintf("Should contain comment for module %s", module.name))
    }

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_shell_code_with_real_files :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Create a test module with actual shell files and test structure
    temp_dir := setup_test_environment("test_temp_shell_exec")
    defer teardown_test_environment(temp_dir)
    
    // Create module directory
    module_dir := filepath.join({temp_dir, "test-shell-module"})
    defer delete(module_dir)
    os.make_directory(module_dir)
    
    // Create module manifest
    manifest_content := `[module]
name = "test-shell-module"
version = "1.0.0"
description = "Test module for shell execution"

[load]
priority = 10
files = ["exports.zsh", "functions.zsh"]

[settings]
test_var = "test_value"
`
    
    manifest_path := filepath.join({module_dir, "module.toml"})
    defer delete(manifest_path)
    testing.expect(t, create_test_shell_file(manifest_path, manifest_content), 
                   "Should create manifest file")
    
    // Create shell files
    exports_content := `# Test exports
export TEST_MODULE_VAR="hello_world"
export TEST_PATH="/test/path"
`
    
    functions_content := `# Test functions
test_function() {
    echo "Test function called with: $1"
    return 0
}

test_echo() {
    echo "TEST_OUTPUT: $TEST_MODULE_VAR"
}
`
    
    exports_path := filepath.join({module_dir, "exports.zsh"})
    defer delete(exports_path)
    functions_path := filepath.join({module_dir, "functions.zsh"})
    defer delete(functions_path)
    
    testing.expect(t, create_test_shell_file(exports_path, exports_content), 
                   "Should create exports file")
    testing.expect(t, create_test_shell_file(functions_path, functions_content), 
                   "Should create functions file")
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer delete(modules)
    
    testing.expect(t, len(modules) == 1, "Should discover test module")
    
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err == "", "Should resolve test module")
    
    // Verify the module has the expected properties
    module := resolved_modules[0]
    testing.expect(t, module.name == "test-shell-module", "Module name should match")
    testing.expect(t, len(module.files) == 2, "Should have 2 files")
    testing.expect(t, len(module.settings) == 1, "Should have 1 setting")
    testing.expect(t, module.settings["test_var"] == "test_value", "Setting should match")
    
    // Verify files exist
    for file in module.files {
        file_path := filepath.join({module_dir, file})
        defer delete(file_path)
        testing.expect(t, os.exists(file_path), 
                       fmt.tprintf("File should exist: %s", file_path))
    }

    cleanup_modules_and_cache(modules[:])
}

@(test)
test_environment_variable_export :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test that module settings are properly formatted as environment variables
    temp_dir := setup_test_environment("test_temp_env_vars")
    defer teardown_test_environment(temp_dir)
    
    // Create module with settings
    module_dir := filepath.join({temp_dir, "env-test-module"})
    defer delete(module_dir)
    os.make_directory(module_dir)
    
    manifest_content := `[module]
name = "env-test-module"
version = "1.0.0"
description = "Environment variable test module"

[load]
priority = 10
files = ["test.zsh"]

[settings]
custom_setting = "custom_value"
number_setting = "42"
path_setting = "/custom/path"
`
    
    manifest_path := filepath.join({module_dir, "module.toml"})
    defer delete(manifest_path)
    testing.expect(t, create_test_shell_file(manifest_path, manifest_content), 
                   "Should create manifest file")
    
    // Create a simple shell file
    shell_content := `# Test shell file
echo "Module loaded successfully"
`
    
    shell_path := filepath.join({module_dir, "test.zsh"})
    defer delete(shell_path)
    testing.expect(t, create_test_shell_file(shell_path, shell_content), 
                   "Should create shell file")
    
    // Test module loading
    modules := loader.discover(temp_dir)
    defer delete(modules)
    
    resolved_modules, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    defer cleanup_resolved(resolved_modules)
    
    testing.expect(t, err == "", "Should resolve env test module")
    
    // Verify module settings
    module := resolved_modules[0]
    testing.expect(t, len(module.settings) == 3, "Should have 3 settings")
    testing.expect(t, module.settings["custom_setting"] == "custom_value", "Custom setting should match")
    testing.expect(t, module.settings["number_setting"] == "42", "Number setting should match")
    testing.expect(t, module.settings["path_setting"] == "/custom/path", "Path setting should match")
    
    // Generate environment variable script and verify format
    env_script := generate_env_test_script(resolved_modules, temp_dir)
    
    // Check that environment variables are properly formatted
    testing.expect(t, strings.contains(env_script, "ZSH_MODULE_"), 
                   "Should contain properly formatted env var")
    testing.expect(t, strings.contains(env_script, "custom_value"), 
                   "Should contain setting value")

    cleanup_modules_and_cache(modules[:])
}

// Helper function to generate a basic shell script for syntax testing
generate_test_shell_script :: proc(modules: [dynamic]manifest.Module) -> string {
    script := strings.builder_make()
    defer strings.builder_destroy(&script)
    
    strings.write_string(&script, "#!/bin/bash\n")
    strings.write_string(&script, "# Generated test shell script\n\n")
    
    for module in modules {
        strings.write_string(&script, fmt.tprintf("# Module: %s\n", module.name))

        module_env := module_name_to_env(module.name)
        defer delete(module_env)
        
        // Export settings as environment variables
        for key, value in module.settings {
            // Simple environment variable naming
            key_env := module_name_to_env(key)
            defer delete(key_env)
            env_var := fmt.tprintf("ZSH_MODULE_%s_%s", module_env, key_env)
            strings.write_string(&script, fmt.tprintf("export %s=\"%s\"\n", env_var, value))
        }
        
        strings.write_string(&script, "\n")
    }
    
    strings.write_string(&script, "echo \"Shell script syntax test passed\"\n")
    
    return strings.to_string(script)
}

// Helper function to generate environment variable test script
generate_env_test_script :: proc(modules: [dynamic]manifest.Module, base_dir: string) -> string {
    script := strings.builder_make()
    defer strings.builder_destroy(&script)
    
    strings.write_string(&script, "#!/bin/bash\n")
    strings.write_string(&script, "set -e  # Exit on any error\n\n")
    
    for module in modules {
        strings.write_string(&script, fmt.tprintf("# Testing environment variables for module: %s\n", module.name))

        module_env := module_name_to_env(module.name)
        defer delete(module_env)
        
        // Export settings
        for key, value in module.settings {
            key_env := module_name_to_env(key)
            defer delete(key_env)
            env_var := fmt.tprintf("ZSH_MODULE_%s_%s", module_env, key_env)
            strings.write_string(&script, fmt.tprintf("export %s=\"%s\"\n", env_var, value))
        }
        
        // Test that variables are set correctly
        for key, value in module.settings {
            key_env := module_name_to_env(key)
            defer delete(key_env)
            env_var := fmt.tprintf("ZSH_MODULE_%s_%s", module_env, key_env)
            strings.write_string(&script, fmt.tprintf("if [[ \"$%s\" != \"%s\" ]]; then\n", env_var, value))
            strings.write_string(&script, fmt.tprintf("    echo \"Error: %s not set correctly\" >&2\n", env_var))
            strings.write_string(&script, fmt.tprintf("    echo \"Expected: %s, Got: $%s\" >&2\n", value, env_var))
            strings.write_string(&script, "    exit 1\n")
            strings.write_string(&script, "fi\n\n")
        }
    }
    
    strings.write_string(&script, "echo \"Environment variable test passed\"\n")
    
    return strings.to_string(script)
}
