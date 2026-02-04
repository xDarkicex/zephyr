package cli

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "../loader"
import "../manifest"

// ValidationResult represents the result of validating a single module
ValidationResult :: struct {
    module_path:     string,
    module_name:     string,
    is_valid:        bool,
    parse_error:     string,
    dependency_errors: [dynamic]string,
}

// ValidationSummary contains overall validation results
ValidationSummary :: struct {
    total_modules:    int,
    valid_modules:    int,
    invalid_modules:  int,
    results:          [dynamic]ValidationResult,
    circular_deps:    bool,
    circular_error:   string,
}

// validate_manifests implements the 'zephyr validate' command
// Validates all discovered manifests and reports errors with file locations
validate_manifests :: proc() {
    // Get modules directory
    modules_dir := loader.get_modules_dir()
    
    // Verify directory exists and is accessible
    if !os.exists(modules_dir) {
        fmt.eprintfln("Error: Modules directory does not exist: %s", modules_dir)
        fmt.eprintln("Create the directory or set ZSH_MODULES_DIR to a valid path")
        fmt.eprintln("Use 'zephyr init <module-name>' to create your first module")
        os.exit(1)
    }
    
    // Check if it's actually a directory
    file_info, stat_err := os.stat(modules_dir)
    if stat_err != os.ERROR_NONE {
        fmt.eprintfln("Error: Cannot access modules directory: %s", modules_dir)
        fmt.eprintfln("System error: %v", stat_err)
        os.exit(1)
    }
    
    if !file_info.is_dir {
        fmt.eprintfln("Error: Path is not a directory: %s", modules_dir)
        os.exit(1)
    }
    
    fmt.eprintfln("Validating modules in: %s", modules_dir)
    fmt.println("")
    
    // Initialize validation summary
    summary := ValidationSummary{
        results = make([dynamic]ValidationResult),
    }
    defer cleanup_validation_summary(&summary)
    
    // Discover and parse all manifests
    parse_all_manifests(modules_dir, &summary)
    
    // Validate dependency references
    validate_dependency_references(&summary)
    
    // Check for circular dependencies
    check_circular_dependencies(&summary)
    
    // Provide summary of validation results
    provide_validation_summary(&summary)
}

// cleanup_validation_summary cleans up allocated memory in ValidationSummary
cleanup_validation_summary :: proc(summary: ^ValidationSummary) {
    for &result in summary.results {
        // Clean up all cloned strings in ValidationResult
        delete(result.module_path)
        delete(result.module_name)
        delete(result.parse_error)
        
        // Clean up dependency error strings
        for error in result.dependency_errors {
            delete(error)
        }
        delete(result.dependency_errors)
    }
    delete(summary.results)
    
    // Clean up circular error string if it exists
    if len(summary.circular_error) > 0 {
        delete(summary.circular_error)
    }
}

// parse_all_manifests discovers and parses all manifests in the modules directory
parse_all_manifests :: proc(modules_dir: string, summary: ^ValidationSummary) {
    // Recursively scan for module.toml files
    scan_for_manifests(modules_dir, summary)
    
    summary.total_modules = len(summary.results)
    
    fmt.eprintfln("Found %d module manifest(s)", summary.total_modules)
    fmt.println("")
    
    if summary.total_modules == 0 {
        fmt.println("No module manifests found.")
        fmt.println("To create a new module, use: zephyr init <module-name>")
        return
    }
    
    // Count valid/invalid modules
    for result in summary.results {
        if result.is_valid {
            summary.valid_modules += 1
        } else {
            summary.invalid_modules += 1
        }
    }
}

