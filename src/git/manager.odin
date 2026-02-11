package git

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../colors"
import "../debug"
import "../errors"
import "../loader"
import "../manifest"
import "../security"

// Manager_Options controls user-facing behavior for git operations.
Manager_Options :: struct {
	verbose: bool,
	force:   bool,
	confirm: bool,
	allow_local: bool,
	check_dependencies: bool,
	unsafe: bool,
	skip_scan: bool,
}

// Module_Manager_Error enumerates high-level operation failures.
Module_Manager_Error :: enum {
	None,
	Invalid_URL,
	Invalid_Module_Name,
	Clone_Failed,
	Fetch_Failed,
	Pull_Failed,
	Rollback_Failed,
	Update_Failed,
	No_Manifest,
	Invalid_Manifest,
	Name_Mismatch,
	Platform_Incompatible,
	Missing_Files,
	Already_Exists,
	Move_Failed,
	Validation_Failed,
	Cleanup_Failed,
	Not_Found,
	Unknown,
}

// Update_Result reports success plus optional messages and summaries.
Update_Status :: enum {
	Success,
	Failed,
	Skipped,
	Rolled_Back,
}

Update_Result :: struct {
	success: bool,
	message: string,
	summary: string,
	status: Update_Status,
	old_version: string,
	new_version: string,
	commits_pulled: int,
	files_changed: int,
}

// cleanup_update_result frees any owned strings.
cleanup_update_result :: proc(result: ^Update_Result) {
	if result == nil do return
	if result.message != "" {
		delete(result.message)
		result.message = ""
	}
	if result.summary != "" {
		delete(result.summary)
		result.summary = ""
	}
	result.status = .Failed
	if result.old_version != "" {
		delete(result.old_version)
		result.old_version = ""
	}
	if result.new_version != "" {
		delete(result.new_version)
		result.new_version = ""
	}
	result.commits_pulled = 0
	result.files_changed = 0
	result.success = false
}

// list_installed_modules returns discovered module names in the modules directory.
list_installed_modules :: proc() -> [dynamic]string {
	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)

	if modules_dir == "" || !os.exists(modules_dir) {
		return nil
	}

	modules := loader.discover(modules_dir)
	if len(modules) == 0 {
		if modules != nil {
			delete(modules)
		}
		return nil
	}

	names := make([dynamic]string, 0, len(modules))
	for module in modules {
		if module.name != "" {
			append(&names, strings.clone(module.name))
		}
	}

	manifest.cleanup_modules(modules[:])
	delete(modules)

	return names
}

// cleanup_manager_results frees a slice of owned strings.
cleanup_manager_results :: proc(messages: []string) {
	if messages == nil do return
	for msg in messages {
		if msg != "" {
			delete(msg)
		}
	}
	delete(messages)
}

