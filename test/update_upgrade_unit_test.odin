package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/git"

@(test)
test_update_git_operations :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed")
	}

	temp_dir := setup_test_environment("update_upgrader_git_ops")
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
	manifest_content := "name = \"update-test\"\nversion = \"1.0.0\"\n"
	init_content := "echo \"hello\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)manifest_content)
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
	updated_content := "name = \"update-test\"\nversion = \"1.0.1\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)updated_content)
	delete(manifest_path)
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"update\"", work_dir)), "git commit update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push", work_dir)), "git push update")

	fetch_result := git.fetch_origin(clone_dir)
	defer git.cleanup_git_result(&fetch_result)
	testing.expect(t, fetch_result.success, "fetch should succeed")

	pull_result := git.pull_origin(clone_dir, "main")
	defer git.cleanup_git_result(&pull_result)
	testing.expect(t, pull_result.success, "pull should succeed")

	current_hash, hash_result := git.get_current_commit(clone_dir)
	defer git.cleanup_git_result(&hash_result)
	defer delete(current_hash)
	testing.expect(t, hash_result.success, "get_current_commit should succeed")
	testing.expect(t, len(current_hash) > 0, "commit hash should be returned")
}

@(test)
test_update_branch_detection :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed")
	}

	temp_dir := setup_test_environment("update_branch_detect")
	defer teardown_test_environment(temp_dir)

	repo_dir := filepath.join({temp_dir, "repo"})
	defer if repo_dir != "" { delete(repo_dir) }
	testing.expect(t, run_git_cmd(fmt.tprintf("git init %q", repo_dir)), "git init repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", repo_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", repo_dir)), "git config name")

	file_path := filepath.join({repo_dir, "module.toml"})
	file_content := "name = \"branch-test\"\nversion = \"1.0.0\"\n"
	os.write_entire_file(file_path, transmute([]u8)file_content)
	delete(file_path)
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", repo_dir)), "git add")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"init\"", repo_dir)), "git commit")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q branch -M main", repo_dir)), "git set main")

	branch, branch_result := git.get_current_branch(repo_dir)
	defer git.cleanup_git_result(&branch_result)
	defer delete(branch)
	testing.expect(t, branch_result.success, "get_current_branch should succeed")
	testing.expect(t, branch == "main", "branch should be main")
}
