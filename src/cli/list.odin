package cli

import "core:fmt"
import "core:os"
import "../loader"
import "../manifest"

// list_modules implements the 'zephyr list' command
// Displays discovered modules in resolved dependency order with priorities and dependencies
list_modules :: proc() {
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
    
    // Discovery phase
    modules := loader.discover(modules_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    if len(modules) == 0 {
        fmt.eprintfln("No modules found in: %s", modules_dir)
        fmt.eprintln("")
        fmt.eprintln("To get started:")
        fmt.eprintln("  1. Use 'zephyr init <module-name>' to create your first module")
        fmt.eprintln("  2. Or check that your modules directory contains valid module.toml files")
        fmt.eprintln("  3. Use 'zephyr validate' to check for manifest errors")
        return
    }
    
    // Platform filtering phase
    current_platform := loader.get_current_platform()
    compatible_indices := loader.filter_compatible_indices(modules)
    defer delete(compatible_indices)
    
    // Dependency resolution phase
    resolved_modules, err := loader.resolve_filtered(modules, compatible_indices)
    if err != "" {
        fmt.eprintfln("Error: Dependency resolution failed")
        fmt.eprintfln("Details: %s", err)
        fmt.eprintln("")
        fmt.eprintln("Suggestions:")
        fmt.eprintln("  - Use 'zephyr validate' to check all manifests")
        fmt.eprintln("  - Check that all required dependencies are installed")
        return
    }
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    // Display header
    fmt.eprintfln("Modules directory: %s", modules_dir)
    fmt.eprintfln("Found %d module(s), %d compatible with current platform", len(modules), len(compatible_indices))
    fmt.eprintfln("Current platform: %s/%s, shell: %s %s", current_platform.os, current_platform.arch, current_platform.shell, current_platform.version)
    fmt.println("")
    
    // Show incompatible modules if any
    if len(modules) > len(compatible_indices) {
        fmt.println("Incompatible modules (skipped):")
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
                fmt.printf("  - %s", module.name)
                if len(module.version) > 0 && module.version != "0.0.0" {
                    fmt.printf(" v%s", module.version)
                }
                fmt.printf(" (")
                
                // Show platform requirements
                filter := module.platforms
                
                if len(filter.os) > 0 {
                    fmt.printf("os: ")
                    for os_name, i in filter.os {
                        if i > 0 do fmt.printf(", ")
                        fmt.printf("%s", os_name)
                    }
                }
                
                if len(filter.arch) > 0 {
                    if len(filter.os) > 0 do fmt.printf(", ")
                    fmt.printf("arch: ")
                    for arch_name, i in filter.arch {
                        if i > 0 do fmt.printf(", ")
                        fmt.printf("%s", arch_name)
                    }
                }
                
                if filter.shell != "" {
                    if len(filter.os) > 0 || len(filter.arch) > 0 do fmt.printf(", ")
                    fmt.printf("shell: %s", filter.shell)
                }
                
                if filter.min_version != "" {
                    if len(filter.os) > 0 || len(filter.arch) > 0 || filter.shell != "" do fmt.printf(", ")
                    fmt.printf("min_version: %s", filter.min_version)
                }
                
                fmt.println(")")
            }
        }
        fmt.println("")
    }
    
    if len(compatible_indices) == 0 {
        fmt.println("No modules are compatible with the current platform.")
        return
    }
    
    fmt.println("Compatible modules (load order):")
    fmt.println("")
    
    // Display modules in resolved order
    for module, idx in resolved_modules {
        fmt.printf("  %d. %s", idx+1, module.name)
        
        // Add version if available
        if len(module.version) > 0 && module.version != "0.0.0" {
            fmt.printf(" v%s", module.version)
        }
        
        // Add priority information
        fmt.printf(" [priority: %d]", module.priority)
        
        fmt.println("")
        
        // Show description if available
        if len(module.description) > 0 {
            fmt.printf("     %s\n", module.description)
        }
        
        // Show dependencies
        if len(module.required) > 0 {
            fmt.printf("     └─ requires: ")
            for dep, dep_idx in module.required {
                if dep_idx > 0 {
                    fmt.printf(", ")
                }
                fmt.printf("%s", dep)
            }
            fmt.println("")
        }
        
        if len(module.optional) > 0 {
            fmt.printf("     └─ optional: ")
            for dep, dep_idx in module.optional {
                if dep_idx > 0 {
                    fmt.printf(", ")
                }
                fmt.printf("%s", dep)
            }
            fmt.println("")
        }
        
        // Show module path
        fmt.printf("     └─ path: %s\n", module.path)
        
        fmt.println("")
    }
    
    fmt.eprintfln("Total: %d modules will be loaded in this order", len(resolved_modules))
}