// install_module clones, validates, and installs a module from a URL or local path.
install_module :: proc(url: string, options: Manager_Options) -> (bool, string) {
	colors.print_info("Preparing installation: %s", url)

	source := parse_install_source(url, options.allow_local)
	defer cleanup_install_source(&source)
	if !source.valid {
		security.log_module_install("", url, false, "invalid install source", false)
		return false, format_manager_error(.Invalid_URL, source.error, url, "parse install source")
	}

	source_type := detect_module_source(source)
	is_signed := source_type == .Signed_Tarball
	audit_name := derive_audit_module_name(source.url, "")
	defer {
		if audit_name != "" {
			delete(audit_name)
		}
	}

	if !security.require_permission(.Install, "install module") {
		security.log_module_install(audit_name, source.url, false, "permission denied", is_signed)
		return false, format_manager_error(.Validation_Failed, "Permission denied", url, "install")
	}
	if options.unsafe && !security.require_permission(.Use_Unsafe, "use --unsafe") {
		security.log_module_install(audit_name, source.url, false, "permission denied", is_signed)
		return false, format_manager_error(.Validation_Failed, "Permission denied", url, "unsafe")
	}
	if !is_signed && !security.require_permission(.Install_Unsigned, "install unsigned module") {
		security.log_module_install(audit_name, source.url, false, "permission denied", is_signed)
		return false, format_manager_error(.Validation_Failed, "Permission denied", url, "install unsigned")
	}

	if source_type == .Signed_Tarball {
		tar_result := install_from_tarball(source, options)
		defer cleanup_tarball_install_result(&tar_result)
		if !tar_result.success {
			security.log_module_install(audit_name, source.url, false, tar_result.message, true)
			return false, format_manager_error(.Clone_Failed, tar_result.message, url, "signed install")
		}
		security.log_module_install(audit_name, source.url, true, tar_result.message, true)
		message := tar_result.message
		tar_result.message = ""
		return true, message
	}

	is_local := source.source_type == .Local_Path
	module_name := ""
	owned_name := false
	defer {
		if owned_name && module_name != "" {
			delete(module_name)
		}
	}
	if !is_local {
		name_result := parse_module_name_from_url(source.url)
		defer cleanup_url_parse_result(&name_result)
		if !name_result.valid {
			security.log_module_install(audit_name, source.url, false, "invalid module name", false)
			return false, format_manager_error(.Invalid_Module_Name, name_result.error, url, "parse module name")
		}
		module_name = name_result.module_name
		name_result.module_name = ""
		owned_name = true
		if audit_name == "" {
			audit_name = strings.clone(module_name)
		}
	}

	debug.debug_info("Installing module: %s", module_name)
	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)

	final_path := ""
	if !is_local {
		final_path = filepath.join({modules_dir, module_name})
		if final_path == "" {
			return false, format_manager_error(.Unknown, "failed to build module path", module_name, "path join")
		}
		defer delete(final_path)

		if os.exists(final_path) && !options.force {
			return false, format_manager_error(.Already_Exists, "module already exists", module_name, "install")
		}
	}

	colors.print_info("Cloning module: %s", source.url)

	install_result := install_to_temp(source.url, module_name)
	defer cleanup_temp_install_result(&install_result)
	if !install_result.success {
		security.log_module_install(audit_name, source.url, false, install_result.error_message, false)
		return false, format_manager_error(.Clone_Failed, install_result.error_message, module_name, "git clone")
	}

	colors.print_info("Scanning for security issues: %s", module_name)
	scan_options := security.Scan_Options{
		unsafe_mode = options.unsafe,
		verbose = options.verbose,
	}
	scan_result := security.scan_module(install_result.temp_path, scan_options)
	defer security.cleanup_scan_result(&scan_result)
	if !scan_result.success {
		cleanup_temp(install_result.temp_path)
		security.log_module_install(audit_name, source.url, false, scan_result.error_message, false)
		return false, format_manager_error(.Validation_Failed, scan_result.error_message, module_name, "security scan")
	}
	if scan_result.critical_count > 0 || scan_result.warning_count > 0 {
		report := security.format_scan_report(&scan_result, module_name)
		fmt.println(report)
		delete(report)
	}
	if security.should_block_install(&scan_result, options.unsafe) {
		cleanup_temp(install_result.temp_path)
		security.log_module_install(audit_name, source.url, false, "Critical security issues detected", false)
		return false, format_manager_error(.Validation_Failed, "Critical security issues detected. Use --unsafe to override.", module_name, "security scan")
	}
	if scan_result.warning_count > 0 && !options.unsafe {
		if !security.prompt_user_for_warnings(&scan_result, module_name) {
			cleanup_temp(install_result.temp_path)
			security.log_module_install(audit_name, source.url, false, "Installation cancelled by user", false)
			return false, format_manager_error(.Validation_Failed, "Installation cancelled by user", module_name, "security scan")
		}
	}
	if options.unsafe && (scan_result.critical_count > 0 || scan_result.warning_count > 0) {
		colors.print_warning("Unsafe mode enabled: security checks bypassed")
	}

	if options.verbose {
		colors.print_info("Validating module: %s", module_name)
	}

	expected_name := ""
	if !is_local {
		expected_name = module_name
	}
	validation := validate_module(install_result.temp_path, expected_name)
	defer cleanup_validation_result(&validation)
	if validation.warning != "" {
		colors.print_warning("%s", validation.warning)
	}

	if options.unsafe {
		audit_name := module_name
		if is_local && validation.module.name != "" {
			audit_name = validation.module.name
		}
		security.audit_unsafe_usage(audit_name, source.url, &scan_result)
	}

	if !validation.valid {
		cleanup_temp(install_result.temp_path)
		security.log_module_install(audit_name, source.url, false, "manifest validation failed", false)
		return false, format_manager_validation_error(&validation, module_name)
	}

	if is_local {
		if validation.module.name == "" {
			cleanup_temp(install_result.temp_path)
			return false, format_manager_error(.Invalid_Manifest, "manifest missing name field", "", "validate")
		}
		module_name = strings.clone(validation.module.name)
		owned_name = true
		final_path = filepath.join({modules_dir, module_name})
		if final_path == "" {
			cleanup_temp(install_result.temp_path)
			return false, format_manager_error(.Unknown, "failed to build module path", module_name, "path join")
		}
		defer delete(final_path)

		if os.exists(final_path) && !options.force {
			cleanup_temp(install_result.temp_path)
			security.log_module_install(audit_name, source.url, false, "module already exists", false)
			return false, format_manager_error(.Already_Exists, "module already exists", module_name, "install")
		}
	}

	colors.print_info("Installing module: %s", module_name)

	move_ok, move_info := move_to_final(install_result.temp_path, modules_dir, module_name, options.force)
	if !move_ok {
		cleanup_temp(install_result.temp_path)
		formatted := format_manager_error(.Move_Failed, move_info, module_name, "move to final")
		if move_info != "" {
			delete(move_info)
		}
		security.log_module_install(audit_name, source.url, false, "move to final failed", false)
		return false, formatted
	}

	if move_info != "" {
		delete(move_info)
	}

	security.log_module_install(audit_name, source.url, true, "installed", false)
	return true, format_install_success(module_name)
}

