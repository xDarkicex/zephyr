package cli

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "../loader"
import "../colors"
import "../errors"

// init_module implements the 'zephyr init <module-name>' command
// Creates a new module skeleton with directory structure and template files
init_module :: proc(module_name: string) {
    // Validate module name
    if !is_valid_module_name(module_name) {
        colors.print_error("Invalid module name '%s'", module_name)
        fmt.eprintln("")
        errors.suggest_for_module_name_error(module_name)
        os.exit(1)
    }
    
    // Get modules directory
    modules_dir := loader.get_modules_dir()
    defer delete(modules_dir)
    
    // Create the module directory path
    module_dir := filepath.join({modules_dir, module_name})
    
    // Check if module already exists
    if os.exists(module_dir) {
        colors.print_error("Module '%s' already exists at: %s", module_name, module_dir)
        fmt.eprintln("")
        errors.suggest_for_module_exists_error(module_name)
        os.exit(1)
    }
    
    colors.print_info("Creating new module: %s", module_name)
    fmt.eprintfln("Location: %s", module_dir)
    fmt.println("")
    
    // Create directory structure
    create_module_directory(module_dir, module_name)
    
    // Create template files
    create_template_files(module_dir, module_name)
    
    // Provide usage instructions
    provide_usage_instructions(module_name, module_dir)
}

// is_valid_module_name validates that a module name follows naming conventions
is_valid_module_name :: proc(name: string) -> bool {
    if len(name) == 0 || len(name) > 50 {
        return false
    }
    
    // Must start with a letter
    if !is_letter(rune(name[0])) {
        return false
    }
    
    // Can only contain letters, numbers, hyphens, and underscores
    for char in name {
        r := rune(char)
        if !is_letter(r) && !is_digit(r) && r != '-' && r != '_' {
            return false
        }
    }
    
    return true
}

// is_letter checks if a rune is a letter (a-z, A-Z)
is_letter :: proc(r: rune) -> bool {
    return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}

// is_digit checks if a rune is a digit (0-9)
is_digit :: proc(r: rune) -> bool {
    return r >= '0' && r <= '9'
}

// replace_chars replaces all occurrences of old_char with new_char in a string
replace_chars :: proc(s: string, old_char: rune, new_char: rune) -> string {
    result := make([]u8, len(s))
    for i in 0..<len(s) {
        if rune(s[i]) == old_char {
            result[i] = u8(new_char)
        } else {
            result[i] = s[i]
        }
    }
    return string(result)
}

// to_title_case converts the first character to uppercase
to_title_case :: proc(s: string) -> string {
    if len(s) == 0 {
        return s
    }
    result := make([]u8, len(s))
    copy(result, s)
    if result[0] >= 'a' && result[0] <= 'z' {
        result[0] = result[0] - 'a' + 'A'
    }
    return string(result)
}

// create_module_directory creates the directory structure for a new module
create_module_directory :: proc(module_dir: string, module_name: string) {
    // Ensure the parent modules directory exists
    modules_dir := filepath.dir(module_dir)
    if !os.exists(modules_dir) {
        colors.print_info("Creating modules directory: %s", modules_dir)
        err := os.make_directory(modules_dir, 0o755)
        if err != os.ERROR_NONE {
            colors.print_error("Failed to create modules directory: %s", modules_dir)
            colors.print_error("System error: %v", err)
            fmt.eprintln("")
            errors.suggest_for_file_creation_error(modules_dir)
            os.exit(1)
        }
    }
    
    // Create the module directory
    colors.print_info("Creating module directory: %s", module_dir)
    err := os.make_directory(module_dir, 0o755)
    if err != os.ERROR_NONE {
        colors.print_error("Failed to create module directory: %s", module_dir)
        colors.print_error("System error: %v", err)
        fmt.eprintln("")
        errors.suggest_for_file_creation_error(module_dir)
        os.exit(1)
    }
    
    // Create subdirectories for organized module structure
    subdirs := []string{
        "functions",  // For shell functions
        "aliases",    // For shell aliases
        "completions", // For shell completions
    }
    
    for subdir in subdirs {
        subdir_path := filepath.join({module_dir, subdir})
        colors.print_info("Creating subdirectory: %s", subdir)
        err := os.make_directory(subdir_path, 0o755)
        if err != os.ERROR_NONE {
            colors.print_warning("Failed to create subdirectory: %s", subdir_path)
            colors.print_warning("System error: %v", err)
            // Continue with other directories instead of exiting
        }
    }
}
// create_template_files creates the template files for a new module
create_template_files :: proc(module_dir: string, module_name: string) {
    // Create module.toml manifest
    create_module_manifest(module_dir, module_name)
    
    // Create placeholder shell files
    create_placeholder_shell_files(module_dir, module_name)
}

