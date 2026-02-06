package debug

import "core:fmt"
import "core:os"
import "core:time"
import "../colors"

// Debug levels
DebugLevel :: enum {
    Silent,  // No debug output
    Error,   // Only errors
    Warn,    // Errors and warnings
    Info,    // Errors, warnings, and info
    Debug,   // All output including debug details
    Trace,   // Maximum verbosity with trace information
}

// Global debug configuration
debug_config := struct {
    level:           DebugLevel,
    show_timestamps: bool,
    show_location:   bool,
    enabled:         bool,
} {
    level = .Error,
    show_timestamps = false,
    show_location = false,
    enabled = false,
}

// init_debug initializes debug configuration from environment variables
init_debug :: proc() {
    // Check for debug environment variables
    debug_env := os.get_env("ZEPHYR_DEBUG")
    verbose_env := os.get_env("ZEPHYR_VERBOSE")
    
    if debug_env != "" {
        debug_config.enabled = true
        switch debug_env {
        case "0", "false", "off":
            debug_config.level = .Silent
        case "1", "true", "on":
            debug_config.level = .Info
        case "2", "debug":
            debug_config.level = .Debug
        case "3", "trace":
            debug_config.level = .Trace
        case:
            debug_config.level = .Info
        }
    }
    
    if verbose_env != "" {
        debug_config.enabled = true
        switch verbose_env {
        case "0", "false", "off":
            debug_config.level = .Error
        case "1", "true", "on":
            debug_config.level = .Info
        case "2":
            debug_config.level = .Debug
        case "3":
            debug_config.level = .Trace
        case:
            debug_config.level = .Info
        }
    }
    delete(debug_env)
    delete(verbose_env)
    
    // Check for timestamp option
    timestamps_env := os.get_env("ZEPHYR_DEBUG_TIMESTAMPS")
    if timestamps_env != "" {
        debug_config.show_timestamps = true
    }
    delete(timestamps_env)
    
    // Check for location option
    location_env := os.get_env("ZEPHYR_DEBUG_LOCATION")
    if location_env != "" {
        debug_config.show_location = true
    }
    delete(location_env)
}

// set_debug_level sets the debug level programmatically
set_debug_level :: proc(level: DebugLevel) {
    debug_config.level = level
    debug_config.enabled = level != .Silent
}

// enable_debug enables debug output
enable_debug :: proc() {
    debug_config.enabled = true
    if debug_config.level == .Silent {
        debug_config.level = .Info
    }
}

// disable_debug disables debug output
disable_debug :: proc() {
    debug_config.enabled = false
}

// is_debug_enabled checks if debug output is enabled
is_debug_enabled :: proc() -> bool {
    return debug_config.enabled
}

// get_debug_level returns the current debug level
get_debug_level :: proc() -> DebugLevel {
    return debug_config.level
}

// format_prefix creates a debug message prefix with optional timestamp and location
format_prefix :: proc(level: string, location: string = "") -> string {
    prefix := ""
    
    if debug_config.show_timestamps {
        now := time.now()
        timestamp := time.time_to_unix(now)
        prefix = fmt.tprintf("[%d] ", timestamp)
    }
    
    prefix = fmt.tprintf("%s[%s]", prefix, level)
    
    if debug_config.show_location && location != "" {
        prefix = fmt.tprintf("%s (%s)", prefix, location)
    }
    
    return fmt.tprintf("%s ", prefix)
}

// Debug output functions
debug_error :: proc(format: string, args: ..any) {
    if !debug_config.enabled || debug_config.level < .Error {
        return
    }
    
    prefix := format_prefix("ERROR")
    message := fmt.tprintf(format, ..args)
    fmt.eprintf("%s%s\n", colors.error(prefix), message)
}

debug_warn :: proc(format: string, args: ..any) {
    if !debug_config.enabled || debug_config.level < .Warn {
        return
    }
    
    prefix := format_prefix("WARN")
    message := fmt.tprintf(format, ..args)
    fmt.eprintf("%s%s\n", colors.warning(prefix), message)
}

