package cli

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../colors"
import "../errors"
import "../git"
import "../loader"
import "../security"

// Update_Options captures CLI inputs for update.
Update_Options :: struct {
	module_name: string,
	check_only:  bool,
	force:       bool,
	skip_scan:   bool,
	unsafe:      bool,
	manager_opts: git.Manager_Options,
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
		if arg == "--check" {
			options.check_only = true
			continue
		}
		if arg == "--force" {
			options.force = true
			options.manager_opts.force = true
			continue
		}
		if arg == "--skip-scan" {
			options.skip_scan = true
			options.manager_opts.skip_scan = true
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
		if options.module_name == "" {
			options.module_name = arg
		}
	}

	return options
}

// update_command executes the update workflow and exits on failure.
update_command :: proc() {
	options := parse_update_options()

	init_git_or_exit()
	defer shutdown_git()

	if !check_update_permissions(options) {
		colors.print_error("Permission denied")
		os.exit(2)
	}

	if options.check_only {
		exit_code := check_for_updates(options)
		os.exit(exit_code)
	}

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

check_update_permissions :: proc(options: Update_Options) -> bool {
	if options.force && !security.require_permission(.Use_Unsafe, "use --force") {
		return false
	}
	if options.skip_scan && !security.require_permission(.Use_Unsafe, "skip security scan") {
		return false
	}
	if options.unsafe && !security.require_permission(.Use_Unsafe, "use --unsafe") {
		return false
	}
	return true
}

check_for_updates :: proc(options: Update_Options) -> int {
	modules := get_modules_to_update(options.module_name)
	if len(modules) == 0 {
		fmt.println(errors.format_info("No modules installed", "Nothing to update"))
		return 0
	}
	defer git.cleanup_manager_results(modules[:])

	updates := 0
	skipped := 0
	failed := 0
	lines := make([dynamic]string)
	defer git.cleanup_manager_results(lines[:])

	for module_name in modules {
		module_path := filepath_for_module(module_name)
		if module_path == "" || !os.exists(module_path) {
			line := strings.clone(fmt.tprintf("%s %s: not found", colors.error_symbol(), module_name))
			append(&lines, line)
			failed += 1
			continue
		}

		if !git.is_git_repository(module_path) {
			line := strings.clone(fmt.tprintf("%s %s: skipped (not a git repository)", colors.warning_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			skipped += 1
			continue
		}
		if !git.has_remote_origin(module_path) {
			line := strings.clone(fmt.tprintf("%s %s: skipped (no git remote)", colors.warning_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			skipped += 1
			continue
		}

		current, curr_result := git.get_current_commit(module_path)
		defer git.cleanup_git_result(&curr_result)
		if !curr_result.success {
			line := strings.clone(fmt.tprintf("%s %s: check failed", colors.error_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			failed += 1
			continue
		}
		defer if current != "" { delete(current) }

		branch, branch_result := git.get_current_branch(module_path)
		defer git.cleanup_git_result(&branch_result)
		if !branch_result.success {
			line := strings.clone(fmt.tprintf("%s %s: check failed", colors.error_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			failed += 1
			continue
		}
		defer if branch != "" { delete(branch) }

		fetch_result := git.fetch_origin(module_path)
		defer git.cleanup_git_result(&fetch_result)
		if !fetch_result.success {
			line := strings.clone(fmt.tprintf("%s %s: fetch failed", colors.error_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			failed += 1
			continue
		}

		remote, remote_result := git.get_remote_commit_hash(module_path, branch)
		defer git.cleanup_git_result(&remote_result)
		if !remote_result.success {
			line := strings.clone(fmt.tprintf("%s %s: check failed", colors.error_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			failed += 1
			continue
		}
		defer if remote != "" { delete(remote) }

		if current == remote {
			line := strings.clone(fmt.tprintf("%s %s: up to date", colors.success_symbol(), module_name))
			append(&lines, line)
			delete(module_path)
			continue
		}

		updates += 1
		line := strings.clone(fmt.tprintf("%s %s: update available", colors.warning_symbol(), module_name))
		append(&lines, line)
		delete(module_path)
	}

	summary := errors.format_summary("Update Check", lines[:], updates, failed+skipped)
	fmt.println(summary)

	if updates > 0 {
		return 1
	}
	return 0
}

get_modules_to_update :: proc(module_name: string) -> [dynamic]string {
	if module_name != "" {
		return []string{strings.clone(module_name)}
	}

	names := git.list_installed_modules()
	if names == nil {
		return nil
	}
	return names
}

filepath_for_module :: proc(module_name: string) -> string {
	if module_name == "" {
		return ""
	}
	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)
	if modules_dir == "" {
		return ""
	}
	return filepath.join({modules_dir, module_name})
}