// create_module_manifest creates a template module.toml with sensible defaults
create_module_manifest :: proc(module_dir: string, module_name: string) {
    manifest_path := filepath.join({module_dir, "module.toml"})
    
    // Generate template TOML content
    template_content := fmt.tprintf(`# Zephyr Module Manifest
# Generated by: zephyr init %s

[module]
name = "%s"
version = "1.0.0"
description = "A shell module for %s functionality"
author = "Your Name <your.email@example.com>"
license = "MIT"

# Dependencies (uncomment and modify as needed)
[dependencies]
# required = ["core"]
# optional = ["git-helpers", "fzf-integration"]

# Platform compatibility (uncomment and modify as needed)
# [platforms]
# os = ["linux", "darwin"]
# arch = ["x86_64", "arm64"]
# shell = "zsh"
# min_version = "5.8"

# Load configuration
[load]
priority = 50
files = ["init.zsh"]

# Hooks (uncomment and modify as needed)
# [hooks]
# pre_load = "check_prerequisites"
# post_load = "setup_completion"

# Module settings (uncomment and modify as needed)
# [settings]
# debug = "false"
# auto_update = "true"
`, module_name, module_name, module_name)
    
    // Write the manifest file
    colors.print_info("Creating module manifest: module.toml")
    success := os.write_entire_file(manifest_path, transmute([]u8)template_content)
    if !success {
        colors.print_error("Failed to create module manifest: %s", manifest_path)
        fmt.eprintln("")
        errors.suggest_for_file_creation_error(manifest_path)
        os.exit(1)
    }
}
// create_placeholder_shell_files creates template shell files for the module
create_placeholder_shell_files :: proc(module_dir: string, module_name: string) {
    // Create main init.zsh file
    create_init_file(module_dir, module_name)
    
    // Create example files in subdirectories
    create_example_function_file(module_dir, module_name)
    create_example_alias_file(module_dir, module_name)
    create_readme_file(module_dir, module_name)
}

// create_init_file creates the main init.zsh file
create_init_file :: proc(module_dir: string, module_name: string) {
    init_path := filepath.join({module_dir, "init.zsh"})
    
    init_content := fmt.tprintf(`#!/usr/bin/env zsh
# %s module initialization
# Generated by: zephyr init %s

# Module: %s
# Description: A shell module for %s functionality
# Version: 1.0.0

# Source all function files
for func_file in "$${0:A:h}"/functions/*.zsh(N); do
    source "$func_file"
done

# Source all alias files  
for alias_file in "$${0:A:h}"/aliases/*.zsh(N); do
    source "$alias_file"
done

# Source all completion files
for comp_file in "$${0:A:h}"/completions/*.zsh(N); do
    source "$comp_file"
done

# Module-specific initialization code goes here
# Example:
# export %s_VERSION="1.0.0"
# export %s_DEBUG="${{ZSH_MODULE_%s_DEBUG:-false}}"

# Uncomment to add a simple greeting
# echo "✓ %s module loaded"
`, strings.to_upper(module_name), module_name, module_name, module_name, 
   strings.to_upper(module_name), strings.to_upper(module_name), 
   strings.to_upper(module_name), module_name)
    
    colors.print_info("Creating main script: init.zsh")
    success := os.write_entire_file(init_path, transmute([]u8)init_content)
    if !success {
        colors.print_error("Failed to create init.zsh: %s", init_path)
        fmt.eprintln("")
        errors.suggest_for_file_creation_error(init_path)
        os.exit(1)
    }
}

