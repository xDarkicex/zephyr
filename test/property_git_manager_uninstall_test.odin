package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/git"

// **Property 24: Uninstall existence check**
// **Property 26: Complete module removal**
// **Property 27: Uninstall success output**
// **Validates: Requirements 6.1, 6.3, 6.4**
@(test)
test_property_git_uninstall_success :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_uninstall_success")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	module_path := create_test_module_dir(modules_dir, "uninstall-me")
	defer {
		if module_path != "" {
			cleanup_test_directory(module_path)
			delete(module_path)
		}
	}

	ok, message := git.uninstall_module("uninstall-me", git.Manager_Options{})
	testing.expect(t, ok, fmt.tprintf("uninstall should succeed: %s", message))
	testing.expect(t, !os.exists(module_path), "module directory should be removed")

	if message != "" {
		lower := strings.to_lower(message)
		testing.expect(t, strings.contains(lower, "uninstall complete"), "success output should mention uninstall complete")
		delete(lower)
		delete(message)
	}
}

// **Property 25: Uninstall non-existent error**
// **Validates: Requirements 6.1, 6.2**
@(test)
test_property_git_uninstall_nonexistent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_uninstall_missing")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	ok, message := git.uninstall_module("missing-module", git.Manager_Options{})
	testing.expect(t, !ok, "uninstall should fail for missing module")
	if message != "" {
		lower := strings.to_lower(message)
		testing.expect(t, strings.contains(lower, "not found"), "error should mention not found")
		delete(lower)
		delete(message)
	}
}

// **Property 28: Uninstall failure error**
// **Validates: Requirements 6.5**
@(test)
test_property_git_uninstall_failure_error :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_uninstall_failure")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	module_path := create_test_module_dir(modules_dir, "uninstall-fail")
	defer {
		if module_path != "" {
			run_git_cmd(fmt.tprintf("chmod u+w %q", module_path))
			cleanup_test_directory(module_path)
			delete(module_path)
		}
	}

	// Remove write permission from module dir so cleanup fails.
	_ = run_git_cmd(fmt.tprintf("chmod u-w %q", module_path))

	ok, message := git.uninstall_module("uninstall-fail", git.Manager_Options{})
	testing.expect(t, !ok, "uninstall should fail when removal fails")
	if message != "" {
		lower := strings.to_lower(message)
		testing.expect(t, strings.contains(lower, "failed"), "error should mention failure")
		delete(lower)
		delete(message)
	}
}

// **Property 29: Dependency checking**
// **Validates: Requirements 6.6, 6.7**
@(test)
test_property_git_uninstall_dependency_checking :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_uninstall_deps")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	target_path := create_test_module_dir(modules_dir, "target-module")
	dependent_path := create_dependent_module_dir(modules_dir, "dependent-module", "target-module")
	defer {
		if dependent_path != "" {
			cleanup_test_directory(dependent_path)
			delete(dependent_path)
		}
		if target_path != "" {
			cleanup_test_directory(target_path)
			delete(target_path)
		}
	}

	opts := git.Manager_Options{check_dependencies = true, confirm = false}
	ok, message := git.uninstall_module("target-module", opts)
	testing.expect(t, !ok, "uninstall should fail when dependents exist")
	if message != "" {
		lower := strings.to_lower(message)
		testing.expect(t, strings.contains(lower, "dependents"), "error should mention dependents")
		delete(lower)
		delete(message)
	}

	opts.confirm = true
	ok, message = git.uninstall_module("target-module", opts)
	testing.expect(t, ok, fmt.tprintf("uninstall should succeed with confirm: %s", message))
	if message != "" { delete(message) }
}

create_test_module_dir :: proc(modules_dir: string, name: string) -> string {
	module_path := filepath.join({modules_dir, name})
	if module_path == "" {
		return ""
	}
	os.make_directory(module_path, 0o755)

	manifest_path := filepath.join({module_path, "module.toml"})
	init_path := filepath.join({module_path, "init.zsh"})
	content := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"1.0.0\"\n\n[load]\nfiles = [\"init.zsh\"]\n", name)
	init_content := "echo \"ok\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)content)
	os.write_entire_file(init_path, transmute([]u8)init_content)

	delete(manifest_path)
	delete(init_path)
	return module_path
}

create_dependent_module_dir :: proc(modules_dir: string, name: string, dependency: string) -> string {
	module_path := filepath.join({modules_dir, name})
	if module_path == "" {
		return ""
	}
	os.make_directory(module_path, 0o755)

	manifest_path := filepath.join({module_path, "module.toml"})
	init_path := filepath.join({module_path, "init.zsh"})
	content := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"1.0.0\"\n\n[dependencies]\nrequired = [\"%s\"]\n\n[load]\nfiles = [\"init.zsh\"]\n", name, dependency)
	init_content := "echo \"ok\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)content)
	os.write_entire_file(init_path, transmute([]u8)init_content)

	delete(manifest_path)
	delete(init_path)
	return module_path
}
