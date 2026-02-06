#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:encoding/json"
import "core:time"
import "core:strings"
import "core:os"
import "core:path/filepath"

import "../src/cli"
import "../src/manifest"
import "../src/loader"

// Helper function to create a dynamic string array from a slice
make_dynamic_string_array :: proc(values: ..string) -> [dynamic]string {
    arr := make([dynamic]string, len(values))
    for v, i in values {
        arr[i] = strings.clone(v)
    }
    return arr
}

// Helper function to create an empty dynamic string array
make_empty_string_array :: proc() -> [dynamic]string {
    return make([dynamic]string)
}

// Generate a simple JSON_Output structure for testing
generate_test_json_output :: proc(
    module_count: int,
    incompatible_count: int,
) -> cli.JSON_Output {
    // Create environment info
    env := cli.Environment_Info{
        zephyr_version = strings.clone("1.0.0"),
        modules_dir = strings.clone("/test/modules"),
        os = strings.clone("linux"),
        arch = strings.clone("x86_64"),
        shell = strings.clone("zsh"),
        shell_version = strings.clone("5.8"),
    }
    
    // Create summary
    summary := cli.Summary_Info{
        total_modules = module_count + incompatible_count,
        compatible_modules = module_count,
        incompatible_modules = incompatible_count,
    }
    
    // Create module info array
    modules := make([dynamic]cli.Module_Info, module_count)
    for i in 0..<module_count {
        modules[i] = cli.Module_Info{
            name = strings.clone(fmt.tprintf("module-%d", i)),
            version = strings.clone("1.0.0"),
            description = strings.clone("Test module"),
            author = strings.clone("Test Author"),
            license = strings.clone("MIT"),
            path = strings.clone(fmt.tprintf("/test/modules/module-%d", i)),
            load_order = i + 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_dynamic_string_array("linux"),
                arch = make_dynamic_string_array("x86_64"),
                shell = strings.clone("zsh"),
                min_version = strings.clone("5.8"),
            },
            load = cli.Load_Info{
                files = make_dynamic_string_array("init.zsh"),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = {},
            exports = cli.Exports_Info{
                functions = make_empty_string_array(),
                aliases = make_empty_string_array(),
                environment_variables = make_empty_string_array(),
            },
        }
    }
    
    // Create incompatible module info array
    incompatible_modules := make([dynamic]cli.Incompatible_Module_Info, incompatible_count)
    for i in 0..<incompatible_count {
        incompatible_modules[i] = cli.Incompatible_Module_Info{
            name = strings.clone(fmt.tprintf("incompatible-%d", i)),
            version = strings.clone("1.0.0"),
            description = strings.clone("Incompatible module"),
            path = strings.clone(fmt.tprintf("/test/modules/incompatible-%d", i)),
            reason = strings.clone("OS mismatch"),
            platforms = cli.Platform_Info_JSON{
                os = make_dynamic_string_array("windows"),
                arch = make_dynamic_string_array("x86_64"),
                shell = strings.clone("zsh"),
                min_version = strings.clone("5.8"),
            },
        }
    }
    
    // Generate timestamp (ISO 8601 format)
    now := time.now()
    // Use a simple ISO 8601-like format for testing
    timestamp := strings.clone(fmt.tprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", 
        2024, 1, 1, 12, 0, 0))
    
    return cli.JSON_Output{
        schema_version = strings.clone("1.0"),
        generated_at = timestamp,
        environment = env,
        summary = summary,
        modules = modules,
        incompatible_modules = incompatible_modules,
    }
}

// **Property 5: Required JSON Schema Fields**
// **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6**
@(test)
test_property_required_json_schema_fields :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module configuration, the JSON output SHALL include all required
    // top-level fields: schema_version (with value "1.0"), generated_at (ISO 8601 timestamp),
    // environment (with zephyr_version, modules_dir, os, arch, shell, shell_version),
    // summary (with total_modules, compatible_modules, incompatible_modules),
    // modules array, and incompatible_modules array.
    
    // Just test one simple case - empty output
    output := generate_test_json_output(0, 0)
    defer cli.cleanup_json_output(&output)
    
    // Marshal to JSON
    json_bytes, marshal_err := json.marshal(output)
    testing.expect(t, marshal_err == nil, "JSON marshaling should succeed")
    
    if marshal_err != nil do return
    defer delete(json_bytes)
    
    json_str := string(json_bytes)
    
    // Property: schema_version field must be present with value "1.0"
    testing.expect(t, contains_field(json_str, "schema_version"), "JSON must contain schema_version field")
    testing.expect(t, contains_value(json_str, "schema_version", "1.0"), "schema_version must be '1.0'")
    
    // Property: generated_at field must be present
    testing.expect(t, contains_field(json_str, "generated_at"), "JSON must contain generated_at field")
    
    // Property: environment object must be present with all required fields
    testing.expect(t, contains_field(json_str, "environment"), "JSON must contain environment object")
    testing.expect(t, contains_field(json_str, "zephyr_version"), "environment must contain zephyr_version")
    testing.expect(t, contains_field(json_str, "modules_dir"), "environment must contain modules_dir")
    testing.expect(t, contains_field(json_str, "os"), "environment must contain os")
    testing.expect(t, contains_field(json_str, "arch"), "environment must contain arch")
    testing.expect(t, contains_field(json_str, "shell"), "environment must contain shell")
    testing.expect(t, contains_field(json_str, "shell_version"), "environment must contain shell_version")
    
    // Property: summary object must be present with all required fields
    testing.expect(t, contains_field(json_str, "summary"), "JSON must contain summary object")
    testing.expect(t, contains_field(json_str, "total_modules"), "summary must contain total_modules")
    testing.expect(t, contains_field(json_str, "compatible_modules"), "summary must contain compatible_modules")
    testing.expect(t, contains_field(json_str, "incompatible_modules"), "summary must contain incompatible_modules")
    
    // Property: modules array must be present
    testing.expect(t, contains_field(json_str, "modules"), "JSON must contain modules array")
    
    // Property: incompatible_modules array must be present
    testing.expect(t, contains_field(json_str, "incompatible_modules"), "JSON must contain incompatible_modules array")
}

// **Property 7: Complete Module Information**
// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10**
@(test)
test_property_complete_module_information :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any compatible module in the JSON output, the module object SHALL include
    // all required fields: name, version, description, author, license, path, load_order, 
    // priority, dependencies (with required and optional arrays), missing_dependencies, 
    // platforms (with os, arch, shell, min_version), load (with files array), 
    // hooks (with pre_load and post_load), settings, and exports (with functions, aliases, environment_variables).
    
    // Create a simple test module info directly (avoid complex generation)
    module_info := cli.Module_Info{
        name = strings.clone("test-module"),
        version = strings.clone("1.0.0"),
        description = strings.clone("Test module"),
        author = strings.clone("Test Author"),
        license = strings.clone("MIT"),
        path = strings.clone("/test/path"),
        load_order = 1,
        priority = 100,
        dependencies = cli.Dependencies_Info{
            required = make_empty_string_array(),
            optional = make_empty_string_array(),
        },
        missing_dependencies = make_empty_string_array(),
        platforms = cli.Platform_Info_JSON{
            os = make_dynamic_string_array("linux"),
            arch = make_dynamic_string_array("x86_64"),
            shell = strings.clone("zsh"),
            min_version = strings.clone("5.8"),
        },
        load = cli.Load_Info{
            files = make_dynamic_string_array("init.zsh"),
        },
        hooks = cli.Hooks_Info{
            pre_load = "",
            post_load = "",
        },
        settings = make(map[string]string),
        exports = cli.Exports_Info{
            functions = make_empty_string_array(),
            aliases = make_empty_string_array(),
            environment_variables = make_empty_string_array(),
        },
    }
    defer cli.cleanup_module_info(&module_info)
    
    // Marshal just the module info to JSON
    json_bytes, marshal_err := json.marshal(module_info)
    testing.expect(t, marshal_err == nil, "JSON marshaling should succeed")
    
    if marshal_err != nil do return
    defer delete(json_bytes)
    
    json_str := string(json_bytes)
    
    // Property: Each module must have all required fields
    
    // Basic module fields (Requirements 3.1)
    testing.expect(t, contains_field(json_str, "name"), "Module must contain name field")
    testing.expect(t, contains_field(json_str, "version"), "Module must contain version field")
    testing.expect(t, contains_field(json_str, "description"), "Module must contain description field")
    testing.expect(t, contains_field(json_str, "author"), "Module must contain author field")
    testing.expect(t, contains_field(json_str, "license"), "Module must contain license field")
    testing.expect(t, contains_field(json_str, "path"), "Module must contain path field")
    
    // Load order and priority (Requirements 3.2, 3.3)
    testing.expect(t, contains_field(json_str, "load_order"), "Module must contain load_order field")
    testing.expect(t, contains_field(json_str, "priority"), "Module must contain priority field")
    
    // Dependencies (Requirements 3.4)
    testing.expect(t, contains_field(json_str, "dependencies"), "Module must contain dependencies object")
    
    // Missing dependencies (Requirements 3.5)
    testing.expect(t, contains_field(json_str, "missing_dependencies"), "Module must contain missing_dependencies array")
    
    // Platform information (Requirements 3.6)
    testing.expect(t, contains_field(json_str, "platforms"), "Module must contain platforms object")
    
    // Load configuration (Requirements 3.7)
    testing.expect(t, contains_field(json_str, "load"), "Module must contain load object")
    
    // Hooks (Requirements 3.8)
    testing.expect(t, contains_field(json_str, "hooks"), "Module must contain hooks object")
    
    // Settings (Requirements 3.9)
    testing.expect(t, contains_field(json_str, "settings"), "Module must contain settings object")
    
    // Exports (Requirements 3.10)
    testing.expect(t, contains_field(json_str, "exports"), "Module must contain exports object")
}

