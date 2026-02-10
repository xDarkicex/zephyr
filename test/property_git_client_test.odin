package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/git"

// **Property: Initialization and shutdown**
// **Validates: Requirements 1.1, 1.2**
@(test)
test_property_git_init_shutdown :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		// libgit2 not available in this build; skip validation.
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)

	if init_result.success {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after init")
	} else {
		testing.expect(t, init_result.error != .None, "init failure should set error code")
	}
}

// **Property 2: Clone to temporary directory**
// **Property 3: Clone error handling**
// **Validates: Requirements 1.1, 1.2, 1.3, 4.1**
@(test)
test_property_git_clone_temp_and_errors :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		// libgit2 not available in this build; skip validation.
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for clone tests")
		return
	}

	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after clone tests")
	}

	dir_a := git.create_unique_temp_dir("git_temp")
	dir_b := git.create_unique_temp_dir("git_temp")

	testing.expect(t, dir_a != "", "temp directory should be created")
	testing.expect(t, dir_b != "", "second temp directory should be created")
	testing.expect(t, dir_a != dir_b, "temp directories should be unique")
	testing.expect(t, os.exists(dir_a), "temp directory should exist on disk")
	testing.expect(t, os.exists(dir_b), "second temp directory should exist on disk")

	cleanup_test_directory(dir_a)
	cleanup_test_directory(dir_b)
	if dir_a != "" { delete(dir_a) }
	if dir_b != "" { delete(dir_b) }

	empty_url := git.clone_repository("", "")
	defer git.cleanup_git_result(&empty_url)
	testing.expect(t, !empty_url.success, "empty URL clone should fail")
	testing.expect(t, empty_url.error == .Invalid_URL, "empty URL should return Invalid_URL")

	invalid_url := git.clone_repository("https://invalid.example/does-not-exist.git", "")
	defer git.cleanup_git_result(&invalid_url)
	testing.expect(t, !invalid_url.success, "invalid URL clone should fail")
	testing.expect(t, invalid_url.error != .None, "invalid URL should set error")
}

// **Unit: fetch/pull operations**
// **Validates: Requirements 5.3, 5.4, 5.5**
@(test)
test_git_fetch_pull_local_repo :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for fetch/pull test")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after fetch/pull test")
	}

	temp_dir := setup_test_environment("git_fetch_pull")
	defer teardown_test_environment(temp_dir)

	bare_dir := filepath.join({temp_dir, "origin.git"})
	work_dir := filepath.join({temp_dir, "work"})
	clone_dir := filepath.join({temp_dir, "clone"})
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if work_dir != "" { delete(work_dir) }
		if clone_dir != "" { delete(clone_dir) }
	}

	testing.expect(t, run_git_cmd(fmt.tprintf("git init --bare %q", bare_dir)), "init bare repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git init %q", work_dir)), "init work repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	init_path := filepath.join({work_dir, "init.zsh"})
	content := "name = \"git-test\"\nversion = \"1.0.0\"\n"
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

	clone_result := git.clone_repository(bare_dir, clone_dir)
	defer git.cleanup_git_result(&clone_result)
	testing.expect(t, clone_result.success, "clone repository should succeed")

	manifest_path = filepath.join({work_dir, "module.toml"})
	updated := "name = \"git-test\"\nversion = \"1.0.1\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)updated)
	delete(manifest_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"update\"", work_dir)), "git commit update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push", work_dir)), "git push update")

	fetch_result := git.fetch_repository(clone_dir)
	defer git.cleanup_git_result(&fetch_result)
	testing.expect(t, fetch_result.success, "fetch should succeed")

	pull_result := git.pull_repository(clone_dir)
	defer git.cleanup_git_result(&pull_result)
	testing.expect(t, pull_result.success, "pull should succeed")

	manifest_path = filepath.join({clone_dir, "module.toml"})
	data, ok := os.read_entire_file(manifest_path)
	testing.expect(t, ok, "read updated manifest")
	if ok {
		contents := string(data)
		testing.expect(t, strings.contains(contents, "version = \"1.0.1\""), "pull should update working tree")
	}
	delete(manifest_path)
	delete(data)
}

// **Security: Hook execution is blocked during controlled checkout**
@(test)
test_git_hooks_not_executed_on_checkout :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for hook execution test")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after hook execution test")
	}

	temp_dir := setup_test_environment("git_hook_execution")
	defer teardown_test_environment(temp_dir)

	bare_dir := filepath.join({temp_dir, "origin.git"})
	work_dir := filepath.join({temp_dir, "work"})
	clone_dir := filepath.join({temp_dir, "clone"})
	hook_marker := filepath.join({temp_dir, "HOOK_EXECUTED_BAD"})
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if work_dir != "" { delete(work_dir) }
		if clone_dir != "" { delete(clone_dir) }
		if hook_marker != "" { delete(hook_marker) }
	}

	testing.expect(t, run_git_cmd(fmt.tprintf("git init --bare %q", bare_dir)), "init bare repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git init %q", work_dir)), "init work repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	init_path := filepath.join({work_dir, "init.zsh"})
	content := "name = \"git-hook-test\"\nversion = \"1.0.0\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)content)
	init_content := "echo \"safe\"\n"
	os.write_entire_file(init_path, transmute([]u8)init_content)
	delete(manifest_path)
	delete(init_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add initial")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"init\"", work_dir)), "git commit initial")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q branch -M main", work_dir)), "git set main")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q remote add origin %q", work_dir, bare_dir)), "git remote add")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push -u origin main", work_dir)), "git push initial")

	clone_result := git.clone_repository_no_checkout(bare_dir, clone_dir)
	defer git.cleanup_git_result(&clone_result)
	testing.expect(t, clone_result.success, "clone without checkout should succeed")

	hooks_dir := filepath.join({clone_dir, ".git", "hooks"})
	os.make_directory(hooks_dir, 0o755)
	hook_path := filepath.join({hooks_dir, "post-checkout"})
	hook_script := fmt.tprintf("#!/bin/sh\ntouch %s\n", hook_marker)
	os.write_entire_file(hook_path, transmute([]u8)hook_script)
	_ = run_git_cmd(fmt.tprintf("chmod +x %q", hook_path))
	delete(hooks_dir)
	delete(hook_path)
	delete(hook_script)

	os.remove(hook_marker)

	checkout_result := git.checkout_repository_head(clone_dir)
	defer git.cleanup_git_result(&checkout_result)
	testing.expect(t, checkout_result.success, "checkout should succeed")

	testing.expect(t, !os.exists(hook_marker), "hook should not execute during checkout")
}

run_git_cmd :: proc(command: string) -> bool {
	return run_shell_command(command)
}
