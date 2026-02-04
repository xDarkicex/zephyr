package main

import "core:fmt"
import "core:os"
import "loader"

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
    fmt.eprintln("Error: 'list' command not yet implemented")
    os.exit(1)
}

run_validate :: proc() {
    fmt.eprintln("Error: 'validate' command not yet implemented")
    os.exit(1)
}

run_init :: proc() {
    fmt.eprintln("Error: 'init' command not yet implemented")
    os.exit(1)
}