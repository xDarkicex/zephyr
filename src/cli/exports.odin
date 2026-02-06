package cli

import "core:os"
import "core:strings"
import "core:fmt"
import "core:path/filepath"
import "../manifest"

// cleanup_exports_info frees all allocated memory in an Exports_Info struct
cleanup_exports_info :: proc(exports: ^Exports_Info) {
    if exports == nil do return
    
    // Clean up functions - these are dynamic arrays
    if exports.functions != nil {
        for &func in exports.functions {
            if func != "" {
                delete(func)
                func = ""
            }
        }
        delete(exports.functions)
        exports.functions = nil
    }
    
    // Clean up aliases - these are dynamic arrays
    if exports.aliases != nil {
        for &alias in exports.aliases {
            if alias != "" {
                delete(alias)
                alias = ""
            }
        }
        delete(exports.aliases)
        exports.aliases = nil
    }
    
    // Clean up environment variables - these are dynamic arrays
    if exports.environment_variables != nil {
        for &env_var in exports.environment_variables {
            if env_var != "" {
                delete(env_var)
                env_var = ""
            }
        }
        delete(exports.environment_variables)
        exports.environment_variables = nil
    }
}

// discover_exports parses module files to find functions, aliases, and env vars
discover_exports :: proc(module: manifest.Module) -> Exports_Info {
    // Use dynamic arrays directly
    functions := make([dynamic]string)
    aliases := make([dynamic]string)
    environment_variables := make([dynamic]string)
    
    // Parse each file in the module's load configuration
    for file_name in module.files {
        file_path := filepath.join({module.path, file_name})
        defer delete(file_path)
        
        content, ok := os.read_entire_file(file_path)
        if !ok {
            // Handle file read errors gracefully with empty arrays
            continue
        }
        defer delete(content)
        
        content_str := string(content)
        
        // Discover functions
        discover_functions(content_str, &functions)
        
        // Discover aliases
        discover_aliases(content_str, &aliases)
    }
    
    // Add environment variables from settings
    for key, _ in module.settings {
        // Build the environment variable name manually to avoid fmt.tprintf allocations
        module_upper := strings.to_upper(module.name)
        key_upper := strings.to_upper(key)
        defer delete(module_upper)
        defer delete(key_upper)
        
        env_var_name := strings.concatenate({"ZSH_MODULE_", module_upper, "_", key_upper})
        append(&environment_variables, env_var_name)
    }
    
    // Return the dynamic arrays directly
    return Exports_Info{
        functions = functions,
        aliases = aliases,
        environment_variables = environment_variables,
    }
}

// discover_functions finds function definitions in shell script content
// Patterns: function_name() and function function_name
discover_functions :: proc(content: string, functions: ^[dynamic]string) {
    lines := strings.split(content, "\n")
    defer delete(lines)
    
    for line in lines {
        trimmed := strings.trim_space(line)
        
        // Skip comments
        if strings.has_prefix(trimmed, "#") {
            continue
        }
        
        // Pattern 2: function function_name { (check this first to avoid double-counting)
        if strings.has_prefix(trimmed, "function ") {
            parts := strings.split(trimmed, " ")
            if len(parts) >= 2 {
                func_name := strings.trim_space(parts[1])
                // Remove trailing { or () if present
                func_name = strings.trim_suffix(func_name, "{")
                func_name = strings.trim_suffix(func_name, "()")
                func_name = strings.trim_space(func_name)
                if func_name != "" {
                    append(functions, strings.clone(func_name))
                }
            }
            delete(parts)
            continue  // Skip to next line to avoid double-counting
        }
        
        // Pattern 1: function_name() {
        if strings.contains(trimmed, "()") && strings.contains(trimmed, "{") {
            parts := strings.split(trimmed, "(")
            if len(parts) > 0 {
                func_name := strings.trim_space(parts[0])
                if func_name != "" && !strings.has_prefix(func_name, "#") {
                    append(functions, strings.clone(func_name))
                }
            }
            delete(parts)
        }
    }
}

// discover_aliases finds alias definitions in shell script content
// Pattern: alias name='...'
discover_aliases :: proc(content: string, aliases: ^[dynamic]string) {
    lines := strings.split(content, "\n")
    defer delete(lines)
    
    for line in lines {
        trimmed := strings.trim_space(line)
        
        // Skip comments
        if strings.has_prefix(trimmed, "#") {
            continue
        }
        
        // Pattern: alias name='...'
        if strings.has_prefix(trimmed, "alias ") {
            // Extract alias name
            after_alias := strings.trim_prefix(trimmed, "alias ")
            parts := strings.split(after_alias, "=")
            if len(parts) >= 2 {
                alias_name := strings.trim_space(parts[0])
                if alias_name != "" {
                    append(aliases, strings.clone(alias_name))
                }
            }
            delete(parts)
        }
    }
}
