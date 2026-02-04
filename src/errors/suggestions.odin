#+feature dynamic-literals
package errors

import "core:fmt"
import "core:strings"
import "../colors"

// ErrorType represents different categories of errors
ErrorType :: enum {
    DirectoryNotFound,
    DirectoryNotAccessible,
    ManifestParseError,
    MissingDependency,
    CircularDependency,
    InvalidModuleName,
    ModuleAlreadyExists,
    FileCreationError,
    InvalidManifestSchema,
    PlatformIncompatible,
}

// Suggestion represents a suggested fix for an error
Suggestion :: struct {
    description: string,
    command:     string,
    explanation: string,
}

// get_suggestions returns a list of suggestions for a given error type
get_suggestions :: proc(error_type: ErrorType, ctx: string = "") -> []Suggestion {
    // For now, return empty slice to fix compilation
    // TODO: Implement proper suggestions
    return {}
}

// print_suggestions displays formatted suggestions for an error
print_suggestions :: proc(error_type: ErrorType, ctx: string = "") {
    suggestions := get_suggestions(error_type, ctx)
    if len(suggestions) == 0 {
        return
    }
    
    colors.print_info("Suggested fixes:")
    fmt.println("")
    
    for suggestion, i in suggestions {
        fmt.printf("  %d. %s\n", i+1, colors.bold(suggestion.description))
        
        if suggestion.command != "" {
            fmt.printf("     %s %s\n", colors.dim("Command:"), colors.info(suggestion.command))
        }
        
        if suggestion.explanation != "" {
            fmt.printf("     %s %s\n", colors.dim("Why:"), suggestion.explanation)
        }
        
        fmt.println("")
    }
}

// suggest_for_directory_error provides suggestions for directory-related errors
suggest_for_directory_error :: proc(path: string, exists: bool, is_accessible: bool) {
    if !exists {
        print_suggestions(.DirectoryNotFound)
    } else if !is_accessible {
        print_suggestions(.DirectoryNotAccessible)
    }
}

// suggest_for_manifest_error provides suggestions for manifest parsing errors
suggest_for_manifest_error :: proc(error_message: string, file_path: string) {
    // Analyze the error message to provide specific suggestions
    lower_error := strings.to_lower(error_message)
    
    if strings.contains(lower_error, "missing") && strings.contains(lower_error, "name") {
        print_suggestions(.InvalidManifestSchema)
    } else if strings.contains(lower_error, "toml") || strings.contains(lower_error, "parse") {
        print_suggestions(.ManifestParseError)
    } else {
        print_suggestions(.ManifestParseError)
    }
}

// suggest_for_dependency_error provides suggestions for dependency-related errors
suggest_for_dependency_error :: proc(error_message: string) {
    lower_error := strings.to_lower(error_message)
    
    if strings.contains(lower_error, "missing") {
        print_suggestions(.MissingDependency)
    } else if strings.contains(lower_error, "circular") {
        print_suggestions(.CircularDependency)
    }
}

// suggest_for_module_name_error provides suggestions for module naming errors
suggest_for_module_name_error :: proc(module_name: string) {
    print_suggestions(.InvalidModuleName)
}

// suggest_for_module_exists_error provides suggestions when module already exists
suggest_for_module_exists_error :: proc(module_name: string) {
    print_suggestions(.ModuleAlreadyExists, module_name)
}

// suggest_for_file_creation_error provides suggestions for file creation errors
suggest_for_file_creation_error :: proc(file_path: string) {
    print_suggestions(.FileCreationError)
}

// suggest_for_platform_error provides suggestions for platform compatibility errors
suggest_for_platform_error :: proc() {
    print_suggestions(.PlatformIncompatible)
}