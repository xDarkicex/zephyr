package cli

import "core:fmt"
import "core:os"
import "core:strings"

import "../colors"
import "../debug"
import "../git"

// Install_Options captures CLI inputs for git install.
Install_Options :: struct {
	url:          string,
	allow_local:  bool,
	unsafe:       bool,
	manager_opts: git.Manager_Options,
}

// Update_Options captures CLI inputs for git update.
Update_Options :: struct {
	module_name:  string,
	manager_opts: git.Manager_Options,
}

// Uninstall_Options captures CLI inputs for git uninstall.
Uninstall_Options :: struct {
	module_name:  string,
	manager_opts: git.Manager_Options,
}

// parse_install_options parses install flags from os.args.
parse_install_options :: proc() -> Install_Options {
	options := Install_Options{}

	args := os.args[1:]
	for arg in args {
		if arg == "install" {
			continue
		}
		if is_global_flag(arg) {
			if arg == "-v" || arg == "--verbose" {
				options.manager_opts.verbose = true
			}
			continue
		}
		if arg == "--force" {
			options.manager_opts.force = true
			continue
		}
		if arg == "--local" {
			options.allow_local = true
			options.manager_opts.allow_local = true
			continue
		}
		if arg == "--unsafe" {
			options.unsafe = true
			options.manager_opts.unsafe = true
			continue
		}
		if strings.has_prefix(arg, "-") {
			continue
		}
		if options.url == "" {
			options.url = arg
		}
	}

	return options
}

// parse_update_options parses update flags from os.args.
parse_update_options :: proc() -> Update_Options {
	options := Update_Options{}

	args := os.args[1:]
	for arg in args {
		if arg == "update" {
			continue
		}
		if is_global_flag(arg) {
			if arg == "-v" || arg == "--verbose" {
				options.manager_opts.verbose = true
			}
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

// parse_uninstall_options parses uninstall flags from os.args.
parse_uninstall_options :: proc() -> Uninstall_Options {
	options := Uninstall_Options{}
	options.manager_opts.check_dependencies = true

	args := os.args[1:]
	for arg in args {
		if arg == "uninstall" {
			continue
		}
		if is_global_flag(arg) {
			if arg == "-v" || arg == "--verbose" {
				options.manager_opts.verbose = true
			}
			continue
		}
		if arg == "--confirm" {
			options.manager_opts.confirm = true
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

// install_command executes the install workflow and exits on failure.
install_command :: proc() {
	options := parse_install_options()
	if options.url == "" {
		colors.print_error("Install source required")
		fmt.eprintln("Usage: zephyr install <git-url> [--force] [--local] [--unsafe]")
		os.exit(1)
	}

	init_git_or_exit()
	defer shutdown_git()

	success, message := git.install_module(options.url, options.manager_opts)
	if message != "" {
		if success {
			fmt.println(message)
		} else {
			fmt.eprintln(message)
		}
		delete(message)
	}
	if !success {
		os.exit(1)
	}
}

// update_command executes the update workflow and exits on failure.
update_command :: proc() {
	options := parse_update_options()

	init_git_or_exit()
	defer shutdown_git()

	success, message := git.update_module(options.module_name, options.manager_opts)
	if message != "" {
		if success {
			fmt.println(message)
		} else {
			fmt.eprintln(message)
		}
		delete(message)
	}
	if !success {
		os.exit(1)
	}
}

// uninstall_command executes the uninstall workflow and exits on failure.
uninstall_command :: proc() {
	options := parse_uninstall_options()
	if options.module_name == "" {
		colors.print_error("Module name required")
		fmt.eprintln("Usage: zephyr uninstall <module-name> [--confirm]")
		os.exit(1)
	}

	init_git_or_exit()
	defer shutdown_git()

	success, message := git.uninstall_module(options.module_name, options.manager_opts)
	if message != "" {
		if success {
			fmt.println(message)
		} else {
			fmt.eprintln(message)
		}
		delete(message)
	}
	if !success {
		os.exit(1)
	}
}

// is_global_flag returns true for flags handled globally by the CLI.
is_global_flag :: proc(arg: string) -> bool {
	return arg == "-v" ||
		arg == "--verbose" ||
		arg == "-d" ||
		arg == "--debug" ||
		arg == "--trace" ||
		arg == "--no-color"
}

// init_git_or_exit initializes libgit2 or terminates with an error message.
init_git_or_exit :: proc() {
	if !git.libgit2_enabled() {
		colors.print_error("Git support is not available in this build")
		fmt.eprintln("Rebuild with libgit2 enabled to use git commands.")
		os.exit(1)
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		message := "Failed to initialize git support"
		if init_result.message != "" {
			message = init_result.message
		}
		colors.print_error("%s", message)
		os.exit(1)
	}

	debug.debug_info("libgit2 initialized")
}

// shutdown_git shuts down libgit2, logging warnings on failure.
shutdown_git :: proc() {
	shutdown_result := git.shutdown_libgit2()
	defer git.cleanup_git_result(&shutdown_result)
	if !shutdown_result.success {
		debug.debug_warn("libgit2 shutdown failed: %s", shutdown_result.message)
	}
}