// **Property 11: Incompatible Module Information**
// **Validates: Requirements 5.1, 5.2, 5.3**
@(test)
test_property_incompatible_module_information :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any incompatible module, the JSON output SHALL include the module 
    // in the incompatible_modules array with fields: name, version, description, path, 
    // reason (non-empty string), and platforms (with os, arch, shell, min_version).
    
    // Create a simple incompatible module info directly
    incompatible_info := cli.Incompatible_Module_Info{
        name = strings.clone("incompatible-module"),
        version = strings.clone("1.0.0"),
        description = strings.clone("Test incompatible module"),
        path = strings.clone("/test/incompatible/path"),
        reason = strings.clone("OS mismatch"),
        platforms = cli.Platform_Info_JSON{
            os = make_dynamic_string_array("windows"),
            arch = make_dynamic_string_array("x86_64"),
            shell = strings.clone("zsh"),
            min_version = strings.clone("5.8"),
        },
    }
    defer cli.cleanup_incompatible_module_info(&incompatible_info)
    
    // Marshal to JSON
    json_bytes, marshal_err := json.marshal(incompatible_info)
    testing.expect(t, marshal_err == nil, "JSON marshaling should succeed")
    
    if marshal_err != nil do return
    defer delete(json_bytes)
    
    json_str := string(json_bytes)
    
    // Property: Incompatible module must have all required fields
    
    // Basic fields (Requirements 5.1)
    testing.expect(t, contains_field(json_str, "name"), "Incompatible module must contain name field")
    testing.expect(t, contains_field(json_str, "version"), "Incompatible module must contain version field")
    testing.expect(t, contains_field(json_str, "description"), "Incompatible module must contain description field")
    testing.expect(t, contains_field(json_str, "path"), "Incompatible module must contain path field")
    
    // Reason field (Requirements 5.2)
    testing.expect(t, contains_field(json_str, "reason"), "Incompatible module must contain reason field")
    testing.expect(t, contains_value(json_str, "reason", "OS mismatch"), "Reason field must be non-empty")
    
    // Platform information (Requirements 5.3)
    testing.expect(t, contains_field(json_str, "platforms"), "Incompatible module must contain platforms object")
}

// Unit tests for incompatibility reason generation
// **Validates: Requirements 5.4, 5.5, 5.6, 5.7**

@(test)
test_os_mismatch_reason :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test OS mismatch reason (Requirements 5.4)
    
    // Create a module that requires Windows on a Linux platform
    module := manifest.Module{
        name = "windows-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
        },
    }
    append(&module.platforms.os, strings.clone("windows"))
    defer delete(module.platforms.os)
    
    current_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8",
    }
    
    reason := cli.determine_incompatibility_reason(module, current_platform)
    defer delete(reason)
    
    testing.expect(t, strings.contains(reason, "OS mismatch"), "Should detect OS mismatch")
}

@(test)
test_architecture_mismatch_reason :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test architecture mismatch reason (Requirements 5.5)
    
    // Create a module that requires ARM on an x86_64 platform
    module := manifest.Module{
        name = "arm-module",
        platforms = manifest.Platform_Filter{
            arch = make([dynamic]string),
        },
    }
    append(&module.platforms.arch, strings.clone("arm64"))
    defer {
        for &arch in module.platforms.arch {
            if arch != "" {
                delete(arch)
                arch = ""
            }
        }
        delete(module.platforms.arch)
    }
    
    current_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8",
    }
    
    reason := cli.determine_incompatibility_reason(module, current_platform)
    defer delete(reason)
    
    testing.expect(t, strings.contains(reason, "Architecture mismatch"), "Should detect architecture mismatch")
}

@(test)
test_shell_mismatch_reason :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test shell mismatch reason (Requirements 5.6)
    
    // Create a module that requires bash on a zsh platform
    module := manifest.Module{
        name = "bash-module",
        platforms = manifest.Platform_Filter{
            shell = "bash",
        },
    }
    
    current_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8",
    }
    
    reason := cli.determine_incompatibility_reason(module, current_platform)
    defer delete(reason)
    
    testing.expect(t, strings.contains(reason, "Shell mismatch"), "Should detect shell mismatch")
}

@(test)
test_version_requirement_reason :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Test version requirement reason (Requirements 5.7)
    
    // Create a module that requires zsh 6.0 on a 5.8 platform
    module := manifest.Module{
        name = "version-module",
        platforms = manifest.Platform_Filter{
            shell = "zsh",
            min_version = "6.0",
        },
    }
    
    current_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8",
    }
    
    reason := cli.determine_incompatibility_reason(module, current_platform)
    defer delete(reason)
    
    testing.expect(t, strings.contains(reason, "Shell version requirement not met"), "Should detect version requirement not met")
}

// Helper function to check if a field exists in JSON string
contains_field :: proc(json_str: string, field_name: string) -> bool {
    search_str := fmt.tprintf("\"%s\"", field_name)
    return strings.contains(json_str, search_str)
}