// update_module fetches/pulls updates for a module or all modules when name is empty.
update_module :: proc(module_name: string, options: Manager_Options) -> (bool, string) {
	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)

	if modules_dir == "" || !os.exists(modules_dir) {
		return false, format_manager_error(.Not_Found, "modules directory not found", module_name, "update")
	}

	if options.skip_scan && !security.require_permission(.Use_Unsafe, "skip security scan") {
		return false, format_manager_error(.Validation_Failed, "Permission denied", module_name, "update")
	}

	if module_name == "" {
		names := list_installed_modules()
		if names == nil || len(names) == 0 {
			if names != nil {
				cleanup_manager_results(names[:])
			}
			return true, errors.format_info("No modules installed", "Nothing to update")
		}

		items := make([dynamic]string, 0, len(names))
		success_count := 0
		error_count := 0
		skipped_count := 0

		for name in names {
			if name == "" do continue
				module_path := filepath.join({modules_dir, name})
				if module_path == "" {
					line := strings.clone(fmt.tprintf("%s %s: invalid module path", colors.error_symbol(), name))
					append(&items, line)
					error_count += 1
					continue
				}

				if !os.exists(module_path) {
					line := strings.clone(fmt.tprintf("%s %s: not found", colors.error_symbol(), name))
					append(&items, line)
					delete(module_path)
					error_count += 1
					continue
			}

			result := update_single_module(name, module_path, options)
			if result.summary != "" {
				append(&items, result.summary)
				result.summary = ""
			}
			switch result.status {
			case .Success:
				success_count += 1
			case .Skipped:
				skipped_count += 1
			case:
				error_count += 1
			}
			cleanup_update_result(&result)
			delete(module_path)
		}

		summary := format_update_summary(items[:], success_count, error_count, skipped_count)
		cleanup_manager_results(items[:])
		cleanup_manager_results(names[:])
		return error_count == 0, summary
	}

	module_path := filepath.join({modules_dir, module_name})
	if module_path == "" {
		return false, format_manager_error(.Unknown, "failed to build module path", module_name, "update")
	}
	defer delete(module_path)

	if !os.exists(module_path) {
		return false, format_manager_error(.Not_Found, "module not found", module_name, "update")
	}

	result := update_single_module(module_name, module_path, options)
	success := result.success
	message := result.message
	result.message = ""
	cleanup_update_result(&result)
	return success, message
}

