package main

import "core:fmt"
import "core:os"
import "loader"
import "cli"

main :: proc() {
    // Command routing logic
    if len(os.args) < 2 {
        // Default behavior: run load command
        run_load()
        return
    }
    
    command := os.args[1]
    
    switch command {
    case "load":
        run_load()
    case "list":
        run_list()
    case "validate":
        run_validate()
    case "init":
        run_init()
    case "help", "--help", "-h":
        print_usage()
    case:
        fmt.eprintfln("Error: Unknown command '%s'", command)
        print_usage()
        os.exit(1)
    }
}

// Placeholder functions for CLI commands - will be implemented in Phase 2
run_list :: proc() {
    cli.list_modules()
}

run_validate :: proc() {
    cli.validate_manifests()
}

run_init :: proc() {
    if len(os.args) < 3 {
        fmt.eprintln("Error: Module name required")
        fmt.eprintln("Usage: zephyr init <module-name>")
        fmt.eprintln("")
        fmt.eprintln("Example: zephyr init my-shell-module")
        os.exit(1)
    }
    
    fmt.eprintln("Error: 'init' command not yet implemented")
    os.exit(1)
}

// run_load implements the default load behavior
run_load :: proc() {
    // Get modules directory with error handling
    modules_dir := get_modules_directory()
    
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
    
    // Discovery phase with detailed error handling
    modules := loader.discover(modules_dir)
    if len(modules) == 0 {
        fmt.eprintfln("No modules found in: %s", modules_dir)
        fmt.eprintln("")
        fmt.eprintln("To get started:")
        fmt.eprintln("  1. Use 'zephyr init <module-name>' to create your first module")
        fmt.eprintln("  2. Or check that your modules directory contains valid module.toml files")
        fmt.eprintln("  3. Use 'zephyr validate' to check for manifest errors")
        os.exit(1)
    }
    defer delete(modules)
    
    // Dependency resolution phase with detailed error handling
    resolved_modules, err := loader.resolve(modules)
    if err != "" {
        fmt.eprintfln("Error: Dependency resolution failed")
        fmt.eprintfln("Details: %s", err)
        fmt.eprintln("")
        fmt.eprintln("Suggestions:")
        fmt.eprintln("  - Use 'zephyr validate' to check all manifests")
        fmt.eprintln("  - Use 'zephyr list' to see module dependencies")
        fmt.eprintln("  - Check that all required dependencies are installed")
        os.exit(1)
    }
    defer delete(resolved_modules)
    
    // Shell code emission phase
    // Note: emit() writes to stdout, so any errors would be from I/O
    // The loader.emit() function handles its own error cases internally
    loader.emit(resolved_modules)
}

// get_modules_directory resolves the modules directory path
// Uses ZSH_MODULES_DIR environment variable if set, otherwise defaults to $HOME/.zsh/modules
get_modules_directory :: proc() -> string {
    // Check for ZSH_MODULES_DIR environment variable first
    modules_dir := os.get_env("ZSH_MODULES_DIR")
    if modules_dir != "" {
        return modules_dir
    }
    
    // Default to $HOME/.zsh/modules
    home := os.get_env("HOME")
    if home == "" {
        // Fallback if HOME is not set (shouldn't happen on Unix systems)
        fmt.eprintln("Warning: HOME environment variable not set, using current directory")
        return ".zsh/modules"
    }
    
    // Use the loader package's get_modules_dir function for consistency
    return loader.get_modules_dir()
}

// print_usage displays help information for the CLI
print_usage :: proc() {
    fmt.println("Zephyr Shell Loader - Modular shell configuration management")
    fmt.println("")
    fmt.println("USAGE:")
    fmt.println("    zephyr [COMMAND]")
    fmt.println("")
    fmt.println("COMMANDS:")
    fmt.println("    load        Generate shell code for loading modules (default)")
    fmt.println("    list        List discovered modules and their load order")
    fmt.println("    validate    Validate all module manifests for errors")
    fmt.println("    init        Create a new module skeleton")
    fmt.println("    help        Show this help message")
    fmt.println("")
    fmt.println("EXAMPLES:")
    fmt.println("    zephyr                    # Load modules (same as 'zephyr load')")
    fmt.println("    zephyr load               # Generate shell code for sourcing")
    fmt.println("    zephyr list               # Show modules and dependencies")
    fmt.println("    zephyr validate           # Check manifests for errors")
    fmt.println("    zephyr init my-module     # Create new module 'my-module'")
    fmt.println("")
    fmt.println("ENVIRONMENT:")
    fmt.println("    ZSH_MODULES_DIR    Directory containing modules (default: ~/.zsh/modules)")
    fmt.println("")
    fmt.println("INTEGRATION:")
    fmt.println("    Add this to your .zshrc to load modules automatically:")
    fmt.println("    eval \"$(zephyr load)\"")
    fmt.println("")
    fmt.println("For more information, visit: https://github.com/xDarkicex/zephyr")
}