// scan_for_manifests recursively scans directories for module.toml files and parses them
scan_for_manifests :: proc(dir_path: string, summary: ^ValidationSummary) {
    handle, err := os.open(dir_path)
    if err != os.ERROR_NONE {
        // Skip directories we can't access
        return
    }
    defer os.close(handle)
    
    entries, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        // Skip directories we can't read
        return
    }
    defer os.file_info_slice_delete(entries)
    
    for entry in entries {
        if !entry.is_dir {
            continue
        }
        
        module_dir := filepath.join({dir_path, entry.name})
        manifest_path := filepath.join({module_dir, "module.toml"})
        
        // Check if this directory contains a module.toml file
        if os.exists(manifest_path) {
            result := ValidationResult{
                module_path = strings.clone(module_dir),
                dependency_errors = make([dynamic]string),
            }
            
            // Parse the manifest using detailed parsing
            parse_result := manifest.parse_detailed(manifest_path)
            
            if parse_result.error == .None {
                result.is_valid = true
                result.module_name = strings.clone(parse_result.module.name)
            } else {
                result.is_valid = false
                result.module_name = strings.clone(entry.name) // Use directory name as fallback
                result.parse_error = strings.clone(parse_result.message)
            }
            
            append(&summary.results, result)
        }
        
        // Recursively scan subdirectories
        scan_for_manifests(module_dir, summary)
    }
}
// report_parsing_errors displays detailed parsing errors with file locations
report_parsing_errors :: proc(summary: ^ValidationSummary) {
    if summary.invalid_modules == 0 {
        return
    }
    
    fmt.println("PARSING ERRORS:")
    fmt.println("===============")
    
    for result in summary.results {
        if !result.is_valid && len(result.parse_error) > 0 {
            manifest_path := filepath.join({result.module_path, "module.toml"})
            fmt.eprintfln("✗ %s", manifest_path)
            fmt.eprintfln("  Error: %s", result.parse_error)
            fmt.println("")
        }
    }
}
// validate_dependency_references checks that all dependency references are valid
validate_dependency_references :: proc(summary: ^ValidationSummary) {
    // Build a set of available module names from valid modules
    available_modules := make(map[string]bool)
    defer delete(available_modules)
    
    for result in summary.results {
        if result.is_valid {
            available_modules[result.module_name] = true
        }
    }
    
    // Check dependencies for each valid module
    for &result in summary.results {
        if !result.is_valid {
            continue // Skip modules that failed to parse
        }
        
        // Re-parse the module to get dependency information
        manifest_path := filepath.join({result.module_path, "module.toml"})
        module, parse_ok := manifest.parse(manifest_path)
        if !parse_ok {
            continue // This shouldn't happen since we already validated parsing
        }
        
        // Check required dependencies
        for dep in module.required {
            if dep not_in available_modules {
                error_msg := fmt.tprintf("Missing required dependency: '%s'", dep)
                append(&result.dependency_errors, strings.clone(error_msg))
            }
        }
        
        // Check optional dependencies (warn but don't fail)
        for dep in module.optional {
            if dep not_in available_modules {
                error_msg := fmt.tprintf("Optional dependency not found: '%s' (warning)", dep)
                append(&result.dependency_errors, strings.clone(error_msg))
            }
        }
        
        // Clean up the module
        cleanup_module(&module)
    }
}

// cleanup_module cleans up allocated memory in a Module struct
cleanup_module :: proc(module: ^manifest.Module) {
    // Clean up string fields
    delete(module.name)
    delete(module.version)
    delete(module.description)
    delete(module.author)
    delete(module.license)
    delete(module.path)
    
    // Clean up dynamic arrays of strings
    for dep in module.required {
        delete(dep)
    }
    delete(module.required)
    
    for dep in module.optional {
        delete(dep)
    }
    delete(module.optional)
    
    for file in module.files {
        delete(file)
    }
    delete(module.files)
    
    // Clean up platform filter strings
    for os in module.platforms.os {
        delete(os)
    }
    delete(module.platforms.os)
    
    for arch in module.platforms.arch {
        delete(arch)
    }
    delete(module.platforms.arch)
    delete(module.platforms.shell)
    delete(module.platforms.min_version)
    
    // Clean up hooks
    delete(module.hooks.pre_load)
    delete(module.hooks.post_load)
    
    // Clean up settings map
    for key, value in module.settings {
        delete(key)
        delete(value)
    }
    delete(module.settings)
}