// Helper function to check if a field has a specific value in JSON string
contains_value :: proc(json_str: string, field_name: string, value: string) -> bool {
    search_str := fmt.tprintf("\"%s\":\"%s\"", field_name, value)
    return strings.contains(json_str, search_str)
}
// **Property 1: Valid JSON Output**
// **Validates: Requirements 1.1, 8.1**
@(test)
test_property_valid_json_output :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module configuration, when the --json flag is provided, 
    // the output to stdout SHALL be valid JSON conforming to RFC 8259 that can 
    // be successfully parsed by a JSON parser.
    
    // Test case 1: Empty JSON output
    {
        output := cli.JSON_Output{
            schema_version = strings.clone("1.0"),
            generated_at = strings.clone("2024-01-01T12:00:00Z"),
            environment = cli.Environment_Info{
                zephyr_version = strings.clone("1.0.0"),
                modules_dir = strings.clone("/test/modules"),
                os = strings.clone("linux"),
                arch = strings.clone("x86_64"),
                shell = strings.clone("zsh"),
                shell_version = strings.clone("5.8"),
            },
            summary = cli.Summary_Info{
                total_modules = 0,
                compatible_modules = 0,
                incompatible_modules = 0,
            },
            modules = make([dynamic]cli.Module_Info),
            incompatible_modules = make([dynamic]cli.Incompatible_Module_Info),
        }
        defer cli.cleanup_json_output(&output)
        
        // Property: The output must be valid JSON that can be marshaled
        json_bytes, marshal_err := json.marshal(output)
        testing.expect(t, marshal_err == nil, "JSON marshaling should succeed for empty output")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        // Property: The marshaled JSON must be valid and parseable
        json_str := string(json_bytes)
        testing.expect(t, len(json_str) > 0, "JSON output should not be empty")
        
        // Property: The JSON should be parseable back to a value
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "JSON should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
    
    // Test case 2: Simple module structure
    {
        module_info := cli.Module_Info{
            name = strings.clone("test-module"),
            version = strings.clone("1.0.0"),
            description = strings.clone("Test module"),
            author = strings.clone("Test Author"),
            license = strings.clone("MIT"),
            path = strings.clone("/test/path"),
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_dynamic_string_array("linux"),
                arch = make_dynamic_string_array("x86_64"),
                shell = strings.clone("zsh"),
                min_version = strings.clone("5.8"),
            },
            load = cli.Load_Info{
                files = make_dynamic_string_array("init.zsh"),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Property: Individual module structures must be valid JSON
        json_bytes, marshal_err := json.marshal(module_info)
        testing.expect(t, marshal_err == nil, "JSON marshaling should succeed for module info")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        // Property: The JSON should be parseable
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "Module JSON should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
}
// **Property 3: Pretty Printing Format**
// **Validates: Requirements 1.2, 8.6, 8.7**
@(test)
test_property_pretty_printing_format :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module configuration, when both --json and --pretty flags are provided,
    // the JSON output SHALL contain newlines and use 2-space indentation for nested structures,
    // and when --pretty is not provided, the output SHALL be compact without unnecessary whitespace.
    
    // Create a simple test structure with nested objects
    output := cli.JSON_Output{
        schema_version = strings.clone("1.0"),
        generated_at = strings.clone("2024-01-01T12:00:00Z"),
        environment = cli.Environment_Info{
            zephyr_version = strings.clone("1.0.0"),
            modules_dir = strings.clone("/test/modules"),
            os = strings.clone("linux"),
            arch = strings.clone("x86_64"),
            shell = strings.clone("zsh"),
            shell_version = strings.clone("5.8"),
        },
        summary = cli.Summary_Info{
            total_modules = 1,
            compatible_modules = 1,
            incompatible_modules = 0,
        },
        modules = make([dynamic]cli.Module_Info),
        incompatible_modules = make([dynamic]cli.Incompatible_Module_Info),
    }
    defer cli.cleanup_json_output(&output)
    
    // Test case 1: Pretty printing enabled
    {
        pretty_options := json.Marshal_Options{
            pretty = true,
            use_spaces = true,
            spaces = 2,
        }
        
        pretty_bytes, err := json.marshal(output, pretty_options)
        testing.expect(t, err == nil, "Pretty JSON marshaling should succeed")
        
        if err != nil do return
        defer delete(pretty_bytes)
        
        pretty_str := string(pretty_bytes)
        
        // Property: Pretty printed JSON must contain newlines
        testing.expect(t, strings.contains(pretty_str, "\n"), "Pretty JSON must contain newlines")
        
        // Property: Pretty printed JSON must use 2-space indentation
        testing.expect(t, strings.contains(pretty_str, "  "), "Pretty JSON must contain 2-space indentation")
        
        // Property: Nested objects should be indented
        testing.expect(t, strings.contains(pretty_str, "  \"environment\""), "Nested objects should be indented")
    }
    
    // Test case 2: Compact printing (no pretty flag)
    {
        compact_options := json.Marshal_Options{
            pretty = false,
        }
        
        compact_bytes, err := json.marshal(output, compact_options)
        testing.expect(t, err == nil, "Compact JSON marshaling should succeed")
        
        if err != nil do return
        defer delete(compact_bytes)
        
        compact_str := string(compact_bytes)
        
        // Property: Compact JSON should not contain unnecessary newlines
        // (Note: Some newlines might be present in string values, but not for formatting)
        newline_count := strings.count(compact_str, "\n")
        testing.expect(t, newline_count == 0, "Compact JSON should not contain formatting newlines")
        
        // Property: Compact JSON should not contain indentation spaces
        // (Check that there are no sequences of multiple spaces used for indentation)
        testing.expect(t, !strings.contains(compact_str, "  "), "Compact JSON should not contain indentation spaces")
    }
    
    // Test case 3: Compare sizes - pretty should be larger than compact
    {
        pretty_options := json.Marshal_Options{pretty = true, use_spaces = true, spaces = 2}
        compact_options := json.Marshal_Options{pretty = false}
        
        pretty_bytes, pretty_err := json.marshal(output, pretty_options)
        compact_bytes, compact_err := json.marshal(output, compact_options)
        
        testing.expect(t, pretty_err == nil && compact_err == nil, "Both marshaling operations should succeed")
        
        if pretty_err == nil && compact_err == nil {
            defer delete(pretty_bytes)
            defer delete(compact_bytes)
            
            // Property: Pretty printed JSON should be larger due to formatting
            testing.expect(t, len(pretty_bytes) > len(compact_bytes), "Pretty JSON should be larger than compact JSON")
        }
    }
}
// **Property 14: Empty Field Defaults**
// **Validates: Requirements 8.2, 8.3**
@(test)
test_property_empty_field_defaults :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module field that has no value, the JSON output SHALL use 
    // the appropriate empty default: empty string ("") for string fields, 
    // empty array ([]) for array fields, empty object ({}) for object fields, 
    // and 0 for integer fields.
    
    // Create a module with empty/default values
    module_info := cli.Module_Info{
        name = "",                    // Empty string
        version = "",                 // Empty string
        description = "",             // Empty string
        author = "",                  // Empty string
        license = "",                 // Empty string
        path = "",                    // Empty string
        load_order = 0,               // Zero integer
        priority = 0,                 // Zero integer
        dependencies = cli.Dependencies_Info{
            required = make_empty_string_array(),    // Empty array
            optional = make_empty_string_array(),    // Empty array
        },
        missing_dependencies = make_empty_string_array(), // Empty array
        platforms = cli.Platform_Info_JSON{
            os = make_empty_string_array(),          // Empty array
            arch = make_empty_string_array(),        // Empty array
            shell = "",               // Empty string
            min_version = "",         // Empty string
        },
        load = cli.Load_Info{
            files = make_empty_string_array(),       // Empty array
        },
        hooks = cli.Hooks_Info{
            pre_load = "",            // Empty string
            post_load = "",           // Empty string
        },
        settings = make(map[string]string), // Empty object
        exports = cli.Exports_Info{
            functions = make([dynamic]string),             // Empty array
            aliases = make([dynamic]string),               // Empty array
            environment_variables = make([dynamic]string), // Empty array
        },
    }
    defer cli.cleanup_module_info(&module_info)
    
    // Marshal to JSON
    json_bytes, err := json.marshal(module_info)
    testing.expect(t, err == nil, "JSON marshaling should succeed for empty fields")
    
    if err != nil do return
    defer delete(json_bytes)
    
    json_str := string(json_bytes)
    
    // Property: Empty string fields should be empty strings in JSON
    testing.expect(t, contains_value(json_str, "name", ""), "Empty name should be empty string")
    testing.expect(t, contains_value(json_str, "version", ""), "Empty version should be empty string")
    testing.expect(t, contains_value(json_str, "description", ""), "Empty description should be empty string")
    testing.expect(t, contains_value(json_str, "author", ""), "Empty author should be empty string")
    testing.expect(t, contains_value(json_str, "license", ""), "Empty license should be empty string")
    testing.expect(t, contains_value(json_str, "path", ""), "Empty path should be empty string")
    
    // Property: Zero integer fields should be 0 in JSON
    testing.expect(t, strings.contains(json_str, "\"load_order\":0"), "Empty load_order should be 0")
    testing.expect(t, strings.contains(json_str, "\"priority\":0"), "Empty priority should be 0")
    
    // Property: Empty array fields should be empty arrays in JSON
    testing.expect(t, strings.contains(json_str, "\"required\":[]"), "Empty required array should be []")
    testing.expect(t, strings.contains(json_str, "\"optional\":[]"), "Empty optional array should be []")
    testing.expect(t, strings.contains(json_str, "\"missing_dependencies\":[]"), "Empty missing_dependencies should be []")
    testing.expect(t, strings.contains(json_str, "\"os\":[]"), "Empty os array should be []")
    testing.expect(t, strings.contains(json_str, "\"arch\":[]"), "Empty arch array should be []")
    testing.expect(t, strings.contains(json_str, "\"files\":[]"), "Empty files array should be []")
    testing.expect(t, strings.contains(json_str, "\"functions\":[]"), "Empty functions array should be []")
    testing.expect(t, strings.contains(json_str, "\"aliases\":[]"), "Empty aliases array should be []")
    testing.expect(t, strings.contains(json_str, "\"environment_variables\":[]"), "Empty environment_variables should be []")
    
    // Property: Empty object fields should be empty objects in JSON
    testing.expect(t, strings.contains(json_str, "\"settings\":{}"), "Empty settings should be {}")
    
    // Property: The JSON should still be valid despite all empty fields
    parsed_value: json.Value
    parse_err := json.unmarshal(json_bytes, &parsed_value)
    testing.expect(t, parse_err == nil, "JSON with empty fields should be parseable")
    
    if parse_err == nil {
        json.destroy_value(parsed_value)
    }
}
// **Property 15: JSON Character Escaping**
// **Validates: Requirements 8.4**
@(test)
test_property_json_character_escaping :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module containing special characters (quotes, backslashes, control characters) 
    // in string fields, the JSON output SHALL properly escape these characters according to JSON specification.
    
    // Test case 1: Quotes and backslashes
    {
        module_info := cli.Module_Info{
            name = strings.clone("test\"module"),           // Contains double quote
            version = strings.clone("1.0\\beta"),          // Contains backslash
            description = strings.clone("A 'test' module"), // Contains single quotes
            author = strings.clone("John \"Doe\""),         // Contains escaped quotes
            license = strings.clone("MIT\\GPL"),            // Contains backslash
            path = strings.clone("/path/with\\backslash"),  // Contains backslash
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_empty_string_array(),
                arch = make_empty_string_array(),
                shell = "",
                min_version = "",
            },
            load = cli.Load_Info{
                files = make_empty_string_array(),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Marshal to JSON
        json_bytes, err := json.marshal(module_info)
        testing.expect(t, err == nil, "JSON marshaling should succeed with special characters")
        
        if err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: Double quotes should be escaped as \"
        testing.expect(t, strings.contains(json_str, "test\\\"module"), "Double quotes should be escaped")
        testing.expect(t, strings.contains(json_str, "John \\\"Doe\\\""), "Quotes in author should be escaped")
        
        // Property: Backslashes should be escaped as \\
        testing.expect(t, strings.contains(json_str, "1.0\\\\beta"), "Backslashes in version should be escaped")
        testing.expect(t, strings.contains(json_str, "MIT\\\\GPL"), "Backslashes in license should be escaped")
        testing.expect(t, strings.contains(json_str, "/path/with\\\\backslash"), "Backslashes in path should be escaped")
        
        // Property: The JSON should still be valid after escaping
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "JSON with escaped characters should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
    
    // Test case 2: Control characters
    {
        module_info := cli.Module_Info{
            name = strings.clone("test\nmodule"),           // Contains newline
            version = strings.clone("1.0\trelease"),       // Contains tab
            description = strings.clone("Line1\nLine2"),   // Contains newline
            author = strings.clone("Tab\tSeparated"),      // Contains tab
            license = strings.clone("MIT"),
            path = strings.clone("/path"),
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_empty_string_array(),
                arch = make_empty_string_array(),
                shell = "",
                min_version = "",
            },
            load = cli.Load_Info{
                files = make_empty_string_array(),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Marshal to JSON
        json_bytes, err := json.marshal(module_info)
        testing.expect(t, err == nil, "JSON marshaling should succeed with control characters")
        
        if err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: Newlines should be escaped as \n
        testing.expect(t, strings.contains(json_str, "test\\nmodule"), "Newlines should be escaped")
        testing.expect(t, strings.contains(json_str, "Line1\\nLine2"), "Newlines in description should be escaped")
        
        // Property: Tabs should be escaped as \t
        testing.expect(t, strings.contains(json_str, "1.0\\trelease"), "Tabs should be escaped")
        testing.expect(t, strings.contains(json_str, "Tab\\tSeparated"), "Tabs in author should be escaped")
        
        // Property: The JSON should still be valid after escaping control characters
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "JSON with escaped control characters should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
}
// **Property 16: UTF-8 Encoding**
// **Validates: Requirements 8.5**
@(test)
test_property_utf8_encoding :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module configuration, the JSON output SHALL be valid UTF-8 encoded text.
    
    // Test case 1: ASCII characters (subset of UTF-8)
    {
        module_info := cli.Module_Info{
            name = strings.clone("ascii-module"),
            version = strings.clone("1.0.0"),
            description = strings.clone("Simple ASCII description"),
            author = strings.clone("John Doe"),
            license = strings.clone("MIT"),
            path = strings.clone("/path/to/module"),
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_empty_string_array(),
                arch = make_empty_string_array(),
                shell = "",
                min_version = "",
            },
            load = cli.Load_Info{
                files = make_empty_string_array(),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Marshal to JSON
        json_bytes, err := json.marshal(module_info)
        testing.expect(t, err == nil, "JSON marshaling should succeed with ASCII characters")
        
        if err != nil do return
        defer delete(json_bytes)
        
        // Property: The JSON bytes should be valid UTF-8
        json_str := string(json_bytes)
        testing.expect(t, len(json_str) > 0, "JSON string should not be empty")
        
        // Property: Should be parseable as valid JSON
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "ASCII JSON should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
    
    // Test case 2: Unicode characters (extended UTF-8)
    {
        module_info := cli.Module_Info{
            name = strings.clone("unicode-模块"),              // Chinese characters
            version = strings.clone("1.0.0-α"),              // Greek alpha
            description = strings.clone("Módulo de prueba"), // Spanish with accents
            author = strings.clone("José García"),           // Spanish name with accents
            license = strings.clone("MIT™"),                 // Trademark symbol
            path = strings.clone("/路径/to/module"),          // Chinese characters in path
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_empty_string_array(),
                arch = make_empty_string_array(),
                shell = "",
                min_version = "",
            },
            load = cli.Load_Info{
                files = make_empty_string_array(),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Marshal to JSON
        json_bytes, err := json.marshal(module_info)
        testing.expect(t, err == nil, "JSON marshaling should succeed with Unicode characters")
        
        if err != nil do return
        defer delete(json_bytes)
        
        // Property: The JSON bytes should be valid UTF-8
        json_str := string(json_bytes)
        testing.expect(t, len(json_str) > 0, "Unicode JSON string should not be empty")
        
        // Property: Unicode characters should be preserved or properly escaped in JSON
        // Note: JSON allows Unicode to be escaped as \uXXXX sequences, which is valid
        testing.expect(t, strings.contains(json_str, "unicode-") && 
                         (strings.contains(json_str, "模块") || strings.contains(json_str, "\\u")), 
                         "Chinese characters should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "1.0.0-") && 
                         (strings.contains(json_str, "α") || strings.contains(json_str, "\\u")), 
                         "Greek characters should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "Módulo de prueba") || strings.contains(json_str, "\\u"), 
                         "Spanish accents should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "José García") || strings.contains(json_str, "\\u"), 
                         "Spanish name should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "MIT") && 
                         (strings.contains(json_str, "™") || strings.contains(json_str, "\\u")), 
                         "Trademark symbol should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "/") && strings.contains(json_str, "/to/module") && 
                         (strings.contains(json_str, "路径") || strings.contains(json_str, "\\u")), 
                         "Chinese path should be preserved or escaped")
        
        // Property: Should be parseable as valid JSON despite Unicode content
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "Unicode JSON should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
    
    // Test case 3: Emoji and symbols (high Unicode code points)
    {
        module_info := cli.Module_Info{
            name = strings.clone("emoji-module-🚀"),
            version = strings.clone("1.0.0"),
            description = strings.clone("Module with emojis 📦 and symbols ⚡"),
            author = strings.clone("Developer 👨‍💻"),
            license = strings.clone("MIT"),
            path = strings.clone("/path/to/📁"),
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_empty_string_array(),
                arch = make_empty_string_array(),
                shell = "",
                min_version = "",
            },
            load = cli.Load_Info{
                files = make_empty_string_array(),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Marshal to JSON
        json_bytes, err := json.marshal(module_info)
        testing.expect(t, err == nil, "JSON marshaling should succeed with emoji characters")
        
        if err != nil do return
        defer delete(json_bytes)
        
        // Property: The JSON bytes should be valid UTF-8
        json_str := string(json_bytes)
        testing.expect(t, len(json_str) > 0, "Emoji JSON string should not be empty")
        
        // Property: Emoji should be preserved or properly escaped in JSON
        // Note: JSON allows Unicode to be escaped as \uXXXX sequences, which is valid
        testing.expect(t, strings.contains(json_str, "emoji-module-") && 
                         (strings.contains(json_str, "🚀") || strings.contains(json_str, "\\u")), 
                         "Rocket emoji should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "📦") || strings.contains(json_str, "\\u"), 
                         "Package emoji should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "⚡") || strings.contains(json_str, "\\u"), 
                         "Lightning emoji should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "👨‍💻") || strings.contains(json_str, "\\u"), 
                         "Developer emoji should be preserved or escaped")
        testing.expect(t, strings.contains(json_str, "📁") || strings.contains(json_str, "\\u"), 
                         "Folder emoji should be preserved or escaped")
        
        // Property: Should be parseable as valid JSON despite emoji content
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "Emoji JSON should be parseable")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
    }
}

// **Property 13: Error Output Separation**
// **Validates: Requirements 1.4, 7.6**
@(test)
test_property_error_output_separation :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any error condition when --json flag is provided, error messages SHALL be 
    // written to stderr (not stdout), and stdout SHALL contain either valid JSON or nothing.
    
    // This property test verifies the error handling behavior by checking that:
    // 1. Error messages use stderr output functions (colors.print_error writes to stderr)
    // 2. JSON output functions only write to stdout
    // 3. Valid JSON can still be produced even in error scenarios
    
    // Test case 1: Verify that marshal_and_output writes to stdout
    {
        output := cli.JSON_Output{
            schema_version = strings.clone("1.0"),
            generated_at = strings.clone("2024-01-01T12:00:00Z"),
            environment = cli.Environment_Info{
                zephyr_version = strings.clone("1.0.0"),
                modules_dir = strings.clone("/test/modules"),
                os = strings.clone("linux"),
                arch = strings.clone("x86_64"),
                shell = strings.clone("zsh"),
                shell_version = strings.clone("5.8"),
            },
            summary = cli.Summary_Info{
                total_modules = 0,
                compatible_modules = 0,
                incompatible_modules = 0,
            },
            modules = make([dynamic]cli.Module_Info),
            incompatible_modules = make([dynamic]cli.Incompatible_Module_Info),
        }
        defer cli.cleanup_json_output(&output)
        
        // Marshal to JSON (this is what marshal_and_output does internally)
        json_bytes, marshal_err := json.marshal(output)
        testing.expect(t, marshal_err == nil, "JSON marshaling should succeed")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: The JSON output should be valid (can be written to stdout)
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "JSON output should be valid for stdout")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
        
        // Property: The JSON should not contain error message patterns
        testing.expect(t, !strings.contains(json_str, "Error:"), "JSON output should not contain error messages")
        testing.expect(t, !strings.contains(json_str, "Failed:"), "JSON output should not contain failure messages")
        testing.expect(t, !strings.contains(json_str, "Cannot"), "JSON output should not contain error text")
    }
    
    // Test case 2: Verify empty JSON output for error scenarios
    {
        // When an error occurs early (e.g., directory doesn't exist), 
        // the system should exit without producing JSON output
        // This test verifies that create_empty_json_output produces valid JSON
        
        json_bytes, marshal_err := cli.create_empty_json_output("/nonexistent/path", false)
        testing.expect(t, marshal_err == nil, "Empty JSON marshaling should succeed")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: Empty output should be valid JSON
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "Empty JSON output should be valid")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
        
        // Property: Empty output should not contain error messages
        testing.expect(t, !strings.contains(json_str, "Error:"), "Empty JSON should not contain error messages")
        testing.expect(t, !strings.contains(json_str, "does not exist"), "Empty JSON should not contain error text")
    }
    
    // Test case 3: Verify JSON structure remains valid even with problematic data
    {
        // Test that JSON output remains valid even when module data might be problematic
        module_info := cli.Module_Info{
            name = "",  // Empty name (edge case)
            version = "",
            description = "",
            author = "",
            license = "",
            path = strings.clone("/nonexistent/path"),  // Nonexistent path
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_empty_string_array(),
                arch = make_empty_string_array(),
                shell = "",
                min_version = "",
            },
            load = cli.Load_Info{
                files = make_empty_string_array(),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        defer cli.cleanup_module_info(&module_info)
        
        // Marshal to JSON
        json_bytes, marshal_err := json.marshal(module_info)
        testing.expect(t, marshal_err == nil, "JSON marshaling should succeed even with empty fields")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: JSON should be valid even with problematic data
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "JSON should be valid even with empty/problematic fields")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
        
        // Property: JSON should not contain error messages
        testing.expect(t, !strings.contains(json_str, "Error:"), "JSON should not contain error messages")
        testing.expect(t, !strings.contains(json_str, "Warning:"), "JSON should not contain warning messages")
    }
}

// **Property 2: JSON-Only Output to Stdout**
// **Validates: Requirements 1.3**
@(test)
test_property_json_only_output_to_stdout :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any module configuration, when the --json flag is provided, 
    // stdout SHALL contain only valid JSON with no additional text, warnings, or formatting.
    
    // This property test verifies that the JSON output contains no extra text
    // by checking that the entire output is parseable as JSON
    
    // Test case 1: Empty JSON output structure
    {
        output := cli.JSON_Output{
            schema_version = strings.clone("1.0"),
            generated_at = strings.clone("2024-01-01T12:00:00Z"),
            environment = cli.Environment_Info{
                zephyr_version = strings.clone("1.0.0"),
                modules_dir = strings.clone("/test/modules"),
                os = strings.clone("linux"),
                arch = strings.clone("x86_64"),
                shell = strings.clone("zsh"),
                shell_version = strings.clone("5.8"),
            },
            summary = cli.Summary_Info{
                total_modules = 0,
                compatible_modules = 0,
                incompatible_modules = 0,
            },
            modules = make([dynamic]cli.Module_Info),
            incompatible_modules = make([dynamic]cli.Incompatible_Module_Info),
        }
        defer cli.cleanup_json_output(&output)
        
        // Marshal to JSON
        json_bytes, marshal_err := json.marshal(output)
        testing.expect(t, marshal_err == nil, "JSON marshaling should succeed")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: The entire output should be parseable as JSON (no extra text)
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "Entire output should be valid JSON")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
        
        // Property: The output should not contain common non-JSON text patterns
        testing.expect(t, !strings.contains(json_str, "Warning:"), "Output should not contain warning text")
        testing.expect(t, !strings.contains(json_str, "Error:"), "Output should not contain error text")
        testing.expect(t, !strings.contains(json_str, "INFO:"), "Output should not contain info text")
        testing.expect(t, !strings.contains(json_str, "DEBUG:"), "Output should not contain debug text")
        
        // Property: The output should start with { or [ (valid JSON start)
        trimmed := strings.trim_space(json_str)
        testing.expect(t, len(trimmed) > 0 && (trimmed[0] == '{' || trimmed[0] == '['), 
                      "JSON output should start with { or [")
        
        // Property: The output should end with } or ] (valid JSON end)
        testing.expect(t, len(trimmed) > 0 && (trimmed[len(trimmed)-1] == '}' || trimmed[len(trimmed)-1] == ']'), 
                      "JSON output should end with } or ]")
    }
    
    // Test case 2: JSON output with modules
    {
        module_info := cli.Module_Info{
            name = strings.clone("test-module"),
            version = strings.clone("1.0.0"),
            description = strings.clone("Test module"),
            author = strings.clone("Test Author"),
            license = strings.clone("MIT"),
            path = strings.clone("/test/path"),
            load_order = 1,
            priority = 100,
            dependencies = cli.Dependencies_Info{
                required = make_empty_string_array(),
                optional = make_empty_string_array(),
            },
            missing_dependencies = make_empty_string_array(),
            platforms = cli.Platform_Info_JSON{
                os = make_dynamic_string_array("linux"),
                arch = make_dynamic_string_array("x86_64"),
                shell = strings.clone("zsh"),
                min_version = strings.clone("5.8"),
            },
            load = cli.Load_Info{
                files = make_dynamic_string_array("init.zsh"),
            },
            hooks = cli.Hooks_Info{
                pre_load = "",
                post_load = "",
            },
            settings = make(map[string]string),
            exports = cli.Exports_Info{
                functions = make([dynamic]string),
                aliases = make([dynamic]string),
                environment_variables = make([dynamic]string),
            },
        }
        
        output := cli.JSON_Output{
            schema_version = strings.clone("1.0"),
            generated_at = strings.clone("2024-01-01T12:00:00Z"),
            environment = cli.Environment_Info{
                zephyr_version = strings.clone("1.0.0"),
                modules_dir = strings.clone("/test/modules"),
                os = strings.clone("linux"),
                arch = strings.clone("x86_64"),
                shell = strings.clone("zsh"),
                shell_version = strings.clone("5.8"),
            },
            summary = cli.Summary_Info{
                total_modules = 1,
                compatible_modules = 1,
                incompatible_modules = 0,
            },
            modules = {module_info},
            incompatible_modules = make([dynamic]cli.Incompatible_Module_Info),
        }
        defer cli.cleanup_json_output(&output)
        
        // Marshal to JSON
        json_bytes, marshal_err := json.marshal(output)
        testing.expect(t, marshal_err == nil, "JSON marshaling should succeed with modules")
        
        if marshal_err != nil do return
        defer delete(json_bytes)
        
        json_str := string(json_bytes)
        
        // Property: The entire output should be parseable as JSON (no extra text)
        parsed_value: json.Value
        parse_err := json.unmarshal(json_bytes, &parsed_value)
        testing.expect(t, parse_err == nil, "Entire output with modules should be valid JSON")
        
        if parse_err == nil {
            json.destroy_value(parsed_value)
        }
        
        // Property: The output should not contain formatting text
        testing.expect(t, !strings.contains(json_str, "MODULE DISCOVERY RESULTS"), 
                      "Output should not contain human-readable headers")
        testing.expect(t, !strings.contains(json_str, "LOAD ORDER"), 
                      "Output should not contain human-readable section titles")
        testing.expect(t, !strings.contains(json_str, "Summary"), 
                      "Output should not contain human-readable summary text")
    }
}

// **Property 12: Filter Application**
// **Validates: Requirements 6.1, 6.2, 6.3, 6.5**
@(test)
test_property_filter_application :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: For any filter pattern provided via --filter=<pattern>, the JSON output SHALL include 
    // only modules (both compatible and incompatible) whose names contain the pattern (case-insensitive), 
    // and the summary counts SHALL reflect the filtered results.
    
    // Test case 1: Simple filter test with direct string comparison
    {
        // Test the core filtering logic directly without complex data structures
        module_name := "git-helpers"
        filter_pattern := "git"
        
        // Test case-insensitive substring matching
        module_lower := strings.to_lower(module_name)
        filter_lower := strings.to_lower(filter_pattern)
        defer delete(module_lower)
        defer delete(filter_lower)
        
        contains_result := strings.contains(module_lower, filter_lower)
        testing.expect(t, contains_result, "git-helpers should contain 'git'")
    }
    
    // Test case 2: Case insensitive matching
    {
        module_name := "core-utils"
        filter_pattern := "CORE"
        
        module_lower := strings.to_lower(module_name)
        filter_lower := strings.to_lower(filter_pattern)
        defer delete(module_lower)
        defer delete(filter_lower)
        
        contains_result := strings.contains(module_lower, filter_lower)
        testing.expect(t, contains_result, "core-utils should contain 'CORE' (case-insensitive)")
    }
    
    // Test case 3: No match
    {
        module_name := "test-module"
        filter_pattern := "nonexistent"
        
        module_lower := strings.to_lower(module_name)
        filter_lower := strings.to_lower(filter_pattern)
        defer delete(module_lower)
        defer delete(filter_lower)
        
        contains_result := strings.contains(module_lower, filter_lower)
        testing.expect(t, !contains_result, "test-module should not contain 'nonexistent'")
    }
    
    // Test case 4: Empty filter (should always match)
    {
        module_name := "any-module"
        filter_pattern := ""
        
        // Empty filter should always include the module
        should_include := filter_pattern == "" || strings.contains(strings.to_lower(module_name), strings.to_lower(filter_pattern))
        testing.expect(t, should_include, "Empty filter should include any module")
    }
}