debug_info :: proc(format: string, args: ..any) {
    if !debug_config.enabled || debug_config.level < .Info {
        return
    }
    
    prefix := format_prefix("INFO")
    message := fmt.tprintf(format, ..args)
    fmt.eprintf("%s%s\n", colors.info(prefix), message)
}

debug_debug :: proc(format: string, args: ..any) {
    if !debug_config.enabled || debug_config.level < .Debug {
        return
    }
    
    prefix := format_prefix("DEBUG")
    message := fmt.tprintf(format, ..args)
    fmt.eprintf("%s%s\n", colors.dim(prefix), message)
}

debug_trace :: proc(format: string, args: ..any) {
    if !debug_config.enabled || debug_config.level < .Trace {
        return
    }
    
    prefix := format_prefix("TRACE")
    message := fmt.tprintf(format, ..args)
    fmt.eprintf("%s%s\n", colors.dim(prefix), message)
}

// Convenience functions for common debug scenarios
debug_enter :: proc(function_name: string) {
    debug_trace("Entering %s", function_name)
}

debug_exit :: proc(function_name: string) {
    debug_trace("Exiting %s", function_name)
}

debug_timing :: proc(operation: string, duration: time.Duration) {
    debug_debug("Operation '%s' took %v", operation, duration)
}

debug_memory :: proc(operation: string, bytes: int) {
    debug_debug("Memory operation '%s': %d bytes", operation, bytes)
}

// File operation debugging
debug_file_read :: proc(path: string, size: int) {
    debug_debug("Reading file: %s (%d bytes)", path, size)
}

debug_file_write :: proc(path: string, size: int) {
    debug_debug("Writing file: %s (%d bytes)", path, size)
}

debug_directory_scan :: proc(path: string, count: int) {
    debug_debug("Scanned directory: %s (found %d entries)", path, count)
}

// Module operation debugging
debug_module_discovered :: proc(name: string, path: string) {
    debug_info("Discovered module: %s at %s", name, path)
}

debug_module_parsed :: proc(name: string, version: string) {
    debug_info("Parsed module: %s v%s", name, version)
}

debug_module_filtered :: proc(name: string, reason: string) {
    debug_info("Filtered module: %s (reason: %s)", name, reason)
}

debug_dependency_resolved :: proc(name: string, dependencies: []string) {
    debug_info("Resolved dependencies for %s: %v", name, dependencies)
}

// Command line argument debugging
debug_args :: proc(args: []string) {
    debug_debug("Command line arguments: %v", args)
}

debug_env_var :: proc(name: string, value: string) {
    if value != "" {
        debug_debug("Environment variable %s = %s", name, value)
    } else {
        debug_debug("Environment variable %s is not set", name)
    }
}

// Error context debugging
debug_error_context :: proc(operation: string, error: string, ctx: map[string]string) {
    debug_error("Error in %s: %s", operation, error)
    for key, value in ctx {
        debug_debug("  %s: %s", key, value)
    }
}

// Performance debugging
debug_performance_start :: proc(operation: string) -> time.Time {
    start_time := time.now()
    debug_trace("Starting performance measurement for: %s", operation)
    return start_time
}

debug_performance_end :: proc(operation: string, start_time: time.Time) {
    duration := time.since(start_time)
    debug_timing(operation, duration)
}

// Print debug configuration
print_debug_config :: proc() {
    if !debug_config.enabled {
        fmt.eprintln("Debug output is disabled")
        return
    }
    
    fmt.eprintfln("Debug configuration:")
    fmt.eprintfln("  Level: %v", debug_config.level)
    fmt.eprintfln("  Timestamps: %v", debug_config.show_timestamps)
    fmt.eprintfln("  Location: %v", debug_config.show_location)
    fmt.eprintfln("  Enabled: %v", debug_config.enabled)
}