// report_dependency_errors displays dependency validation errors
report_dependency_errors :: proc(summary: ^ValidationSummary) {
    has_dependency_errors := false
    
    // Check if any modules have dependency errors
    for result in summary.results {
        if len(result.dependency_errors) > 0 {
            has_dependency_errors = true
            break
        }
    }
    
    if !has_dependency_errors {
        return
    }
    
    fmt.println("DEPENDENCY ERRORS:")
    fmt.println("==================")
    
    for result in summary.results {
        if len(result.dependency_errors) > 0 {
            manifest_path := filepath.join({result.module_path, "module.toml"})
            fmt.eprintfln("✗ %s (%s)", manifest_path, result.module_name)
            
            for error in result.dependency_errors {
                if strings.contains(error, "warning") {
                    fmt.eprintfln("  ⚠  %s", error)
                } else {
                    fmt.eprintfln("  ✗ %s", error)
                }
            }
            fmt.println("")
        }
    }
}
// check_circular_dependencies detects circular dependencies using the resolver
check_circular_dependencies :: proc(summary: ^ValidationSummary) {
    // Only check for circular dependencies if we have valid modules
    if summary.valid_modules == 0 {
        return
    }
    
    // Build a list of valid modules for dependency resolution
    valid_modules := make([dynamic]manifest.Module)
    defer delete(valid_modules)
    
    for result in summary.results {
        if !result.is_valid {
            continue
        }
        
        // Re-parse the module to get full module data
        manifest_path := filepath.join({result.module_path, "module.toml"})
        module, parse_ok := manifest.parse(manifest_path)
        if parse_ok {
            module.path = strings.clone(result.module_path)
            append(&valid_modules, module)
        }
    }
    
    // Use the existing resolver to detect circular dependencies
    resolved_modules, err := loader.resolve(valid_modules)
    if err != "" {
        summary.circular_deps = true
        summary.circular_error = strings.clone(err)
    }
    
    // Clean up
    if resolved_modules != nil {
        defer delete(resolved_modules)
    }
    
    for &module in valid_modules {
        cleanup_module(&module)
    }
}

// report_circular_dependencies displays circular dependency errors
report_circular_dependencies :: proc(summary: ^ValidationSummary) {
    if !summary.circular_deps {
        return
    }
    
    fmt.println("CIRCULAR DEPENDENCY ERROR:")
    fmt.println("==========================")
    fmt.eprintfln("✗ %s", summary.circular_error)
    fmt.println("")
    fmt.println("Circular dependencies prevent modules from loading in a valid order.")
    fmt.println("Review your module dependencies to break the cycle.")
    fmt.println("")
}
// provide_validation_summary displays a comprehensive summary of validation results
provide_validation_summary :: proc(summary: ^ValidationSummary) {
    // Report parsing errors first
    report_parsing_errors(summary)
    
    // Report dependency errors
    report_dependency_errors(summary)
    
    // Report circular dependency errors
    report_circular_dependencies(summary)
    
    // Display overall summary
    fmt.println("VALIDATION SUMMARY:")
    fmt.println("===================")
    fmt.eprintfln("Total modules found: %d", summary.total_modules)
    fmt.eprintfln("Valid modules: %d", summary.valid_modules)
    fmt.eprintfln("Invalid modules: %d", summary.invalid_modules)
    
    if summary.total_modules == 0 {
        fmt.println("")
        fmt.println("No modules found. Use 'zephyr init <module-name>' to create your first module.")
        return
    }
    
    // Count modules with dependency errors
    modules_with_dep_errors := 0
    for result in summary.results {
        if len(result.dependency_errors) > 0 {
            modules_with_dep_errors += 1
        }
    }
    
    if modules_with_dep_errors > 0 {
        fmt.eprintfln("Modules with dependency issues: %d", modules_with_dep_errors)
    }
    
    if summary.circular_deps {
        fmt.println("Circular dependencies detected: YES")
    }
    
    fmt.println("")
    
    // Determine overall validation status
    overall_valid := summary.invalid_modules == 0 && modules_with_dep_errors == 0 && !summary.circular_deps
    
    if overall_valid {
        fmt.println("✓ All modules are valid and ready to load!")
        fmt.println("Use 'zephyr list' to see the load order.")
    } else {
        fmt.println("✗ Validation failed. Please fix the errors above.")
        fmt.println("Use 'zephyr validate' again after making changes.")
        os.exit(1)
    }
}