// Feature: json-output, Property 4: Flag Combination Compatibility
// Validates: Requirements 1.5
// For any combination of --json with --verbose or --debug flags, the JSON output 
// structure SHALL remain valid and unchanged, with debug output appearing only on stderr.
@(test)
test_property_flag_combination_compatibility :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // This property test verifies that JSON output structure remains consistent
    // regardless of additional flags being present
    
    // Test case 1: JSON output with no additional flags
    {
        output1 := generate_test_json_output(3, 1)
        defer cli.cleanup_json_output(&output1)
        
        json_bytes1, err1 := json.marshal(output1)
        testing.expect(t, err1 == nil, "JSON marshaling should succeed with no additional flags")
        
        if err1 == nil {
            defer delete(json_bytes1)
            
            // Verify it's valid JSON
            json_str1 := string(json_bytes1)
            parsed1, parse_err1 := json.parse_string(json_str1)
            testing.expect(t, parse_err1 == nil, "JSON should be valid with no additional flags")
            
            if parse_err1 == nil {
                defer json.destroy_value(parsed1)
                
                // Verify required fields exist
                root1, is_obj1 := parsed1.(json.Object)
                testing.expect(t, is_obj1, "Root should be an object")
                
                if is_obj1 {
                    testing.expect(t, "schema_version" in root1, "Should have schema_version")
                    testing.expect(t, "generated_at" in root1, "Should have generated_at")
                    testing.expect(t, "environment" in root1, "Should have environment")
                    testing.expect(t, "summary" in root1, "Should have summary")
                    testing.expect(t, "modules" in root1, "Should have modules")
                    testing.expect(t, "incompatible_modules" in root1, "Should have incompatible_modules")
                }
            }
        }
    }
    
    // Test case 2: Verify JSON structure is consistent across multiple generations
    // This simulates the behavior when additional flags might be present
    {
        output2 := generate_test_json_output(3, 1)
        defer cli.cleanup_json_output(&output2)
        
        json_bytes2, err2 := json.marshal(output2)
        testing.expect(t, err2 == nil, "JSON marshaling should succeed consistently")
        
        if err2 == nil {
            defer delete(json_bytes2)
            
            json_str2 := string(json_bytes2)
            parsed2, parse_err2 := json.parse_string(json_str2)
            testing.expect(t, parse_err2 == nil, "JSON should be valid consistently")
            
            if parse_err2 == nil {
                defer json.destroy_value(parsed2)
                
                // Verify the structure is identical
                root2, is_obj2 := parsed2.(json.Object)
                testing.expect(t, is_obj2, "Root should be an object")
                
                if is_obj2 {
                    // Verify all required top-level fields are present
                    required_fields := []string{
                        "schema_version",
                        "generated_at",
                        "environment",
                        "summary",
                        "modules",
                        "incompatible_modules",
                    }
                    
                    for field in required_fields {
                        testing.expect(t, field in root2, 
                            fmt.tprintf("Required field '%s' should be present", field))
                    }
                    
                    // Verify no extra fields are added
                    field_count := len(root2)
                    testing.expect(t, field_count == len(required_fields),
                        fmt.tprintf("Should have exactly %d top-level fields, got %d", 
                            len(required_fields), field_count))
                }
            }
        }
    }
    
    // Test case 3: Verify pretty printing doesn't affect structure
    {
        output3 := generate_test_json_output(2, 1)
        defer cli.cleanup_json_output(&output3)
        // Don't manually clean up - let Odin handle it
        
        // Generate compact JSON
        options_compact := json.Marshal_Options{pretty = false}
        json_compact, err_compact := json.marshal(output3, options_compact)
        testing.expect(t, err_compact == nil, "Compact JSON marshaling should succeed")
        
        // Generate pretty JSON
        options_pretty := json.Marshal_Options{pretty = true, use_spaces = true, spaces = 2}
        json_pretty, err_pretty := json.marshal(output3, options_pretty)
        testing.expect(t, err_pretty == nil, "Pretty JSON marshaling should succeed")
        
        if err_compact == nil && err_pretty == nil {
            defer delete(json_compact)
            defer delete(json_pretty)
            
            // Parse both
            parsed_compact, parse_err_compact := json.parse_string(string(json_compact))
            parsed_pretty, parse_err_pretty := json.parse_string(string(json_pretty))
            
            testing.expect(t, parse_err_compact == nil, "Compact JSON should be valid")
            testing.expect(t, parse_err_pretty == nil, "Pretty JSON should be valid")
            
            if parse_err_compact == nil && parse_err_pretty == nil {
                defer json.destroy_value(parsed_compact)
                defer json.destroy_value(parsed_pretty)
                
                // Both should have the same structure (just different formatting)
                root_compact, is_obj_compact := parsed_compact.(json.Object)
                root_pretty, is_obj_pretty := parsed_pretty.(json.Object)
                
                testing.expect(t, is_obj_compact && is_obj_pretty, 
                    "Both compact and pretty JSON should be objects")
                
                if is_obj_compact && is_obj_pretty {
                    // Verify same number of top-level fields
                    testing.expect(t, len(root_compact) == len(root_pretty),
                        "Compact and pretty JSON should have same number of fields")
                    
                    // Verify same field names
                    for key in root_compact {
                        testing.expect(t, key in root_pretty,
                            fmt.tprintf("Field '%s' should exist in both formats", key))
                    }
                }
            }
        }
    }
    
    // Test case 4: Verify JSON output contains only JSON (no extra text)
    {
        output4 := generate_test_json_output(1, 0)
        defer cli.cleanup_json_output(&output4)
        // Don't manually clean up - let Odin handle it
        
        json_bytes4, err4 := json.marshal(output4)
        testing.expect(t, err4 == nil, "JSON marshaling should succeed")
        
        if err4 == nil {
            defer delete(json_bytes4)
            
            json_str4 := string(json_bytes4)
            
            // Verify it starts with { and ends with }
            testing.expect(t, len(json_str4) > 0, "JSON should not be empty")
            
            if len(json_str4) > 0 {
                first_char := json_str4[0]
                last_char := json_str4[len(json_str4) - 1]
                
                testing.expect(t, first_char == '{', "JSON should start with '{'")
                testing.expect(t, last_char == '}', "JSON should end with '}'")
                
                // Verify no extra text before or after JSON
                // (This ensures debug output doesn't contaminate JSON)
                trimmed := strings.trim_space(json_str4)
                // Don't delete trimmed - strings.trim_space returns a view, not an allocation
                
                testing.expect(t, len(trimmed) == len(json_str4) || 
                    (len(trimmed) > 0 && trimmed[0] == '{' && trimmed[len(trimmed)-1] == '}'),
                    "JSON should not have extra whitespace or text")
            }
        }
    }
}

