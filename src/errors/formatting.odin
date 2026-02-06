package errors

import "core:fmt"
import "core:strings"
import "../colors"

// ErrorContext provides additional context for error messages
ErrorContext :: struct {
    file_path:    string,
    line_number:  int,
    column:       int,
    operation:    string,
    module_name:  string,
    suggestion:   string,
}

// format_error creates a well-formatted error message with context
format_error :: proc(title: string, message: string, ctx: ErrorContext = {}) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Error header with symbol
    fmt.sbprintf(&builder, "%s %s\n", colors.error_symbol(), colors.error(title))
    
    // Main error message
    if message != "" {
        fmt.sbprintf(&builder, "  %s\n", message)
    }
    
    // Add context information if available
    if ctx.file_path != "" {
        fmt.sbprintf(&builder, "  %s %s", colors.dim("File:"), ctx.file_path)
        
        if ctx.line_number > 0 {
            fmt.sbprintf(&builder, ":%d", ctx.line_number)
            
            if ctx.column > 0 {
                fmt.sbprintf(&builder, ":%d", ctx.column)
            }
        }
        fmt.sbprintf(&builder, "\n")
    }
    
    if ctx.operation != "" {
        fmt.sbprintf(&builder, "  %s %s\n", colors.dim("Operation:"), ctx.operation)
    }
    
    if ctx.module_name != "" {
        fmt.sbprintf(&builder, "  %s %s\n", colors.dim("Module:"), ctx.module_name)
    }

    if ctx.suggestion != "" {
        fmt.sbprintf(&builder, "  %s %s\n", colors.dim("Suggested fix:"), ctx.suggestion)
    }
    
    return strings.clone(strings.to_string(builder))
}

// format_warning creates a well-formatted warning message
format_warning :: proc(title: string, message: string, ctx: ErrorContext = {}) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Warning header with symbol
    fmt.sbprintf(&builder, "%s %s\n", colors.warning_symbol(), colors.warning(title))
    
    // Main warning message
    if message != "" {
        fmt.sbprintf(&builder, "  %s\n", message)
    }
    
    // Add context information if available
    if ctx.file_path != "" {
        fmt.sbprintf(&builder, "  %s %s", colors.dim("File:"), ctx.file_path)
        
        if ctx.line_number > 0 {
            fmt.sbprintf(&builder, ":%d", ctx.line_number)
            
            if ctx.column > 0 {
                fmt.sbprintf(&builder, ":%d", ctx.column)
            }
        }
        fmt.sbprintf(&builder, "\n")
    }
    
    if ctx.module_name != "" {
        fmt.sbprintf(&builder, "  %s %s\n", colors.dim("Module:"), ctx.module_name)
    }
    
    return strings.clone(strings.to_string(builder))
}

// format_success creates a well-formatted success message
format_success :: proc(title: string, message: string = "") -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Success header with symbol
    fmt.sbprintf(&builder, "%s %s", colors.success_symbol(), colors.success(title))
    
    // Main success message
    if message != "" {
        fmt.sbprintf(&builder, "\n  %s", message)
    }
    
    return strings.clone(strings.to_string(builder))
}

// format_info creates a well-formatted info message
format_info :: proc(title: string, message: string = "") -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Info header with symbol
    fmt.sbprintf(&builder, "%s %s", colors.info_symbol(), colors.info(title))
    
    // Main info message
    if message != "" {
        fmt.sbprintf(&builder, "\n  %s", message)
    }
    
    return strings.clone(strings.to_string(builder))
}

// format_validation_error creates a formatted validation error for manifests
format_validation_error :: proc(file_path: string, error_message: string, line_number: int = 0) -> string {
    ctx := ErrorContext{
        file_path = file_path,
        line_number = line_number,
        operation = "Manifest validation",
    }
    
    return format_error("Invalid manifest", error_message, ctx)
}

// format_dependency_error creates a formatted dependency resolution error
format_dependency_error :: proc(module_name: string, dependency: string, error_type: string) -> string {
    ctx := ErrorContext{
        module_name = module_name,
        operation = "Dependency resolution",
    }
    
    message := ""
    switch error_type {
    case "missing":
        message = fmt.tprintf("Required dependency '%s' not found", dependency)
    case "circular":
        message = fmt.tprintf("Circular dependency detected involving '%s'", dependency)
    case "version":
        message = fmt.tprintf("Version conflict with dependency '%s'", dependency)
    case:
        message = fmt.tprintf("Dependency error with '%s': %s", dependency, error_type)
    }

    formatted := format_error("Dependency Error", message, ctx)
    if message != "" {
        delete(message)
    }
    return formatted
}

// format_file_error creates a formatted file operation error
format_file_error :: proc(operation: string, file_path: string, system_error: string) -> string {
    ctx := ErrorContext{
        file_path = file_path,
        operation = operation,
    }
    
    message := fmt.tprintf("System error: %s", system_error)
    title := fmt.tprintf("File %s failed", operation)

    formatted := format_error(title, message, ctx)
    if message != "" {
        delete(message)
    }
    if title != "" {
        delete(title)
    }
    return formatted
}

// format_platform_error creates a formatted platform compatibility error
format_platform_error :: proc(module_name: string, current_platform: string, required_platforms: []string) -> string {
    ctx := ErrorContext{
        module_name = module_name,
        operation = "Platform compatibility check",
    }
    
    message := fmt.tprintf("Current platform '%s' not supported. Required: %v",
        current_platform, required_platforms)

    formatted := format_error("Platform Incompatible", message, ctx)
    if message != "" {
        delete(message)
    }
    return formatted
}