// uninstall_module removes an installed module, optionally checking dependents.
uninstall_module :: proc(module_name: string, options: Manager_Options) -> (bool, string) {
	if module_name == "" {
		return false, format_manager_error(.Invalid_Module_Name, "module name is required", "", "uninstall")
	}

	if !security.require_permission(.Uninstall, "uninstall module") {
		security.log_module_uninstall(module_name, false, "permission denied")
		return false, format_manager_error(.Validation_Failed, "Permission denied", module_name, "uninstall")
	}

	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)

	if modules_dir == "" || !os.exists(modules_dir) {
		security.log_module_uninstall(module_name, false, "modules directory not found")
		return false, format_manager_error(.Not_Found, "modules directory not found", module_name, "uninstall")
	}

	module_path := filepath.join({modules_dir, module_name})
	if module_path == "" {
		return false, format_manager_error(.Unknown, "failed to build module path", module_name, "uninstall")
	}
	defer delete(module_path)

	if !os.exists(module_path) {
		security.log_module_uninstall(module_name, false, "module not found")
		return false, format_manager_error(.Not_Found, "module not found", module_name, "uninstall")
	}

	if options.check_dependencies {
		dependents := find_module_dependents(modules_dir, module_name)
		if dependents != nil && len(dependents) > 0 && !options.confirm {
			message := build_dependents_message(dependents[:])
			cleanup_manager_results(dependents[:])
			formatted := format_manager_error(.Validation_Failed, message, module_name, "uninstall")
			if message != "" {
				delete(message)
			}
			security.log_module_uninstall(module_name, false, "dependents found")
			return false, formatted
		}
		if dependents != nil {
			cleanup_manager_results(dependents[:])
		}
	}

	colors.print_info("Removing module: %s", module_name)

	cleanup_temp(module_path)
	if os.exists(module_path) {
		security.log_module_uninstall(module_name, false, "failed to remove module directory")
		return false, format_manager_error(.Cleanup_Failed, "failed to remove module directory", module_name, "uninstall")
	}

	security.log_module_uninstall(module_name, true, "uninstalled")
	return true, format_uninstall_success(module_name)
}

derive_audit_module_name :: proc(source_url: string, fallback: string) -> string {
	if fallback != "" {
		return strings.clone(fallback)
	}
	if source_url == "" {
		return ""
	}
	base := filepath.base(source_url)
	trimmed := strings.trim_suffix(base, ".git")
	trimmed = strings.trim_suffix(trimmed, ".tar.gz")
	if strings.has_prefix(trimmed, "zephyr-module-") {
		trimmed = strings.trim_prefix(trimmed, "zephyr-module-")
	} else if strings.has_prefix(trimmed, "zephyr-") {
		trimmed = strings.trim_prefix(trimmed, "zephyr-")
	}
	if trimmed == "" {
		return ""
	}
	return strings.clone(trimmed)
}

find_module_dependents :: proc(modules_dir: string, target_name: string) -> [dynamic]string {
	if modules_dir == "" || target_name == "" {
		return nil
	}

	modules := loader.discover(modules_dir)
	if modules == nil || len(modules) == 0 {
		if modules != nil {
			delete(modules)
		}
		return nil
	}

	dependents := make([dynamic]string)
	for module in modules {
		if module.name == "" || module.name == target_name {
			continue
		}

		if module.required != nil {
			for dep in module.required {
				if dep == target_name {
					append(&dependents, strings.clone(module.name))
					break
				}
			}
		}

		if module.optional != nil {
			for dep in module.optional {
				if dep == target_name {
					append(&dependents, strings.clone(module.name))
					break
				}
			}
		}
	}

	manifest.cleanup_modules(modules[:])
	delete(modules)
	return dependents
}

build_dependents_message :: proc(dependents: []string) -> string {
	if dependents == nil || len(dependents) == 0 {
		return strings.clone("module has dependents")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "module has dependents: ")
	for dep, idx in dependents {
		if idx > 0 {
			fmt.sbprintf(&builder, ", ")
		}
		fmt.sbprintf(&builder, "%s", dep)
	}
	fmt.sbprintf(&builder, ". Use --confirm to force uninstall.")
	return strings.clone(strings.to_string(builder))
}

