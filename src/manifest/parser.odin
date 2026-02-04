package manifest

import "core:os"
import "core:fmt"
import "core:strings"

// ParseError represents different types of parsing errors
ParseError :: enum {
    None,
    FileNotFound,
    FileReadError,
    TomlParseError,
    InvalidSchema,
}

// ParseResult contains the result of parsing and any error information
ParseResult :: struct {
    module: Module,
    error:  ParseError,
    message: string,
}

// parse reads and parses a TOML manifest file into a Module struct
// Note: This is a simplified implementation until core:encoding/toml is available
parse :: proc(file_path: string) -> (Module, bool) {
    result := parse_detailed(file_path)
    return result.module, result.error == .None
}

// parse_detailed provides detailed error information for debugging
parse_detailed :: proc(file_path: string) -> ParseResult {
    result := ParseResult{
        error = .None,
    }
    
    // Check if file exists
    if !os.exists(file_path) {
        result.error = .FileNotFound
        result.message = fmt.tprintf("Manifest file not found: %s", file_path)
        return result
    }
    
    // Read the entire file
    data, read_ok := os.read_entire_file(file_path)
    if !read_ok {
        result.error = .FileReadError
        result.message = fmt.tprintf("Failed to read manifest file: %s", file_path)
        return result
    }
    defer delete(data)
    
    // Initialize module with defaults
    result.module = Module{
        version = "0.0.0",
        priority = 100, // Default priority
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    
    // Basic TOML-like parsing (simplified for now)
    content := string(data)
    lines := strings.split_lines(content)
    defer delete(lines)
    
    current_section := ""
    
    for line in lines {
        trimmed := strings.trim_space(line)
        if len(trimmed) == 0 || strings.has_prefix(trimmed, "#") {
            continue
        }
        
        // Section headers
        if strings.has_prefix(trimmed, "[") && strings.has_suffix(trimmed, "]") {
            current_section = strings.trim(trimmed, "[]")
            continue
        }
        
        // Key-value pairs
        if strings.contains(trimmed, "=") {
            parts := strings.split(trimmed, "=")
            if len(parts) >= 2 {
                key := strings.trim_space(parts[0])
                value_part := strings.join(parts[1:], "=") // Handle values with = in them
                value := strings.trim_space(value_part)
                
                // Remove surrounding quotes if present
                if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
                    value = value[1:len(value)-1]
                }
                
                switch current_section {
                case "module":
                    switch key {
                    case "name":
                        if len(value) == 0 {
                            result.error = .InvalidSchema
                            result.message = fmt.tprintf("Invalid or empty 'name' field in [module] section of %s", file_path)
                            return result
                        }
                        result.module.name = strings.clone(value)
                    case "version":
                        result.module.version = strings.clone(value)
                    case "description":
                        result.module.description = strings.clone(value)
                    case "author":
                        result.module.author = strings.clone(value)
                    case "license":
                        result.module.license = strings.clone(value)
                    }
                case "load":
                    switch key {
                    case "priority":
                        // Simple integer parsing - fix the logic
                        priority := 0
                        for char in value {
                            if char >= '0' && char <= '9' {
                                priority = priority * 10 + int(char - '0')
                            } else {
                                priority = 100 // default on invalid input
                                break
                            }
                        }
                        if priority == 0 && len(value) > 0 && value[0] != '0' {
                            priority = 100 // default if parsing failed
                        }
                        result.module.priority = priority
                    case "files":
                        // Parse array format: ["file1.zsh", "file2.zsh"]
                        if strings.has_prefix(value, "[") && strings.has_suffix(value, "]") {
                            array_content := strings.trim(value, "[]")
                            if len(array_content) > 0 {
                                items := strings.split(array_content, ",")
                                defer delete(items)
                                
                                for item in items {
                                    trimmed_item := strings.trim_space(item)
                                    // Remove quotes
                                    if len(trimmed_item) >= 2 && trimmed_item[0] == '"' && trimmed_item[len(trimmed_item)-1] == '"' {
                                        trimmed_item = trimmed_item[1:len(trimmed_item)-1]
                                    }
                                    if len(trimmed_item) > 0 {
                                        append(&result.module.files, strings.clone(trimmed_item))
                                    }
                                }
                            }
                        } else {
                            // Single file without array brackets
                            if len(value) > 0 {
                                append(&result.module.files, strings.clone(value))
                            }
                        }
                    }
                case "dependencies":
                    switch key {
                    case "required":
                        // Parse array format: ["dep1", "dep2"]
                        if strings.has_prefix(value, "[") && strings.has_suffix(value, "]") {
                            array_content := strings.trim(value, "[]")
                            if len(array_content) > 0 {
                                items := strings.split(array_content, ",")
                                defer delete(items)
                                
                                for item in items {
                                    trimmed_item := strings.trim_space(item)
                                    // Remove quotes
                                    if len(trimmed_item) >= 2 && trimmed_item[0] == '"' && trimmed_item[len(trimmed_item)-1] == '"' {
                                        trimmed_item = trimmed_item[1:len(trimmed_item)-1]
                                    }
                                    if len(trimmed_item) > 0 {
                                        append(&result.module.required, strings.clone(trimmed_item))
                                    }
                                }
                            }
                        } else {
                            // Single dependency without array brackets
                            if len(value) > 0 {
                                append(&result.module.required, strings.clone(value))
                            }
                        }
                    case "optional":
                        // Parse array format: ["dep1", "dep2"]
                        if strings.has_prefix(value, "[") && strings.has_suffix(value, "]") {
                            array_content := strings.trim(value, "[]")
                            if len(array_content) > 0 {
                                items := strings.split(array_content, ",")
                                defer delete(items)
                                
                                for item in items {
                                    trimmed_item := strings.trim_space(item)
                                    // Remove quotes
                                    if len(trimmed_item) >= 2 && trimmed_item[0] == '"' && trimmed_item[len(trimmed_item)-1] == '"' {
                                        trimmed_item = trimmed_item[1:len(trimmed_item)-1]
                                    }
                                    if len(trimmed_item) > 0 {
                                        append(&result.module.optional, strings.clone(trimmed_item))
                                    }
                                }
                            }
                        } else {
                            // Single dependency without array brackets
                            if len(value) > 0 {
                                append(&result.module.optional, strings.clone(value))
                            }
                        }
                    }
                case "hooks":
                    switch key {
                    case "pre_load":
                        result.module.hooks.pre_load = strings.clone(value)
                    case "post_load":
                        result.module.hooks.post_load = strings.clone(value)
                    }
                case "platforms":
                    switch key {
                    case "shell":
                        result.module.platforms.shell = strings.clone(value)
                    case "min_version":
                        result.module.platforms.min_version = strings.clone(value)
                    }
                case "settings":
                    result.module.settings[strings.clone(key)] = strings.clone(value)
                }
            }
        }
    }
    
    // Validate that we have at least a module name
    if len(result.module.name) == 0 {
        result.error = .InvalidSchema
        result.message = fmt.tprintf("Missing required 'name' field in [module] section of %s", file_path)
        return result
    }
    
    return result
}