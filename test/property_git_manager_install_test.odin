package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/git"

// **Property 12: Duplicate module error**
// **Validates: Requirements 4.4, 7.6**
@(test)
test_property_git_install_duplicate_module :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for install tests")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after install tests")
	}

	temp_dir := setup_test_environment("git_install_duplicate")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-test-module", "test-module", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	existing_path := filepath.join({modules_dir, "test-module"})
	os.make_directory(existing_path, 0o755)
	defer {
		cleanup_test_directory(existing_path)
		delete(existing_path)
	}

	url := strings.clone(bare_dir)
	defer delete(url)

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	success, message := git.install_module(url, opts)
	testing.expect(t, !success, fmt.tprintf("install should fail when module already exists: %s", message))
	if message != "" {
		lower := strings.to_lower(message)
		defer delete(lower)
		testing.expect(t, strings.contains(lower, "already exists"), fmt.tprintf("error should mention module already exists: %s", message))
		delete(message)
	}
}

// **Property 13: Force reinstallation**
// **Validates: Requirements 4.5**
@(test)
test_property_git_install_force_reinstall :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
	}

	temp_dir := setup_test_environment("git_install_force")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-force-module", "force-module", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	existing_path := filepath.join({modules_dir, "force-module"})
	os.make_directory(existing_path, 0o755)
	manifest_path := filepath.join({existing_path, "module.toml"})
	existing_manifest := "[module]\nname = \"force-module\"\nversion = \"0.1.0\"\n\n[load]\nfiles = [\"init.zsh\"]\n"
	os.write_entire_file(manifest_path, transmute([]u8)existing_manifest)
	delete(manifest_path)
	defer {
		cleanup_test_directory(existing_path)
		delete(existing_path)
	}

	url := strings.clone(bare_dir)
	defer delete(url)

	opts := git.Manager_Options{verbose = false, force = true, confirm = false, allow_local = true}
	success, message := git.install_module(url, opts)
	testing.expect(t, success, fmt.tprintf("install should succeed with force flag: %s", message))
	if message != "" {
		delete(message)
	}

	manifest_path = filepath.join({existing_path, "module.toml"})
	data, ok := os.read_entire_file(manifest_path)
	if ok {
		contents := string(data)
		defer delete(data)
		testing.expect(t, strings.contains(contents, "version = \"1.0.0\""), "force reinstall should replace module contents")
	}
	delete(manifest_path)
}

// **Property 14: Installation success output**
// **Validates: Requirements 4.6, 4.7, 8.4**
@(test)
test_property_git_install_success_output :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
	}

	temp_dir := setup_test_environment("git_install_success")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-success-module", "success-module", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	url := strings.clone(bare_dir)
	defer delete(url)

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	success, message := git.install_module(url, opts)
	testing.expect(t, success, fmt.tprintf("install should succeed: %s", message))
	if message != "" {
		lower := strings.to_lower(message)
		defer delete(lower)
		testing.expect(t, strings.contains(lower, "installed successfully"), fmt.tprintf("success output should mention installed successfully: %s", message))
		testing.expect(t, strings.contains(lower, "zephyr load"), fmt.tprintf("success output should include next steps: %s", message))
		delete(message)
	}

	installed_path := filepath.join({modules_dir, "success-module"})
	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}

create_bare_repo :: proc(t: ^testing.T, base_dir: string, repo_name: string, module_name: string, version: string) -> (string, string) {
	bare_dir := filepath.join({base_dir, fmt.tprintf("%s.git", repo_name)})
	work_dir := filepath.join({base_dir, fmt.tprintf("%s-work", repo_name)})

	testing.expect(t, run_git_cmd(fmt.tprintf("git init --bare %q", bare_dir)), "init bare repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git init %q", work_dir)), "init work repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	init_path := filepath.join({work_dir, "init.zsh"})
	content := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"%s\"\n\n[load]\nfiles = [\"init.zsh\"]\n", module_name, version)
	os.write_entire_file(manifest_path, transmute([]u8)content)
	init_content := "echo \"hello\"\n"
	os.write_entire_file(init_path, transmute([]u8)init_content)
	delete(manifest_path)
	delete(init_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add initial")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"init\"", work_dir)), "git commit initial")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q branch -M main", work_dir)), "git set main")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q remote add origin %q", work_dir, bare_dir)), "git remote add")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push -u origin main", work_dir)), "git push initial")

	cleanup_test_directory(work_dir)
	delete(work_dir)

	return bare_dir, strings.clone(module_name)
}

restore_modules_env :: proc(original_env: string) {
	if len(original_env) > 0 {
		os.set_env("ZSH_MODULES_DIR", original_env)
	} else {
		os.unset_env("ZSH_MODULES_DIR")
	}
	delete(original_env)
}