format_uninstall_success :: proc(module_name: string) -> string {
	message := strings.clone(fmt.tprintf("Module '%s' uninstalled successfully.", module_name))
	defer delete(message)
	return errors.format_success("Uninstall complete", message)
}

update_single_module :: proc(module_name: string, module_path: string, options: Manager_Options) -> Update_Result {
	result := Update_Result{}

	colors.print_info("Updating module: %s", module_name)

	if !is_git_repository(module_path) {
		result.status = .Skipped
		result.message = format_manager_error(.Update_Failed, "not a git repository", module_name, "update")
		result.summary = strings.clone(fmt.tprintf("%s %s: skipped (not a git repository)", colors.warning_symbol(), module_name))
		return result
	}
	if !has_remote_origin(module_path) {
		result.status = .Skipped
		result.message = format_manager_error(.Update_Failed, "no git remote", module_name, "update")
		result.summary = strings.clone(fmt.tprintf("%s %s: skipped (no git remote)", colors.warning_symbol(), module_name))
		return result
	}

	manifest_path := filepath.join({module_path, "module.toml"})
	if manifest_path != "" && os.exists(manifest_path) {
		old_module, ok := manifest.parse(manifest_path)
		if ok {
			result.old_version = strings.clone(old_module.version)
			manifest.cleanup_module(&old_module)
		} else {
			manifest.cleanup_module(&old_module)
		}
		delete(manifest_path)
	}

	prev_hash, hash_result := get_head_commit_hash(module_path)
	defer cleanup_git_result(&hash_result)
	if !hash_result.success {
		detail := hash_result.message
		if detail == "" {
			detail = "failed to read current commit"
		}
			result.message = format_manager_error(.Update_Failed, detail, module_name, "read current commit")
			result.summary = strings.clone(fmt.tprintf("%s %s: update failed", colors.error_symbol(), module_name))
			result.status = .Failed
			return result
		}
	defer if prev_hash != "" { delete(prev_hash) }

	branch, branch_result := get_head_branch(module_path)
	defer cleanup_git_result(&branch_result)
	if !branch_result.success {
		detail := branch_result.message
		if detail == "" {
			detail = "failed to read current branch"
		}
		result.message = format_manager_error(.Update_Failed, detail, module_name, "read current branch")
		result.summary = strings.clone(fmt.tprintf("%s %s: update failed", colors.error_symbol(), module_name))
		result.status = .Failed
		return result
	}
	defer if branch != "" { delete(branch) }

	colors.print_info("Fetching updates: %s", module_name)

	fetch_result := fetch_repository(module_path)
	defer cleanup_git_result(&fetch_result)
	if !fetch_result.success {
		detail := fetch_result.message
		if detail == "" {
			detail = "git fetch failed"
		}
			result.message = format_manager_error(.Fetch_Failed, detail, module_name, "git fetch")
			result.summary = strings.clone(fmt.tprintf("%s %s: fetch failed", colors.error_symbol(), module_name))
			result.status = .Failed
			return result
		}

	colors.print_info("Pulling updates: %s", module_name)

	pull_result := pull_repository_branch(module_path, branch)
	defer cleanup_git_result(&pull_result)
	if !pull_result.success {
		detail := pull_result.message
		if detail == "" {
			detail = "git pull failed"
		}
			result.message = format_manager_error(.Pull_Failed, detail, module_name, "git pull")
			result.summary = strings.clone(fmt.tprintf("%s %s: pull failed", colors.error_symbol(), module_name))
			result.status = .Failed
			return result
		}

	scan_result, scan_ok, scan_message := validate_update_scan(module_name, module_path, options)
	defer security.cleanup_scan_result(&scan_result)
	if !scan_ok {
		rollback_info := rollback_update_message(module_path, prev_hash)
		message := strings.clone(fmt.tprintf("%s\nRollback: %s", scan_message, rollback_info))
		result.message = format_manager_error(.Validation_Failed, message, module_name, "security scan")
		result.summary = strings.clone(fmt.tprintf("%s %s: security scan failed", colors.error_symbol(), module_name))
		result.status = .Rolled_Back
		delete(rollback_info)
		delete(message)
		return result
	}

	validation := validate_update_manifest(module_path, module_name, options.verbose)
	defer cleanup_validation_result(&validation)
	if validation.warning != "" {
		colors.print_warning("%s", validation.warning)
	}

		if validation.valid {
			new_hash, new_hash_result := get_head_commit_hash(module_path)
			defer cleanup_git_result(&new_hash_result)
			if new_hash_result.success && new_hash != "" {
				stats, stats_result := compute_update_stats(module_path, prev_hash, new_hash)
				defer cleanup_git_result(&stats_result)
				if stats_result.success {
					result.commits_pulled = stats.commits_pulled
					result.files_changed = stats.files_changed
				}
				delete(new_hash)
			}

			manifest_path := filepath.join({module_path, "module.toml"})
			if manifest_path != "" && os.exists(manifest_path) {
				new_module, ok := manifest.parse(manifest_path)
				if ok {
					result.new_version = strings.clone(new_module.version)
					manifest.cleanup_module(&new_module)
				} else {
					manifest.cleanup_module(&new_module)
				}
				delete(manifest_path)
			}

			result.success = true
			result.status = .Success
			result.message = format_update_success(module_name)
			result.summary = format_update_line(module_name, &result)
			return result
		}

	rollback_message := ""
	rollback_message = rollback_update_message(module_path, prev_hash)

		validation_detail := build_validation_detail(&validation)
		message := strings.clone(fmt.tprintf("%s\nRollback: %s", validation_detail, rollback_message))
		result.message = format_manager_error(.Validation_Failed, message, module_name, "update")
		result.summary = strings.clone(fmt.tprintf("%s %s: validation failed", colors.error_symbol(), module_name))
		result.status = .Rolled_Back

	delete(rollback_message)
	delete(validation_detail)
	delete(message)
	return result
}