// create_example_function_file creates an example function file
create_example_function_file :: proc(module_dir: string, module_name: string) {
    functions_dir := filepath.join({module_dir, "functions"})
    func_file := filepath.join({functions_dir, "example.zsh"})
    
    func_content := fmt.tprintf(`#!/usr/bin/env zsh
# Example functions for %s module

# Example function - replace with your own
%s_hello() {
    echo "Hello from %s module!"
    echo "This is an example function."
    echo "Replace this with your own functionality."
}

# Another example function with parameters
%s_info() {
    local message="${{1:-No message provided}}"
    echo "[%s] $message"
}

# Example function that uses module settings
%s_debug() {
    if [[ "${{ZSH_MODULE_%s_DEBUG:-false}}" == "true" ]]; then
        echo "[DEBUG:%s] $*" >&2
    fi
}
`, module_name, replace_chars(module_name, '-', '_'), module_name,
   replace_chars(module_name, '-', '_'), strings.to_upper(module_name),
   replace_chars(module_name, '-', '_'), strings.to_upper(module_name),
   strings.to_upper(module_name))
    
    colors.print_info("Creating example functions: functions/example.zsh")
    success := os.write_entire_file(func_file, transmute([]u8)func_content)
    if !success {
        colors.print_warning("Failed to create functions/example.zsh: %s", func_file)
    }
}

// create_example_alias_file creates an example alias file
create_example_alias_file :: proc(module_dir: string, module_name: string) {
    aliases_dir := filepath.join({module_dir, "aliases"})
    alias_file := filepath.join({aliases_dir, "example.zsh"})
    
    alias_content := fmt.tprintf(`#!/usr/bin/env zsh
# Example aliases for %s module

# Example aliases - replace with your own
alias %s-hello='%s_hello'
alias %s-info='%s_info'

# Example conditional alias
if command -v git >/dev/null 2>&1; then
    alias %s-status='git status --short'
fi

# Example alias with parameters
alias %s-debug='%s_debug'
`, module_name, replace_chars(module_name, '_', '-'), 
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '_', '-'),
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '_', '-'),
   replace_chars(module_name, '_', '-'),
   replace_chars(module_name, '-', '_'))
    
    colors.print_info("Creating example aliases: aliases/example.zsh")
    success := os.write_entire_file(alias_file, transmute([]u8)alias_content)
    if !success {
        colors.print_warning("Failed to create aliases/example.zsh: %s", alias_file)
    }
}

