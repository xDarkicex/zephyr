#+feature dynamic-literals
package colors

import "core:fmt"
import "core:os"

// ANSI color codes for terminal output
Color :: enum {
    Reset,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    Bold,
    Dim,
}

// color_codes maps Color enum to ANSI escape sequences
color_codes := map[Color]string{
    .Reset   = "\033[0m",
    .Red     = "\033[31m",
    .Green   = "\033[32m",
    .Yellow  = "\033[33m",
    .Blue    = "\033[34m",
    .Magenta = "\033[35m",
    .Cyan    = "\033[36m",
    .White   = "\033[37m",
    .Bold    = "\033[1m",
    .Dim     = "\033[2m",
}

// Global flag to control colored output
colored_output_enabled := true

// init_colors initializes the colors module and detects terminal capabilities
init_colors :: proc() {
    // Check if we're in a terminal that supports colors
    // For now, we'll assume colors are supported unless NO_COLOR is set
    
    no_color := os.get_env("NO_COLOR")
    if no_color != "" {
        colored_output_enabled = false
    }
    
    // Also check TERM environment variable
    term := os.get_env("TERM")
    if term == "dumb" || term == "" {
        colored_output_enabled = false
    }
}

// colorize wraps text with the specified color
colorize :: proc(text: string, color: Color) -> string {
    if !colored_output_enabled {
        return text
    }
    
    color_code := color_codes[color]
    reset_code := color_codes[.Reset]
    return fmt.tprintf("%s%s%s", color_code, text, reset_code)
}

// Error formatting functions
error :: proc(text: string) -> string {
    return colorize(text, .Red)
}

warning :: proc(text: string) -> string {
    return colorize(text, .Yellow)
}

success :: proc(text: string) -> string {
    return colorize(text, .Green)
}

info :: proc(text: string) -> string {
    return colorize(text, .Blue)
}

bold :: proc(text: string) -> string {
    return colorize(text, .Bold)
}

dim :: proc(text: string) -> string {
    return colorize(text, .Dim)
}

// Formatted print functions with colors
print_error :: proc(format: string, args: ..any) {
    colored_text := error(fmt.tprintf(format, ..args))
    fmt.println(colored_text)
}

print_warning :: proc(format: string, args: ..any) {
    colored_text := warning(fmt.tprintf(format, ..args))
    fmt.println(colored_text)
}

print_success :: proc(format: string, args: ..any) {
    colored_text := success(fmt.tprintf(format, ..args))
    fmt.println(colored_text)
}

print_info :: proc(format: string, args: ..any) {
    colored_text := info(fmt.tprintf(format, ..args))
    fmt.println(colored_text)
}

// Error symbols with colors
error_symbol :: proc() -> string {
    return error("✗")
}

warning_symbol :: proc() -> string {
    return warning("⚠")
}

success_symbol :: proc() -> string {
    return success("✓")
}

info_symbol :: proc() -> string {
    return info("ℹ")
}

// Disable colors (useful for testing or when piping output)
disable_colors :: proc() {
    colored_output_enabled = false
}

// Enable colors
enable_colors :: proc() {
    colored_output_enabled = true
}

// Check if colors are enabled
colors_enabled :: proc() -> bool {
    return colored_output_enabled
}