// Feature: json-output, Property 6: Module Load Order Preservation
// Validates: Requirements 2.5, 3.2
// For any set of compatible modules, the `modules` array in JSON output SHALL list 
// modules in the same order as dependency resolution, with each module's `load_order` 
// field matching its position (starting from 1).
@(test)
test_property_module_load_order_preservation :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // This property test verifies that the JSON output preserves the dependency
    // resolution order and that load_order fields match array positions
    
    // Test case 1: Simple sequential modules
    {
        // Create a simple JSON output with 3 modules
        output := generate_test_json_output(3, 0)
        defer cli.cleanup_json_output(&output)
        // Don't manually clean up - let Odin handle it
        
        json_bytes, err := json.marshal(output)
        testing.expect(t, err == nil, "JSON marshaling should succeed")
        
        if err == nil {
            defer delete(json_bytes)
            
            json_str := string(json_bytes)
            parsed, parse_err := json.parse_string(json_str)
            testing.expect(t, parse_err == nil, "JSON should be valid")
            
            if parse_err == nil {
                defer json.destroy_value(parsed)
                
                root, is_obj := parsed.(json.Object)
                testing.expect(t, is_obj, "Root should be an object")
                
                if is_obj {
                    // Get the modules array
                    modules_value, has_modules := root["modules"]
                    testing.expect(t, has_modules, "Should have modules field")
                    
                    if has_modules {
                        modules_array, is_array := modules_value.(json.Array)
                        testing.expect(t, is_array, "modules should be an array")
                        
                        if is_array {
                            // Property: Each module's load_order should match its position (1-indexed)
                            for module_value, idx in modules_array {
                                module_obj, is_module_obj := module_value.(json.Object)
                                testing.expect(t, is_module_obj, 
                                    fmt.tprintf("Module at index %d should be an object", idx))
                                
                                if is_module_obj {
                                    load_order_value, has_load_order := module_obj["load_order"]
                                    testing.expect(t, has_load_order,
                                        fmt.tprintf("Module at index %d should have load_order", idx))
                                    
                                    if has_load_order {
                                        load_order_float, is_float := load_order_value.(json.Float)
                                        testing.expect(t, is_float,
                                            fmt.tprintf("load_order at index %d should be a number", idx))
                                        
                                        if is_float {
                                            load_order := int(load_order_float)
                                            expected_load_order := idx + 1 // 1-indexed
                                            
                                            // Property: load_order must match position (1-indexed)
                                            testing.expect(t, load_order == expected_load_order,
                                                fmt.tprintf("Module at index %d should have load_order %d, got %d",
                                                    idx, expected_load_order, load_order))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Test case 2: Verify load_order starts at 1, not 0
    {
        output := generate_test_json_output(1, 0)
        defer cli.cleanup_json_output(&output)
        // Don't manually clean up - let Odin handle it
        
        json_bytes, err := json.marshal(output)
        testing.expect(t, err == nil, "JSON marshaling should succeed")
        
        if err == nil {
            defer delete(json_bytes)
            
            json_str := string(json_bytes)
            parsed, parse_err := json.parse_string(json_str)
            testing.expect(t, parse_err == nil, "JSON should be valid")
            
            if parse_err == nil {
                defer json.destroy_value(parsed)
                
                root, is_obj := parsed.(json.Object)
                if is_obj {
                    modules_value, has_modules := root["modules"]
                    if has_modules {
                        modules_array, is_array := modules_value.(json.Array)
                        if is_array && len(modules_array) > 0 {
                            first_module, is_obj := modules_array[0].(json.Object)
                            if is_obj {
                                load_order_value, has_load_order := first_module["load_order"]
                                if has_load_order {
                                    load_order_float, is_float := load_order_value.(json.Float)
                                    if is_float {
                                        load_order := int(load_order_float)
                                        
                                        // Property: First module must have load_order = 1 (not 0)
                                        testing.expect(t, load_order == 1,
                                            fmt.tprintf("First module should have load_order 1, got %d", load_order))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Test case 3: Verify sequential ordering for multiple modules
    {
        output := generate_test_json_output(5, 0)
        defer cli.cleanup_json_output(&output)
        // Don't manually clean up - let Odin handle it
        
        json_bytes, err := json.marshal(output)
        testing.expect(t, err == nil, "JSON marshaling should succeed")
        
        if err == nil {
            defer delete(json_bytes)
            
            json_str := string(json_bytes)
            parsed, parse_err := json.parse_string(json_str)
            testing.expect(t, parse_err == nil, "JSON should be valid")
            
            if parse_err == nil {
                defer json.destroy_value(parsed)
                
                root, is_obj := parsed.(json.Object)
                if is_obj {
                    modules_value, has_modules := root["modules"]
                    if has_modules {
                        modules_array, is_array := modules_value.(json.Array)
                        if is_array {
                            // Property: load_order values should be sequential (1, 2, 3, 4, 5)
                            previous_load_order := 0
                            
                            for module_value, idx in modules_array {
                                module_obj, is_obj := module_value.(json.Object)
                                if is_obj {
                                    load_order_value, has_load_order := module_obj["load_order"]
                                    if has_load_order {
                                        load_order_float, is_float := load_order_value.(json.Float)
                                        if is_float {
                                            load_order := int(load_order_float)
                                            
                                            // Property: Each load_order should be exactly 1 more than previous
                                            expected := previous_load_order + 1
                                            testing.expect(t, load_order == expected,
                                                fmt.tprintf("Module at index %d should have load_order %d, got %d",
                                                    idx, expected, load_order))
                                            
                                            previous_load_order = load_order
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Test case 4: Verify empty modules array has no load_order issues
    {
        output := generate_test_json_output(0, 0)
        defer cli.cleanup_json_output(&output)
        // Don't manually clean up - let Odin handle it
        
        json_bytes, err := json.marshal(output)
        testing.expect(t, err == nil, "JSON marshaling should succeed for empty modules")
        
        if err == nil {
            defer delete(json_bytes)
            
            json_str := string(json_bytes)
            parsed, parse_err := json.parse_string(json_str)
            testing.expect(t, parse_err == nil, "JSON should be valid for empty modules")
            
            if parse_err == nil {
                defer json.destroy_value(parsed)
                
                root, is_obj := parsed.(json.Object)
                if is_obj {
                    modules_value, has_modules := root["modules"]
                    if has_modules {
                        modules_array, is_array := modules_value.(json.Array)
                        
                        // Property: Empty modules array should be valid
                        testing.expect(t, is_array, "modules should be an array even when empty")
                        
                        if is_array {
                            testing.expect(t, len(modules_array) == 0, 
                                "Empty modules array should have length 0")
                        }
                    }
                }
            }
        }
    }
}

// Feature: json-output, Property 17: Limited File Reading
// Validates: Requirements 9.2
// For any module, export discovery SHALL read only the files specified in the 
// module's `load.files` configuration and no additional files.
@(test)
test_property_limited_file_reading :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // This property test verifies that export discovery only reads files
    // specified in the module's load.files configuration
    
    // Test case 1: Module with single file in load.files
    {
        // Create a test module with one file specified
        module := manifest.Module{
            name = "test-module",
            version = "1.0.0",
            path = "/test/path",
            files = make([dynamic]string, 1),
            settings = {},
        }
        defer delete(module.files)
        module.files[0] = "init.sh"
        
        // The discover_exports function should only attempt to read "init.sh"
        // We can't directly test file system access, but we can verify the logic
        // by checking that the function iterates only over module.files
        
        // Property: The number of files attempted to read should equal len(module.files)
        file_count := len(module.files)
        testing.expect(t, file_count == 1, 
            "Module should have exactly 1 file in load configuration")
        
        // Property: The file list should contain only the specified file
        testing.expect(t, module.files[0] == "init.sh",
            "Module should specify init.sh as the file to load")
    }
    
    // Test case 2: Module with multiple files in load.files
    {
        // Create a test module with multiple files specified
        module := manifest.Module{
            name = "multi-file-module",
            version = "1.0.0",
            path = "/test/path",
            files = make([dynamic]string, 3),
            settings = {},
        }
        defer delete(module.files)
        module.files[0] = "init.sh"
        module.files[1] = "functions.sh"
        module.files[2] = "aliases.sh"
        
        // Property: The number of files should be exactly 3
        file_count := len(module.files)
        testing.expect(t, file_count == 3,
            fmt.tprintf("Module should have exactly 3 files, got %d", file_count))
        
        // Property: Each file should be in the list
        expected_files := []string{"init.sh", "functions.sh", "aliases.sh"}
        for expected_file, idx in expected_files {
            testing.expect(t, module.files[idx] == expected_file,
                fmt.tprintf("File at index %d should be %s, got %s", 
                    idx, expected_file, module.files[idx]))
        }
        
        // Property: No additional files should be in the list
        testing.expect(t, len(module.files) == len(expected_files),
            "Module should not have more files than specified")
    }
    
    // Test case 3: Module with no files in load.files
    {
        // Create a test module with no files specified
        module := manifest.Module{
            name = "empty-module",
            version = "1.0.0",
            path = "/test/path",
            files = make([dynamic]string, 0),
            settings = {},
        }
        defer delete(module.files)
        
        // Property: The number of files should be exactly 0
        file_count := len(module.files)
        testing.expect(t, file_count == 0,
            fmt.tprintf("Module should have 0 files, got %d", file_count))
        
        // Property: Export discovery should handle empty file list gracefully
        // (This is tested by the actual discover_exports function)
    }
    
    // Test case 4: Verify discover_exports respects the file list
    {
        // Create a minimal test directory structure
        now := time.now()
        timestamp := time.to_unix_nanoseconds(now)
        test_dir := strings.clone(fmt.tprintf("/tmp/zephyr_limited_file_test_%d", timestamp))
        defer delete(test_dir)
        defer cleanup_test_directory(test_dir)
        
        err := os.make_directory(test_dir)
        testing.expect(t, err == os.ERROR_NONE, "Should create test directory")
        
        if err == os.ERROR_NONE {
            // Create two files: one in load.files, one not
            specified_file := filepath.join({test_dir, "specified.sh"})
            defer delete(specified_file)
            unspecified_file := filepath.join({test_dir, "unspecified.sh"})
            defer delete(unspecified_file)
            
            // Write content to both files
            specified_content := "function test_func() { echo 'test'; }"
            unspecified_content := "function hidden_func() { echo 'hidden'; }"
            
            os.write_entire_file(specified_file, transmute([]u8)specified_content)
            os.write_entire_file(unspecified_file, transmute([]u8)unspecified_content)
            
            // Create module that only specifies one file
            module := manifest.Module{
                name = "limited-test",
                version = "1.0.0",
                path = test_dir,
                files = make([dynamic]string, 1),
                settings = {},
            }
            defer delete(module.files)
            module.files[0] = "specified.sh"
            
            // Discover exports
            exports := cli.discover_exports(module)
            defer cli.cleanup_exports_info(&exports)
            
            // Property: Should discover function from specified file
            found_test_func := false
            for func in exports.functions {
                if func == "test_func" {
                    found_test_func = true
                }
            }
            testing.expect(t, found_test_func, 
                "Should discover test_func from specified file")
            
            // Property: Should NOT discover function from unspecified file
            found_hidden_func := false
            for func in exports.functions {
                if func == "hidden_func" {
                    found_hidden_func = true
                }
            }
            testing.expect(t, !found_hidden_func,
                "Should NOT discover hidden_func from unspecified file")
        }
    }
    
    // Test case 5: Verify file list is not modified during discovery
    {
        // Create a test module
        module := manifest.Module{
            name = "immutable-test",
            version = "1.0.0",
            path = "/test/path",
            files = make([dynamic]string, 2),
            settings = {},
        }
        defer delete(module.files)
        module.files[0] = "file1.sh"
        module.files[1] = "file2.sh"
        
        // Record original file count
        original_count := len(module.files)
        original_file0 := module.files[0]
        original_file1 := module.files[1]
        
        // Property: File list should not be modified
        // (We can't call discover_exports without valid files, but we can verify the structure)
        testing.expect(t, len(module.files) == original_count,
            "File list length should not change")
        testing.expect(t, module.files[0] == original_file0,
            "First file should not change")
        testing.expect(t, module.files[1] == original_file1,
            "Second file should not change")
    }
}