build_validation_detail :: proc(result: ^Validation_Result) -> string {
	if result == nil {
		return strings.clone("validation failed")
	}

	switch result.error {
	case .Missing_Files:
		return build_missing_files_message(result)
	case .Platform_Incompatible:
		return strings.clone(result.message)
	case .Invalid_Manifest:
		return strings.clone(result.message)
	case .No_Manifest:
		return strings.clone(result.message)
	case .Name_Mismatch:
		return strings.clone(result.message)
	case .Validation_Failed:
		return strings.clone(result.message)
	case .None:
		return strings.clone("validation failed")
	case:
		return strings.clone(result.message)
	}
}

rollback_update_message :: proc(module_path: string, prev_hash: string) -> string {
	rollback_result := reset_to_commit(module_path, prev_hash)
	defer cleanup_git_result(&rollback_result)
	if rollback_result.success {
		return strings.clone("rolled back to previous commit")
	}
	if rollback_result.message != "" {
		message := strings.clone(fmt.tprintf("rollback failed: %s", rollback_result.message))
		return message
	}
	return strings.clone("rollback failed")
}

format_update_success :: proc(module_name: string) -> string {
	message := strings.clone(fmt.tprintf("Module '%s' updated successfully.", module_name))
	defer delete(message)
	return errors.format_success("Update complete", message)
}

format_update_line :: proc(module_name: string, result: ^Update_Result) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "%s %s", colors.success_symbol(), module_name)

	if result != nil && result.old_version != "" && result.new_version != "" {
		fmt.sbprintf(&builder, ": %s \u2192 %s", result.old_version, result.new_version)
	}

	if result != nil {
		stats := Update_Stats{
			commits_pulled = result.commits_pulled,
			files_changed = result.files_changed,
		}
		stats_text := format_update_stats(stats)
		defer delete(stats_text)
		if stats_text != "" {
			fmt.sbprintf(&builder, " (%s)", stats_text)
		}
	}

	return strings.clone(strings.to_string(builder))
}

