package cli

import "core:fmt"
import "core:os"
import "core:strings"
import "../loader"
import "../manifest"
import "../colors"
import "../errors"

// list_modules implements the 'zephyr list' command
// Displays discovered modules in resolved dependency order with priorities and dependencies
list_modules :: proc() {
    // Get modules directory
    modules_dir := loader.get_modules_dir()
    
    // Verify directory exists and is accessible
    if !os.exists(modules_dir) {
        colors.print_error("Modules directory does not exist: %s", modules_dir)
        fmt.eprintln("")
        errors.suggest_for_directory_error(modules_dir, false, false)
        os.exit(1)
    }
    
    // Check if it's actually a directory
    file_info, stat_err := os.stat(modules_dir)
    if stat_err != os.ERROR_NONE {
        colors.print_error("Cannot access modules directory: %s", modules_dir)
        colors.print_error("System error: %v", stat_err)
        fmt.eprintln("")
        errors.suggest_for_directory_error(modules_dir, true, false)
        os.exit(1)
    }
    
    if !file_info.is_dir {
        colors.print_error("Path is not a directory: %s", modules_dir)
        fmt.eprintln("")
        errors.suggest_for_directory_error(modules_dir, true, false)
        os.exit(1)
    }
    
    // Discovery phase
    modules := loader.discover(modules_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    if len(modules) == 0 {
        colors.print_warning("No modules found in: %s", modules_dir)
        fmt.eprintln("")
        errors.suggest_for_directory_error(modules_dir, true, true)
        return
    }
    
    // Platform filtering phase
    current_platform := loader.get_current_platform()
    compatible_indices := loader.filter_compatible_indices(modules)
    defer delete(compatible_indices)
    
    // Dependency resolution phase
    resolved_modules, err := loader.resolve_filtered(modules, compatible_indices)
    if err != "" {
        colors.print_error("Dependency resolution failed")
        colors.print_error("Details: %s", err)
        fmt.eprintln("")
        errors.suggest_for_dependency_error(err)
        return
    }
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    // Display header
    fmt.println("")
    errors.print_formatted_info("MODULE DISCOVERY RESULTS")
    fmt.printf("  %s %s\n", colors.dim("Directory:"), modules_dir)
    fmt.printf("  %s %d total, %d compatible\n", colors.dim("Modules:"), len(modules), len(compatible_indices))
    fmt.printf("  %s %s/%s, shell: %s %s\n", colors.dim("Platform:"), 
        current_platform.os, current_platform.arch, current_platform.shell, current_platform.version)
    fmt.println("")
    
    // Show incompatible modules if any
    if len(modules) > len(compatible_indices) {
        errors.print_formatted_warning("INCOMPATIBLE MODULES", 
            fmt.tprintf("%d module(s) skipped due to platform restrictions", 
                len(modules) - len(compatible_indices)))
        
        for module, idx in modules {
            // Check if this module is in the compatible list
            is_compatible := false
            for comp_idx in compatible_indices {
                if comp_idx == idx {
                    is_compatible = true
                    break
                }
            }
            
            if !is_compatible {
                fmt.printf("  %s %s", colors.warning_symbol(), colors.bold(module.name))
                if len(module.version) > 0 && module.version != "0.0.0" {
                    fmt.printf(" %s", colors.dim(fmt.tprintf("v%s", module.version)))
                }
                
                // Show platform requirements in a more readable format
                filter := module.platforms
                requirements := make([dynamic]string)
                defer delete(requirements)
                
                if len(filter.os) > 0 {
                    os_list := strings.join(filter.os[:], ", ")
                    append(&requirements, fmt.tprintf("OS: %s", os_list))
                }
                
                if len(filter.arch) > 0 {
                    arch_list := strings.join(filter.arch[:], ", ")
                    append(&requirements, fmt.tprintf("Arch: %s", arch_list))
                }
                
                if filter.shell != "" {
                    append(&requirements, fmt.tprintf("Shell: %s", filter.shell))
                }
                
                if filter.min_version != "" {
                    append(&requirements, fmt.tprintf("Min version: %s", filter.min_version))
                }
                
                if len(requirements) > 0 {
                    req_text := strings.join(requirements[:], ", ")
                    fmt.printf(" %s", colors.dim(fmt.tprintf("(%s)", req_text)))
                }
                
                fmt.println("")
            }
        }
        fmt.println("")
    }
    
    if len(compatible_indices) == 0 {
        errors.print_formatted_warning("No compatible modules", 
            "All modules have platform restrictions that don't match your system")
        return
    }
    
    errors.print_formatted_success("LOAD ORDER", 
        fmt.tprintf("%d module(s) will be loaded in dependency order", len(resolved_modules)))
    fmt.println("")
    
    // Display modules in resolved order using a table format
    headers := []string{"#", "Module", "Version", "Priority", "Dependencies"}
    rows := make([][]string, len(resolved_modules))
    defer delete(rows)
    
    for module, idx in resolved_modules {
        row := make([]string, 5)
        
        // Position
        row[0] = fmt.tprintf("%d", idx + 1)
        
        // Module name
        row[1] = module.name
        
        // Version
        if len(module.version) > 0 && module.version != "0.0.0" {
            row[2] = module.version
        } else {
            row[2] = "-"
        }
        
        // Priority
        row[3] = fmt.tprintf("%d", module.priority)
        
        // Dependencies
        if len(module.required) > 0 {
            deps := strings.join(module.required[:], ", ")
            row[4] = deps
        } else {
            row[4] = "-"
        }
        
        rows[idx] = row
    }
    
    table := errors.format_table(headers, rows)
    fmt.print(table)
    fmt.println("")
    
    // Show additional details for each module
    for module, idx in resolved_modules {
        fmt.printf("%s %s", colors.success_symbol(), colors.bold(module.name))
        if len(module.version) > 0 && module.version != "0.0.0" {
            fmt.printf(" %s", colors.dim(fmt.tprintf("v%s", module.version)))
        }
        fmt.println("")
        
        // Show description if available
        if len(module.description) > 0 {
            fmt.printf("  %s %s\n", colors.dim("Description:"), module.description)
        }
        
        // Show path
        fmt.printf("  %s %s\n", colors.dim("Path:"), module.path)
        
        // Show optional dependencies if any
        if len(module.optional) > 0 {
            optional_deps := strings.join(module.optional[:], ", ")
            fmt.printf("  %s %s\n", colors.dim("Optional:"), optional_deps)
        }
        
        fmt.println("")
    }
    
    errors.print_formatted_success("Summary", 
        fmt.tprintf("%d modules ready to load", len(resolved_modules)))
}