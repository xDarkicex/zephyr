package git

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "../security"
// Temporary installation pipeline for cloning and moving modules atomically.
// Ownership: Temp_Install_Result strings are owned by the caller.

// Temp_Install_Result captures the temp/final paths and any error message.
Temp_Install_Result :: struct {
	success:       bool,
	temp_path:     string,
	final_path:    string,
	error_message: string,
}

// cleanup_temp_install_result frees any owned strings in a Temp_Install_Result.
cleanup_temp_install_result :: proc(result: ^Temp_Install_Result) {
	if result == nil do return

	if result.temp_path != "" {
		delete(result.temp_path)
		result.temp_path = ""
	}
	if result.final_path != "" {
		delete(result.final_path)
		result.final_path = ""
	}
	if result.error_message != "" {
		delete(result.error_message)
		result.error_message = ""
	}
	result.success = false
}

// install_to_temp clones a repository into a temporary directory.
install_to_temp :: proc(url: string, expected_name: string) -> Temp_Install_Result {
	result := Temp_Install_Result{}
	_ = expected_name

	if url == "" {
		result.error_message = strings.clone("empty URL")
		return result
	}

	temp_dir := create_temp_install_dir("zephyr-install")
	if temp_dir == "" {
		result.error_message = strings.clone("failed to create temp directory")
		return result
	}
	result.temp_path = temp_dir

	clone_result := clone_repository_no_checkout(url, temp_dir)
	defer cleanup_git_result(&clone_result)
	if !clone_result.success {
		if clone_result.message != "" {
			result.error_message = strings.clone(clone_result.message)
		} else {
			result.error_message = strings.clone("clone failed")
		}
		cleanup_temp(temp_dir)
		delete(temp_dir)
		result.temp_path = ""
		return result
	}

	checkout_result := checkout_repository_head(temp_dir)
	defer cleanup_git_result(&checkout_result)
	if !checkout_result.success {
		if checkout_result.message != "" {
			result.error_message = strings.clone(checkout_result.message)
		} else {
			result.error_message = strings.clone("checkout failed")
		}
		cleanup_temp(temp_dir)
		delete(temp_dir)
		result.temp_path = ""
		return result
	}

	result.success = true
	return result
}

scan_source :: proc(url: string) -> (security.Scan_Result, string, string) {
	result := security.Scan_Result{success = false}
	if url == "" {
		result.error_message = strings.clone("empty URL")
		return result, "", ""
	}

	temp_dir := create_temp_install_dir("zephyr-scan")
	if temp_dir == "" {
		result.error_message = strings.clone("failed to create scan directory")
		return result, "", ""
	}

	clone_result := clone_repository_no_checkout(url, temp_dir)
	defer cleanup_git_result(&clone_result)
	if !clone_result.success {
		if clone_result.message != "" {
			result.error_message = strings.clone(clone_result.message)
		} else {
			result.error_message = strings.clone("clone failed")
		}
		cleanup_temp(temp_dir)
		delete(temp_dir)
		return result, "", ""
	}

	checkout_result := checkout_repository_head(temp_dir)
	defer cleanup_git_result(&checkout_result)
	if !checkout_result.success {
		if checkout_result.message != "" {
			result.error_message = strings.clone(checkout_result.message)
		} else {
			result.error_message = strings.clone("checkout failed")
		}
		cleanup_temp(temp_dir)
		delete(temp_dir)
		return result, "", ""
	}

	commit := ""
	hash, hash_result := get_head_commit_hash(temp_dir)
	defer cleanup_git_result(&hash_result)
	if hash_result.success && hash != "" {
		commit = hash
	} else {
		if hash != "" {
			delete(hash)
		}
	}

	scan_options := security.Scan_Options{}
	scan_result := security.scan_module(temp_dir, scan_options)
	return scan_result, temp_dir, commit
}

// move_to_final moves a temp install into the modules directory.
move_to_final :: proc(temp_path: string, modules_dir: string, module_name: string, force: bool) -> (bool, string) {
	if temp_path == "" {
		return false, strings.clone("empty temp path")
	}
	if modules_dir == "" {
		return false, strings.clone("empty modules directory")
	}
	if module_name == "" {
		return false, strings.clone("empty module name")
	}

	if !os.exists(modules_dir) {
		os.make_directory(modules_dir, 0o755)
	}

	final_path := filepath.join({modules_dir, module_name})
	if final_path == "" {
		return false, strings.clone("failed to create final path")
	}

	if os.exists(final_path) {
		if !force {
			delete(final_path)
			return false, strings.clone("module already exists")
		}
		cleanup_temp(final_path)
	}

	ok := os.rename(temp_path, final_path)
	if !ok {
		delete(final_path)
		return false, strings.clone("failed to move module into place")
	}

	return true, final_path
}

// cleanup_temp removes a temporary directory and its contents.
cleanup_temp :: proc(temp_path: string) {
	if temp_path == "" do return
	if !os.exists(temp_path) do return
	remove_directory_recursive(temp_path)
}

// create_temp_install_dir creates a unique temp directory under TMPDIR.
create_temp_install_dir :: proc(prefix: string) -> string {
	return create_temp_install_dir_with_base(prefix, "")
}

// create_temp_install_dir_with_base creates a temp dir under a base override.
create_temp_install_dir_with_base :: proc(prefix: string, base_override: string) -> string {
	base := ""
	if base_override != "" {
		base = strings.clone(base_override)
	} else {
		base_env := os.get_env("TMPDIR")
		if base_env == "" {
			delete(base_env)
			base = strings.clone("/tmp")
		} else {
			base = strings.clone(base_env)
			delete(base_env)
		}
	}
	defer delete(base)

	if !os.exists(base) {
		return ""
	}

	for attempt in 0..<5 {
		timestamp := cast(u64)time.now()._nsec
		random_part := timestamp + (cast(u64)(attempt + 1) * 0x9e3779b97f4a7c15)

		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)
		fmt.sbprintf(&builder, "%s_%d_%d", prefix, timestamp, random_part)
		name := strings.clone(strings.to_string(builder))
		defer delete(name)

		path := filepath.join({base, name})
		if path == "" do continue

		if os.exists(path) {
			delete(path)
			continue
		}

		os.make_directory(path, 0o755)
		if os.exists(path) {
			return path
		}
		delete(path)
	}

	return ""
}

// remove_directory_recursive removes a directory tree recursively.
remove_directory_recursive :: proc(dir_path: string) {
	if !os.exists(dir_path) do return

	handle, open_err := os.open(dir_path)
	if open_err != os.ERROR_NONE {
		return
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		return
	}
	defer os.file_info_slice_delete(entries)

	for entry in entries {
		full_path := filepath.join({dir_path, entry.name})
		defer delete(full_path)

		if entry.is_dir {
			remove_directory_recursive(full_path)
		} else {
			os.remove(full_path)
		}
	}

	os.remove(dir_path)
}
