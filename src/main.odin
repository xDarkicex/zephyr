package main

import "cli"
import "colors"
import "core:fmt"
import "core:os"
import "core:strings"
import "debug"
import "errors"
import "loader"
import "manifest"

main :: proc() {
	// Initialize colors and debug modules
	colors.init_colors()
	debug.init_debug()

	debug.debug_args(os.args[:])

	// Parse command line arguments for flags
	args := os.args[1:]
	command := ""
	verbose := false
	debug_mode := false
	force_shell := ""

	// Process flags and find command
	i := 0
	for i < len(args) {
		arg := args[i]

		if arg == "-v" || arg == "--verbose" {
			verbose = true
			debug.set_debug_level(.Info)
			debug.debug_info("Verbose mode enabled")
		} else if arg == "-d" || arg == "--debug" {
			debug_mode = true
			debug.set_debug_level(.Debug)
			debug.debug_debug("Debug mode enabled")
		} else if arg == "--trace" {
			debug.set_debug_level(.Trace)
			debug.debug_trace("Trace mode enabled")
		} else if arg == "--no-color" {
			colors.disable_colors()
			debug.debug_info("Color output disabled")
		} else if strings.has_prefix(arg, "--shell=") {
			// Handle --shell=bash syntax
			force_shell = arg[8:]
			debug.debug_info("Force shell: %s", force_shell)
		} else if arg == "--shell" {
			// Handle --shell bash syntax
			i += 1
			if i < len(args) {
				force_shell = args[i]
				debug.debug_info("Force shell: %s", force_shell)
			}
		} else {
			// First non-flag argument is the command
			command = arg
			break
		}
		i += 1
	}

	// Configure shell backend before any emission
	shell_config := loader.Shell_Config{force_shell = force_shell}
	loader.set_emit_config(shell_config)

	debug.debug_info("Processing command: %s", command)

	cli.run_first_time_setup()

	// Command routing logic
	if command == "" {
		// Default behavior: run load command
		debug.debug_info("No command specified, defaulting to load")
		run_load()
		return
	}

	switch command {
	case "load":
		run_load()
	case "list":
		run_list()
	case "validate":
		run_validate()
	case "init":
		run_init()
	case "scan":
		run_scan()
	case "install":
		run_install()
	case "update":
		run_update()
	case "uninstall":
		run_uninstall()
	case "show-signing-key":
		run_show_signing_key()
	case "verify":
		run_verify()
	case "help", "--help", "-h":
		print_usage()
	case:
		colors.print_error("Unknown command '%s'", command)
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
	// Find the module name argument after processing flags
	args := os.args[1:]
	module_name := ""

	// Skip flags to find module name
	for arg in args {
		if arg != "-v" &&
		   arg != "--verbose" &&
		   arg != "-d" &&
		   arg != "--debug" &&
		   arg != "--trace" &&
		   arg != "--no-color" &&
		   arg != "init" &&
		   !strings.has_prefix(arg, "--shell") {
			module_name = arg
			break
		}
	}

	if module_name == "" {
		colors.print_error("Module name required")
		fmt.eprintln("Usage: zephyr init <module-name>")
		fmt.eprintln("")
		fmt.eprintln("Example: zephyr init my-shell-module")
		os.exit(1)
	}

	debug.debug_info("Creating module: %s", module_name)
	cli.init_module(module_name)
}

run_scan :: proc() {
	cli.scan_command()
}

run_install :: proc() {
	cli.install_command()
}

run_update :: proc() {
	cli.update_command()
}

run_uninstall :: proc() {
	cli.uninstall_command()
}

run_show_signing_key :: proc() {
	cli.show_signing_key_command()
}

run_verify :: proc() {
	args := os.args[1:]
	module_path := ""
	for arg in args {
		if arg == "verify" {
			continue
		}
		if strings.has_prefix(arg, "-") {
			continue
		}
		module_path = arg
		break
	}
	cli.verify_module_command(module_path)
}

// run_load implements the default load behavior
run_load :: proc() {
	debug.debug_enter("run_load")
	defer debug.debug_exit("run_load")

	// Get modules directory with error handling
	modules_dir := get_modules_directory()
	defer delete(modules_dir)
	debug.debug_info("Using modules directory: %s", modules_dir)

	// Verify directory exists and is accessible
	if !os.exists(modules_dir) {
		debug.debug_error("Modules directory does not exist: %s", modules_dir)
		colors.print_error("Modules directory does not exist: %s", modules_dir)
		fmt.eprintln("")
		errors.suggest_for_directory_error(modules_dir, false, false)
		os.exit(1)
	}

	// Check if it's actually a directory
	file_info, stat_err := os.stat(modules_dir)
	if stat_err != os.ERROR_NONE {
		debug.debug_error("Cannot access modules directory: %s, error: %v", modules_dir, stat_err)
		colors.print_error("Cannot access modules directory: %s", modules_dir)
		colors.print_error("System error: %v", stat_err)
		fmt.eprintln("")
		errors.suggest_for_directory_error(modules_dir, true, false)
		os.exit(1)
	}

	if !file_info.is_dir {
		debug.debug_error("Path is not a directory: %s", modules_dir)
		colors.print_error("Path is not a directory: %s", modules_dir)
		fmt.eprintln("")
		errors.suggest_for_directory_error(modules_dir, true, false)
		os.exit(1)
	}

	// Discovery phase with detailed error handling
	debug.debug_info("Starting module discovery")
	modules := loader.discover(modules_dir)
	debug.debug_info("Discovered %d modules", len(modules))

	if len(modules) == 0 {
		debug.debug_warn("No modules found in directory")
		colors.print_warning("No modules found in: %s", modules_dir)
		fmt.eprintln("")
		errors.suggest_for_directory_error(modules_dir, true, true)
		os.exit(1)
	}
	defer {
		manifest.cleanup_modules(modules[:])
		delete(modules)
		// Clean up the cache after we're done with the modules
		loader.cleanup_cache()
	}

	// Platform filtering phase
	debug.debug_info("Starting platform filtering")
	compatible_indices := loader.filter_compatible_indices(modules)
	debug.debug_info("Found %d compatible modules", len(compatible_indices))

	if len(compatible_indices) == 0 {
		debug.debug_warn("No compatible modules for current platform")
		colors.print_warning(
			"No compatible modules found for current platform in: %s",
			modules_dir,
		)
		fmt.eprintln("")
		errors.suggest_for_platform_error()
		os.exit(1)
	}
	defer delete(compatible_indices)

	// Dependency resolution phase with detailed error handling
	debug.debug_info("Starting dependency resolution")
	resolved_modules, err := loader.resolve_filtered(modules, compatible_indices)
	if err != "" {
		debug.debug_error("Dependency resolution failed: %s", err)
		colors.print_error("Dependency resolution failed")
		colors.print_error("Details: %s", err)
		fmt.eprintln("")
		errors.suggest_for_dependency_error(err)
		os.exit(1)
	}
	defer {
		if resolved_modules != nil {
			// ✅ CRITICAL FIX: resolved_modules contains deep clones with owned strings
			// We must clean up the module contents before deleting the array
			manifest.cleanup_modules(resolved_modules[:])
			delete(resolved_modules)
		}
	}

	debug.debug_info("Resolved %d modules in dependency order", len(resolved_modules))

	// Shell code emission phase
	debug.debug_info("Emitting shell code")
	// Note: emit() writes to stdout, so any errors would be from I/O
	// The loader.emit() function handles its own error cases internally
	loader.emit(resolved_modules)
	debug.debug_info("Shell code emission completed")
}

// get_modules_directory resolves the modules directory path
// Uses ZSH_MODULES_DIR environment variable if set, otherwise defaults to $HOME/.zsh/modules
get_modules_directory :: proc() -> string {
	debug.debug_enter("get_modules_directory")
	defer debug.debug_exit("get_modules_directory")

	// Check for ZSH_MODULES_DIR environment variable first
	modules_dir := os.get_env("ZSH_MODULES_DIR")
	debug.debug_env_var("ZSH_MODULES_DIR", modules_dir)
	
	if modules_dir != "" {
		debug.debug_info("Using ZSH_MODULES_DIR: %s", modules_dir)
		return modules_dir
	}
	delete(modules_dir)

	// Use the loader package's get_modules_dir function for consistency
	result := loader.get_modules_dir()
	debug.debug_info("Using default modules directory: %s", result)
	return result
}

// print_usage displays help information for the CLI
print_usage :: proc() {
	fmt.println("Zephyr Shell Loader - Modular shell configuration management")
	fmt.println("")
	fmt.println("USAGE:")
	fmt.println("    zephyr [FLAGS] [COMMAND]")
	fmt.println("")
	fmt.println("FLAGS:")
	fmt.println("    -v, --verbose     Enable verbose output")
	fmt.println("    -d, --debug       Enable debug output")
	fmt.println("        --trace       Enable trace output (maximum verbosity)")
	fmt.println("        --no-color    Disable colored output")
	fmt.println("        --shell=SHELL Force shell type (zsh or bash)")
	fmt.println("    -h, --help        Show this help message")
	fmt.println("")
	fmt.println("COMMANDS:")
	fmt.println("    load        Generate shell code for loading modules (default)")
	fmt.println("    list        List discovered modules and their load order")
	fmt.println("    validate    Validate all module manifests for errors")
	fmt.println("    init        Create a new module skeleton")
	fmt.println("    scan        Scan a module source for security findings")
	fmt.println("    install     Install a module from a git repository")
	fmt.println("    update      Update installed modules")
	fmt.println("    uninstall   Remove an installed module")
	fmt.println("    show-signing-key  Show the official Zephyr signing key")
	fmt.println("    verify      Verify a signed module tarball")
	fmt.println("    help        Show this help message")
	fmt.println("")
	fmt.println("EXAMPLES:")
	fmt.println("    zephyr                       # Load modules (auto-detect shell)")
	fmt.println("    zephyr --shell=bash load     # Force Bash output")
	fmt.println("    zephyr --shell=zsh load      # Force ZSH output")
	fmt.println("    zephyr -v load               # Load modules with verbose output")
	fmt.println("    zephyr --debug list          # Show modules with debug information")
	fmt.println("    zephyr validate              # Check manifests for errors")
	fmt.println("    zephyr init my-module        # Create new module 'my-module'")
	fmt.println("    zephyr scan <git-url>        # Scan a module for security findings")
	fmt.println("    zephyr scan <git-url> --json # Emit JSON scan report (agent-friendly)")
	fmt.println("    zephyr install <git-url>     # Install a module from git")
	fmt.println("    zephyr install --unsafe <git-url>  # Install despite security findings")
	fmt.println("    zephyr update                # Update all modules")
	fmt.println("    zephyr update my-module      # Update a single module")
	fmt.println("    zephyr uninstall my-module   # Remove a module")
	fmt.println("    zephyr show-signing-key      # Display Zephyr signing key")
	fmt.println("    zephyr verify <path>         # Verify a signed tarball")
	fmt.println("")
	fmt.println("ENVIRONMENT:")
	fmt.println(
		"    ZSH_MODULES_DIR           Directory containing modules (default: ~/.zsh/modules)",
	)
	fmt.println(
		"    ZEPHYR_DEBUG              Enable debug output (0-3 or false/true/debug/trace)",
	)
	fmt.println("    ZEPHYR_VERBOSE            Enable verbose output (0-3 or false/true)")
	fmt.println("    ZEPHYR_DEBUG_TIMESTAMPS   Show timestamps in debug output")
	fmt.println("    ZEPHYR_DEBUG_LOCATION     Show source location in debug output")
	fmt.println("    NO_COLOR                  Disable colored output")
	fmt.println("")
	fmt.println("INTEGRATION:")
	fmt.println("    ZSH:   Add to .zshrc:  eval \"$(zephyr load)\"")
	fmt.println("    Bash:  Add to .bashrc: eval \"$(zephyr load)\"")
	fmt.println("")
	fmt.println("For more information, visit: https://github.com/xDarkicex/zephyr")
}