// create_readme_file creates a README.md file for the module
create_readme_file :: proc(module_dir: string, module_name: string) {
    readme_path := filepath.join({module_dir, "README.md"})
    
    readme_content := fmt.tprintf(`# %s

A shell module for %s functionality.

## Description

This module was generated by Zephyr Shell Loader. Replace this description with details about what your module does.

## Features

- Example function: %s_hello
- Example alias: %s-hello
- Modular structure with organized functions and aliases

## Usage

This module is automatically loaded by Zephyr. The following commands are available:

### Functions

- %s_hello - Displays a hello message
- %s_info <message> - Displays an info message
- %s_debug <message> - Displays debug message if debug mode is enabled

### Aliases

- %s-hello - Shortcut for %s_hello
- %s-info - Shortcut for %s_info

## Configuration

You can configure this module using environment variables:

- ZSH_MODULE_%s_DEBUG - Set to "true" to enable debug output

## Development

### File Structure

%s/
|-- module.toml          # Module manifest
|-- init.zsh            # Main initialization script
|-- functions/          # Shell functions
|   |-- example.zsh
|-- aliases/            # Shell aliases
|   |-- example.zsh
|-- completions/        # Shell completions (empty)
|-- README.md          # This file

### Adding New Features

1. Add functions to functions/*.zsh files
2. Add aliases to aliases/*.zsh files  
3. Add completions to completions/*.zsh files
4. Update this README with documentation

## License

MIT License - see module.toml for details.
`, to_title_case(module_name), module_name,
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '_', '-'),
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '_', '-'),
   replace_chars(module_name, '-', '_'),
   replace_chars(module_name, '_', '-'),
   replace_chars(module_name, '-', '_'),
   strings.to_upper(module_name), module_name)
    
    colors.print_info("Creating documentation: README.md")
    success := os.write_entire_file(readme_path, transmute([]u8)readme_content)
    if !success {
        colors.print_warning("Failed to create README.md: %s", readme_path)
    }
}
// provide_usage_instructions displays helpful information after module creation
provide_usage_instructions :: proc(module_name: string, module_dir: string) {
    colors.print_success("Module created successfully!")
    fmt.println("")
    
    fmt.println("Files created:")
    fmt.eprintfln("   %s/", module_dir)
    fmt.println("   |-- module.toml          # Module manifest and configuration")
    fmt.println("   |-- init.zsh            # Main initialization script")
    fmt.println("   |-- README.md           # Documentation and usage guide")
    fmt.println("   |-- functions/")
    fmt.println("   |   `-- example.zsh     # Example shell functions")
    fmt.println("   |-- aliases/")
    fmt.println("   |   `-- example.zsh     # Example shell aliases")
    fmt.println("   `-- completions/        # Directory for shell completions")
    fmt.println("")
    
    fmt.println("Next steps:")
    fmt.println("")
    fmt.println("1. Edit the module manifest:")
    fmt.eprintfln("   vim %s/module.toml", module_dir)
    fmt.println("   - Update description, author, and license")
    fmt.println("   - Add dependencies if needed")
    fmt.println("   - Configure platform compatibility")
    fmt.println("")
    
    fmt.println("2. Customize your module:")
    fmt.eprintfln("   vim %s/init.zsh", module_dir)
    fmt.eprintfln("   vim %s/functions/example.zsh", module_dir)
    fmt.eprintfln("   vim %s/aliases/example.zsh", module_dir)
    fmt.println("   - Replace example code with your functionality")
    fmt.println("   - Add more files as needed")
    fmt.println("")
    
    fmt.println("3. Test your module:")
    fmt.println("   zephyr validate          # Check for manifest errors")
    fmt.println("   zephyr list              # See module in load order")
    fmt.println("   zephyr load              # Generate shell code")
    fmt.println("")
    
    fmt.println("4. Load your module:")
    fmt.println("   # Add this to your .zshrc if not already present:")
    fmt.println("   eval \"$(zephyr load)\"")
    fmt.println("")
    fmt.println("   # Then reload your shell or run:")
    fmt.println("   source ~/.zshrc")
    fmt.println("")
    
    fmt.println("Documentation:")
    fmt.eprintfln("   Read %s/README.md for detailed information", module_dir)
    fmt.println("   Visit https://github.com/xDarkicex/zephyr for more examples")
    fmt.println("")
    
    fmt.println("Example commands to try after loading:")
    fmt.eprintfln("   %s_hello                 # Call example function", replace_chars(module_name, '-', '_'))
    fmt.eprintfln("   %s-hello                 # Use example alias", replace_chars(module_name, '_', '-'))
    fmt.eprintfln("   %s_info \"Hello World\"     # Function with parameter", replace_chars(module_name, '-', '_'))
    fmt.println("")
    
    colors.print_success("Happy coding with your new '%s' module!", module_name)
}
