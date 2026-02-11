package cli

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:os/os2"

import "../colors"
import "../errors"
import "../loader"
import "../manifest"
import "../security"

// Uninstall_Options captures CLI inputs for uninstall.
Uninstall_Options :: struct {
	module_name: string,
	force:       bool,
	yes:         bool,
}

Confirm_Reader :: proc() -> string

default_confirm_reader :: proc() -> string {
	buf: [256]byte
	n, _ := os.read(os.stdin, buf[:])
	if n <= 0 {
		return strings.clone("")
	}
	return strings.clone(strings.trim_space(string(buf[:n])))
}

confirm_reader := default_confirm_reader

// parse_uninstall_options parses uninstall flags from os.args.
parse_uninstall_options :: proc() -> Uninstall_Options {
	options := Uninstall_Options{}

	args := os.args[1:]
	for arg in args {
		if arg == "uninstall" {
			continue
		}
		if is_global_flag(arg) {
			continue
		}
		if arg == "--force" || arg == "-f" {
			options.force = true
			continue
		}
		if arg == "--yes" || arg == "-y" {
			options.yes = true
			continue
		}
		if strings.has_prefix(arg, "-") {
			continue
		}
		if options.module_name == "" {
			options.module_name = arg
		}
	}

	return options
}

// uninstall_module_internal performs uninstall logic and returns success + message.
uninstall_module_internal :: proc(options: Uninstall_Options) -> (bool, string) {
	if options.module_name == "" {
		return false, strings.clone("module name is required")
	}

	if !security.require_permission(.Uninstall, "uninstall module") {
		security.log_module_uninstall(options.module_name, false, "permission denied")
		return false, strings.clone("permission denied")
	}

	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)
	if modules_dir == "" || !os.exists(modules_dir) {
		security.log_module_uninstall(options.module_name, false, "modules directory not found")
		return false, strings.clone("modules directory not found")
	}

	module_path := filepath.join({modules_dir, options.module_name})
	if module_path == "" {
		return false, strings.clone("failed to build module path")
	}
	defer delete(module_path)

	if !os.exists(module_path) {
		security.log_module_uninstall(options.module_name, false, "module not found")
		return false, strings.clone("module not found")
	}

	modules := loader.discover(modules_dir)
	defer {
		if modules != nil {
			manifest.cleanup_modules(modules[:])
			delete(modules)
		}
	}
	if modules == nil || len(modules) == 0 {
		security.log_module_uninstall(options.module_name, false, "no modules discovered")
		return false, strings.clone("no modules discovered")
	}

	resolved_modules, err := loader.resolve(modules)
	if err != "" {
		security.log_module_uninstall(options.module_name, false, "dependency resolution failed")
		msg := strings.clone(fmt.tprintf("dependency resolution failed: %s", err))
		delete(err)
		return false, msg
	}
	defer {
		if resolved_modules != nil {
			manifest.cleanup_modules(resolved_modules[:])
			delete(resolved_modules)
		}
	}

	reverse := loader.build_reverse_deps(resolved_modules)
	defer loader.cleanup_reverse_deps(reverse)

	dependents, has := loader.get_dependents(options.module_name, reverse)
	if has && dependents != nil && len(dependents) > 0 && !options.force {
		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)
		fmt.sbprintf(&builder, "module has dependents: ")
		for dep, idx in dependents {
			if idx > 0 {
				fmt.sbprintf(&builder, ", ")
			}
			fmt.sbprintf(&builder, "%s", dep)
		}
		fmt.sbprintf(&builder, ". Use --force to uninstall anyway.")
		message := strings.clone(strings.to_string(builder))
		security.log_module_uninstall(options.module_name, false, "dependents found")
		return false, message
	}

	if has && dependents != nil && len(dependents) > 0 && options.force {
		if !show_force_warning(options.module_name, dependents, options.yes) {
			security.log_module_uninstall(options.module_name, false, "force uninstall canceled")
			return false, strings.clone("uninstall canceled")
		}
	}

	if !remove_module_directory(module_path) {
		security.log_module_uninstall(options.module_name, false, "failed to remove module directory")
		return false, strings.clone("failed to remove module directory")
	}

	security.log_module_uninstall(options.module_name, true, "uninstalled")
	return true, strings.clone(fmt.tprintf("✓ Module '%s' uninstalled successfully.", options.module_name))
}

// uninstall_command executes the uninstall workflow and exits on failure.
uninstall_command :: proc() {
	options := parse_uninstall_options()
	if options.module_name == "" {
		colors.print_error("Module name required")
		fmt.eprintln("Usage: zephyr uninstall <module-name> [--force] [--yes]")
		os.exit(1)
	}

	success, message := uninstall_module_internal(options)
	if message != "" {
		if success {
			fmt.println(message)
		} else {
			colors.print_error("%s", message)
			if message == "module not found" {
				fmt.eprintln("")
				errors.suggest_for_directory_error(options.module_name, true, false)
			}
		}
		delete(message)
	}
	if !success {
		os.exit(1)
	}
}

// remove_module_directory removes a module directory and returns true on success.
remove_module_directory :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	os2.remove_all(path)
	return !os.exists(path)
}

show_force_warning :: proc(module_name: string, dependents: []string, skip_prompt: bool) -> bool {
	fmt.printf("%s Force uninstall requested.\n", colors.warning_symbol())
	fmt.printf("  Module: %s\n", module_name)
	if dependents != nil && len(dependents) > 0 {
		deps_joined := strings.join(dependents, ", ")
		defer delete(deps_joined)
		fmt.printf("  Dependents: %s\n", deps_joined)
	}
	if is_critical_module(module_name) {
		fmt.println("")
		fmt.printf("%s WARNING: This is a critical module.\n", colors.error_symbol())
		fmt.println("  Removing it may break core functionality.")
	}
	fmt.println("")
	if skip_prompt {
		return true
	}
	return confirm("Proceed with uninstall? [y/N]: ")
}

confirm :: proc(message: string) -> bool {
	fmt.print(message)
	response := confirm_reader()
	defer delete(response)
	if response == "" {
		return false
	}
	lower := strings.to_lower(response)
	defer delete(lower)
	return lower == "y" || lower == "yes"
}