// format_summary creates a formatted summary section
format_summary :: proc(title: string, items: []string, success_count: int = 0, error_count: int = 0) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Summary header
    fmt.sbprintf(&builder, "%s\n", colors.bold(title))
    for _ in 0..<len(title) {
        fmt.sbprintf(&builder, "=")
    }
    fmt.sbprintf(&builder, "\n")
    
    // Summary statistics if provided
    if success_count > 0 || error_count > 0 {
        total := success_count + error_count
        fmt.sbprintf(&builder, "Total: %d", total)
        
        if success_count > 0 {
            fmt.sbprintf(&builder, " | %s %d", colors.success("Success:"), success_count)
        }
        
        if error_count > 0 {
            fmt.sbprintf(&builder, " | %s %d", colors.error("Errors:"), error_count)
        }
        
        fmt.sbprintf(&builder, "\n\n")
    }
    
    // List items
    for item in items {
        fmt.sbprintf(&builder, "  %s\n", item)
    }
    
    return strings.clone(strings.to_string(builder))
}

// format_progress creates a formatted progress indicator
format_progress :: proc(current: int, total: int, operation: string) -> string {
    percentage := (current * 100) / total
    progress_bar := create_progress_bar(percentage, 20)

    formatted := fmt.tprintf("%s [%s] %d/%d (%d%%)",
        operation, progress_bar, current, total, percentage)
    if progress_bar != "" {
        delete(progress_bar)
    }
    return formatted
}

// create_progress_bar creates a visual progress bar
create_progress_bar :: proc(percentage: int, width: int) -> string {
    filled := (percentage * width) / 100
    empty := width - filled
    
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Filled portion
    for i in 0..<filled {
        fmt.sbprintf(&builder, "█")
    }
    
    // Empty portion
    for i in 0..<empty {
        fmt.sbprintf(&builder, "░")
    }
    
    return strings.to_string(builder)
}

// format_code_block creates a formatted code block with syntax highlighting
format_code_block :: proc(code: string, language: string = "", line_numbers: bool = false) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    lines := strings.split_lines(code)
    defer delete(lines)
    
    // Header
    if language != "" {
        fmt.sbprintf(&builder, "%s\n", colors.dim(fmt.tprintf("--- %s ---", language)))
    }
    
    // Code lines
    for line, i in lines {
        if line_numbers {
            line_num := colors.dim(fmt.tprintf("%3d: ", i + 1))
            fmt.sbprintf(&builder, "%s%s\n", line_num, line)
        } else {
            fmt.sbprintf(&builder, "%s\n", line)
        }
    }
    
    // Footer
    if language != "" {
        fmt.sbprintf(&builder, "%s\n", colors.dim(strings.repeat("-", len(language) + 8)))
    }
    
    return strings.to_string(builder)
}

// format_table creates a formatted table with headers and rows
format_table :: proc(headers: []string, rows: [][]string, max_width: int = 80) -> string {
    if len(headers) == 0 || len(rows) == 0 {
        return ""
    }
    
    // Calculate column widths
    col_widths := make([]int, len(headers))
    defer delete(col_widths)
    
    // Initialize with header widths
    for header, i in headers {
        col_widths[i] = len(header)
    }
    
    // Update with row data widths
    for row in rows {
        for cell, i in row {
            if i < len(col_widths) && len(cell) > col_widths[i] {
                col_widths[i] = len(cell)
            }
        }
    }
    
    // Adjust for max width
    total_width := 0
    for width in col_widths {
        total_width += width + 3 // +3 for " | "
    }
    
    if total_width > max_width {
        // Proportionally reduce column widths
        reduction := total_width - max_width
        for &width in col_widths {
            width = max(width - (reduction / len(col_widths)), 8) // Minimum 8 chars
        }
    }
    
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    
    // Header row
    for header, i in headers {
        if i > 0 do fmt.sbprintf(&builder, " | ")
        fmt.sbprintf(&builder, "%-*s", col_widths[i], header)
    }
    fmt.sbprintf(&builder, "\n")
    
    // Separator
    for width, i in col_widths {
        if i > 0 do fmt.sbprintf(&builder, "-+-")
        fmt.sbprintf(&builder, "%s", strings.repeat("-", width))
    }
    fmt.sbprintf(&builder, "\n")
    
    // Data rows
    for row in rows {
        for cell, i in row {
            if i > 0 do fmt.sbprintf(&builder, " | ")
            if i < len(col_widths) {
                truncated := cell
                if len(cell) > col_widths[i] {
                    truncated = fmt.tprintf("%s...", cell[:col_widths[i]-3])
                }
                fmt.sbprintf(&builder, "%-*s", col_widths[i], truncated)
            }
        }
        fmt.sbprintf(&builder, "\n")
    }
    
    return strings.to_string(builder)
}

// print_formatted_error prints a formatted error message
print_formatted_error :: proc(title: string, message: string, ctx: ErrorContext = {}) {
    formatted := format_error(title, message, ctx)
    fmt.eprint(formatted)
}

// print_formatted_warning prints a formatted warning message
print_formatted_warning :: proc(title: string, message: string, ctx: ErrorContext = {}) {
    formatted := format_warning(title, message, ctx)
    fmt.eprint(formatted)
}

// print_formatted_success prints a formatted success message
print_formatted_success :: proc(title: string, message: string = "") {
    formatted := format_success(title, message)
    fmt.print(formatted)
}

// print_formatted_info prints a formatted info message
print_formatted_info :: proc(title: string, message: string = "") {
    formatted := format_info(title, message)
    fmt.print(formatted)
}