format_update_summary :: proc(items: []string, success_count: int, error_count: int, skipped_count: int) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	title := "Update Summary"
	fmt.sbprintf(&builder, "%s\n", colors.bold(title))
	for _ in 0..<len(title) {
		fmt.sbprintf(&builder, "=")
	}
	fmt.sbprintf(&builder, "\n")

	total := success_count + error_count + skipped_count
	fmt.sbprintf(&builder, "Total: %d", total)
	if success_count > 0 {
		fmt.sbprintf(&builder, " | %s %d", colors.success("Updated:"), success_count)
	}
	if error_count > 0 {
		fmt.sbprintf(&builder, " | %s %d", colors.error("Failed:"), error_count)
	}
	if skipped_count > 0 {
		fmt.sbprintf(&builder, " | %s %d", colors.warning("Skipped:"), skipped_count)
	}
	fmt.sbprintf(&builder, "\n\n")

	for item in items {
		fmt.sbprintf(&builder, "  %s\n", item)
	}

	return strings.clone(strings.to_string(builder))
}

format_install_success :: proc(module_name: string) -> string {
	message := strings.clone(fmt.tprintf("Module '%s' installed successfully.\n  Next steps: run 'zephyr load'", module_name))
	defer delete(message)
	return errors.format_success("Installation complete", message)
}

format_manager_validation_error :: proc(result: ^Validation_Result, module_name: string) -> string {
	if result == nil {
		return format_manager_error(.Validation_Failed, "unknown validation error", module_name, "validate")
	}

	switch result.error {
	case .No_Manifest:
		return format_manager_error(.No_Manifest, result.message, module_name, "validate")
	case .Invalid_Manifest:
		return format_manager_error(.Invalid_Manifest, result.message, module_name, "validate")
	case .Platform_Incompatible:
		return format_manager_error(.Platform_Incompatible, result.message, module_name, "validate")
	case .Missing_Files:
		missing_message := build_missing_files_message(result)
		formatted := format_manager_error(.Missing_Files, missing_message, module_name, "validate")
		if missing_message != "" {
			delete(missing_message)
		}
		return formatted
	case .Name_Mismatch:
		return format_manager_error(.Name_Mismatch, result.message, module_name, "validate")
	case .Validation_Failed:
		return format_manager_error(.Validation_Failed, result.message, module_name, "validate")
	case .None:
		return format_manager_error(.Validation_Failed, result.message, module_name, "validate")
	case:
		return format_manager_error(.Validation_Failed, result.message, module_name, "validate")
	}
}

build_missing_files_message :: proc(result: ^Validation_Result) -> string {
	if result == nil || result.missing_files == nil || len(result.missing_files) == 0 {
		return strings.clone("missing load files")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "missing load files: ")
	for file, idx in result.missing_files {
		if idx > 0 {
			fmt.sbprintf(&builder, ", ")
		}
		fmt.sbprintf(&builder, "%s", file)
	}

	return strings.clone(strings.to_string(builder))
}

format_manager_error :: proc(err: Module_Manager_Error, detail: string, module_name: string, operation: string) -> string {
	title := "Error"
	message := detail

	switch err {
	case .Invalid_URL:
		title = "Invalid URL"
	case .Invalid_Module_Name:
		title = "Invalid module name"
	case .Clone_Failed:
		title = "Clone failed"
	case .Fetch_Failed:
		title = "Fetch failed"
	case .Pull_Failed:
		title = "Pull failed"
	case .Rollback_Failed:
		title = "Rollback failed"
	case .Update_Failed:
		title = "Update failed"
	case .No_Manifest:
		title = "Invalid module"
	case .Invalid_Manifest:
		title = "Invalid manifest"
	case .Name_Mismatch:
		title = "Name mismatch"
	case .Platform_Incompatible:
		title = "Platform incompatible"
	case .Missing_Files:
		title = "Missing files"
	case .Already_Exists:
		title = "Module already exists"
	case .Move_Failed:
		title = "Install move failed"
	case .Validation_Failed:
		title = "Validation failed"
	case .Cleanup_Failed:
		title = "Cleanup failed"
	case .Not_Found:
		title = "Not found"
	case .None:
		title = "Error"
	case .Unknown:
		title = "Error"
	case:
		title = "Error"
	}

	ctx := errors.ErrorContext{
		operation   = operation,
		module_name = module_name,
	}

	return errors.format_error(title, message, ctx)
}
