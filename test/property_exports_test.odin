#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:path/filepath"

import "../src/cli"
import "../src/manifest"

// **Property 8: Function Discovery**
// **Validates: Requirements 4.1**
@(test)
test_property_function_discovery :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any shell file containing function definitions in the patterns
    // `function_name()` or `function function_name`, the export discovery SHALL
    // identify the function name and include it in the `exports.functions` array.
    
    // Test case 1: function_name() pattern
    {
        functions := make([dynamic]string)
        defer {
            for func in functions {
                delete(func)
            }
            delete(functions)
        }
        
        cli.discover_functions("my_function() {\n    echo 'hello'\n}", &functions)
        
        testing.expect(t, len(functions) == 1, "function_name() pattern: Expected 1 function")
        if len(functions) > 0 {
            testing.expect(t, functions[0] == "my_function", "function_name() pattern: Expected 'my_function'")
        }
    }
    
    // Test case 2: function function_name pattern
    {
        functions := make([dynamic]string)
        defer {
            for func in functions {
                delete(func)
            }
            delete(functions)
        }
        
        cli.discover_functions("function my_function {\n    echo 'hello'\n}", &functions)
        
        testing.expect(t, len(functions) == 1, "function function_name pattern: Expected 1 function")
        if len(functions) > 0 {
            testing.expect(t, functions[0] == "my_function", "function function_name pattern: Expected 'my_function'")
        }
    }
    
    // Test case 3: function function_name with brace pattern
    {
        functions := make([dynamic]string)
        defer {
            for func in functions {
                delete(func)
            }
            delete(functions)
        }
        
        cli.discover_functions("function my_function() {\n    echo 'hello'\n}", &functions)
        
        testing.expect(t, len(functions) == 1, "function function_name() pattern: Expected 1 function")
        if len(functions) > 0 {
            testing.expect(t, functions[0] == "my_function", "function function_name() pattern: Expected 'my_function'")
        }
    }
    
    // Test case 4: multiple functions
    {
        functions := make([dynamic]string)
        defer {
            for func in functions {
                delete(func)
            }
            delete(functions)
        }
        
        cli.discover_functions("func1() {\n    echo '1'\n}\nfunction func2 {\n    echo '2'\n}", &functions)
        
        testing.expect(t, len(functions) == 2, "Multiple functions: Expected 2 functions")
        
        expected := []string{"func1", "func2"}
        for expected_func in expected {
            found := false
            for actual_func in functions {
                if actual_func == expected_func {
                    found = true
                    break
                }
            }
            testing.expect(t, found, fmt.tprintf("Multiple functions: Expected function '%s' not found", expected_func))
        }
    }
    
    // Test case 5: no functions
    {
        functions := make([dynamic]string)
        defer {
            for func in functions {
                delete(func)
            }
            delete(functions)
        }
        
        cli.discover_functions("echo 'no functions here'\nalias test='echo test'", &functions)
        
        testing.expect(t, len(functions) == 0, "No functions: Expected 0 functions")
    }
    
    // Test case 6: commented out function
    {
        functions := make([dynamic]string)
        defer {
            for func in functions {
                delete(func)
            }
            delete(functions)
        }
        
        cli.discover_functions("# my_func() {\n#     echo 'commented'\n# }", &functions)
        
        testing.expect(t, len(functions) == 0, "Commented function: Expected 0 functions")
    }
}

