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
    if len(modules) == 0 {
        fmt.eprintfln("No modules found in: %s", modules_dir)
        fmt.eprintln("")
        fmt.eprintln("To get started:")
        fmt.eprintln("  1. Use 'zephyr init <module-name>' to create your first module")
        fmt.eprintln("  2. Or check that your modules directory contains valid module.toml files")
        fmt.eprintln("  3. Use 'zephyr validate' to check for manifest errors")
        return
    }
    defer delete(modules)
    
    // Dependency resolution phase
    resolved_modules, err := loader.resolve(modules)
    if err != "" {
        fmt.eprintfln("Error: Dependency resolution failed")
        fmt.eprintfln("Details: %s", err)
        fmt.eprintln("")
        fmt.eprintln("Suggestions:")
        fmt.eprintln("  - Use 'zephyr validate' to check all manifests")
        fmt.eprintln("  - Check that all required dependencies are installed")
        return
    }
    defer delete(resolved_modules)
    
    // Display header
    fmt.eprintfln("Modules directory: %s", modules_dir)
    fmt.eprintfln("Found %d module(s)", len(modules))
    fmt.println("")
    fmt.println("Resolved load order:")
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