// **Property 9: Alias Discovery**
// **Validates: Requirements 4.2**
@(test)
test_property_alias_discovery :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any shell file containing alias definitions in the pattern
    // `alias name='...'`, the export discovery SHALL identify the alias name
    // and include it in the `exports.aliases` array.
    
    // Test case 1: simple alias
    {
        aliases := make([dynamic]string)
        defer {
            for alias in aliases {
                delete(alias)
            }
            delete(aliases)
        }
        
        cli.discover_aliases("alias ll='ls -la'", &aliases)
        
        testing.expect(t, len(aliases) == 1, "Simple alias: Expected 1 alias")
        if len(aliases) > 0 {
            testing.expect(t, aliases[0] == "ll", "Simple alias: Expected 'll'")
        }
    }
    
    // Test case 2: alias with double quotes
    {
        aliases := make([dynamic]string)
        defer {
            for alias in aliases {
                delete(alias)
            }
            delete(aliases)
        }
        
        cli.discover_aliases("alias grep=\"grep --color=auto\"", &aliases)
        
        testing.expect(t, len(aliases) == 1, "Double quotes alias: Expected 1 alias")
        if len(aliases) > 0 {
            testing.expect(t, aliases[0] == "grep", "Double quotes alias: Expected 'grep'")
        }
    }
    
    // Test case 3: multiple aliases
    {
        aliases := make([dynamic]string)
        defer {
            for alias in aliases {
                delete(alias)
            }
            delete(aliases)
        }
        
        cli.discover_aliases("alias ll='ls -la'\nalias la='ls -A'\nalias l='ls -CF'", &aliases)
        
        testing.expect(t, len(aliases) == 3, "Multiple aliases: Expected 3 aliases")
        
        expected := []string{"ll", "la", "l"}
        for expected_alias in expected {
            found := false
            for actual_alias in aliases {
                if actual_alias == expected_alias {
                    found = true
                    break
                }
            }
            testing.expect(t, found, fmt.tprintf("Multiple aliases: Expected alias '%s' not found", expected_alias))
        }
    }
    
    // Test case 4: no aliases
    {
        aliases := make([dynamic]string)
        defer {
            for alias in aliases {
                delete(alias)
            }
            delete(aliases)
        }
        
        cli.discover_aliases("echo 'no aliases here'\nmy_func() { echo 'test'; }", &aliases)
        
        testing.expect(t, len(aliases) == 0, "No aliases: Expected 0 aliases")
    }
    
    // Test case 5: commented out alias
    {
        aliases := make([dynamic]string)
        defer {
            for alias in aliases {
                delete(alias)
            }
            delete(aliases)
        }
        
        cli.discover_aliases("# alias test='echo test'", &aliases)
        
        testing.expect(t, len(aliases) == 0, "Commented alias: Expected 0 aliases")
    }
}

// **Property 10: Settings to Environment Variables**
// **Validates: Requirements 4.3**
@(test)
test_property_settings_to_environment_variables :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module with settings, each setting key SHALL be transformed
    // to an environment variable name in the format `ZSH_MODULE_<MODULE_NAME>_<KEY>`
    // (uppercase) and included in the `exports.environment_variables` array.
    
    // Test case 1: single setting
    {
        module := manifest.Module{
            name = strings.clone("test_module"),
            settings = make(map[string]string),
            files = make([dynamic]string),
        }
        defer manifest.cleanup_module(&module)
        
        manifest.AddSetting(&module, "debug", "true")
        
        exports := cli.discover_exports(module)
        defer cli.cleanup_exports_info(&exports)
        
        testing.expect(t, len(exports.environment_variables) == 1, 
            "Single setting: Expected 1 env var")
        
        if len(exports.environment_variables) > 0 {
            testing.expect(t, exports.environment_variables[0] == "ZSH_MODULE_TEST_MODULE_DEBUG", 
                "Single setting: Expected ZSH_MODULE_TEST_MODULE_DEBUG")
        }
    }
    
    // Test case 2: multiple settings
    {
        module := manifest.Module{
            name = strings.clone("my_module"),
            settings = make(map[string]string),
            files = make([dynamic]string),
        }
        defer manifest.cleanup_module(&module)
        
        manifest.AddSetting(&module, "debug", "true")
        manifest.AddSetting(&module, "verbose", "false")
        manifest.AddSetting(&module, "timeout", "30")
        
        exports := cli.discover_exports(module)
        defer cli.cleanup_exports_info(&exports)
        
        testing.expect(t, len(exports.environment_variables) == 3, 
            "Multiple settings: Expected 3 env vars")
        
        expected := []string{
            "ZSH_MODULE_MY_MODULE_DEBUG",
            "ZSH_MODULE_MY_MODULE_VERBOSE", 
            "ZSH_MODULE_MY_MODULE_TIMEOUT",
        }
        
        for expected_env_var in expected {
            found := false
            for actual_env_var in exports.environment_variables {
                if actual_env_var == expected_env_var {
                    found = true
                    break
                }
            }
            testing.expect(t, found, fmt.tprintf("Multiple settings: Expected env var '%s' not found", expected_env_var))
        }
    }
    
    // Test case 3: no settings
    {
        module := manifest.Module{
            name = strings.clone("empty_module"),
            settings = make(map[string]string),
            files = make([dynamic]string),
        }
        defer manifest.cleanup_module(&module)
        
        exports := cli.discover_exports(module)
        defer cli.cleanup_exports_info(&exports)
        
        testing.expect(t, len(exports.environment_variables) == 0, 
            "No settings: Expected 0 env vars")
    }
    
    // Test case 4: mixed case
    {
        module := manifest.Module{
            name = strings.clone("CamelCase"),
            settings = make(map[string]string),
            files = make([dynamic]string),
        }
        defer manifest.cleanup_module(&module)
        
        manifest.AddSetting(&module, "MyKey", "value")
        manifest.AddSetting(&module, "another_key", "value2")
        
        exports := cli.discover_exports(module)
        defer cli.cleanup_exports_info(&exports)
        
        testing.expect(t, len(exports.environment_variables) == 2, 
            "Mixed case: Expected 2 env vars")
        
        expected := []string{
            "ZSH_MODULE_CAMELCASE_MYKEY",
            "ZSH_MODULE_CAMELCASE_ANOTHER_KEY",
        }
        
        for expected_env_var in expected {
            found := false
            for actual_env_var in exports.environment_variables {
                if actual_env_var == expected_env_var {
                    found = true
                    break
                }
            }
            testing.expect(t, found, fmt.tprintf("Mixed case: Expected env var '%s' not found", expected_env_var))
        }
    }
}

// Unit test for export discovery error handling
// **Validates: Requirements 4.7**
@(test)
test_export_discovery_error_handling :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test with unreadable files - verify empty arrays are returned
    
    // Create a test module that references a non-existent file
    module := manifest.Module{
        name = strings.clone("test_module"),
        settings = make(map[string]string),
        files = make([dynamic]string),
    }
    defer manifest.cleanup_module(&module)
    
    // Add a non-existent file to the module's files list
    append(&module.files, strings.clone("non_existent_file.zsh"))
    append(&module.files, strings.clone("/invalid/path/file.zsh"))
    
    // Discover exports - should handle file read errors gracefully
    exports := cli.discover_exports(module)
    defer cli.cleanup_exports_info(&exports)
    
    // Verify that empty arrays are returned when files cannot be read
    testing.expect(t, len(exports.functions) == 0, 
        "Functions array should be empty when files cannot be read")
    testing.expect(t, len(exports.aliases) == 0, 
        "Aliases array should be empty when files cannot be read")
    testing.expect(t, len(exports.environment_variables) == 0, 
        "Environment variables array should be empty when module has no settings")
    
    // Test with a module that has settings but unreadable files
    module2 := manifest.Module{
        name = strings.clone("test_module_with_settings"),
        settings = make(map[string]string),
        files = make([dynamic]string),
    }
    defer manifest.cleanup_module(&module2)
    
    // Add settings
    manifest.AddSetting(&module2, "debug", "true")
    manifest.AddSetting(&module2, "verbose", "false")
    
    // Add non-existent files
    append(&module2.files, strings.clone("missing_file.zsh"))
    
    // Discover exports
    exports2 := cli.discover_exports(module2)
    defer cli.cleanup_exports_info(&exports2)
    
    // Verify that functions and aliases are empty, but environment variables are present
    testing.expect(t, len(exports2.functions) == 0, 
        "Functions array should be empty when files cannot be read")
    testing.expect(t, len(exports2.aliases) == 0, 
        "Aliases array should be empty when files cannot be read")
    testing.expect(t, len(exports2.environment_variables) == 2, 
        "Environment variables should be present even when files cannot be read")
    
    // Verify the environment variables are correct
    expected_env_vars := []string{
        "ZSH_MODULE_TEST_MODULE_WITH_SETTINGS_DEBUG",
        "ZSH_MODULE_TEST_MODULE_WITH_SETTINGS_VERBOSE",
    }
    
    for expected_env_var in expected_env_vars {
        found := false
        for actual_env_var in exports2.environment_variables {
            if actual_env_var == expected_env_var {
                found = true
                break
            }
        }
        testing.expect(t, found, 
            fmt.tprintf("Expected env var '%s' not found", expected_env_var))
    }
}
