package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/git"

// **Property 11: Installation pipeline sequence**
// **Validates: Requirements 1.4, 4.1, 4.2, 4.3, 4.8**
@(test)
test_property_git_temp_install_pipeline :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for temp installer tests")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after temp installer tests")
	}

	temp_dir := setup_test_environment("git_temp_install_pipeline")
	defer teardown_test_environment(temp_dir)

	bare_dir := filepath.join({temp_dir, "origin.git"})
	work_dir := filepath.join({temp_dir, "work"})
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if work_dir != "" { delete(work_dir) }
	}

	testing.expect(t, run_git_cmd(fmt.tprintf("git init --bare %q", bare_dir)), "init bare repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git init %q", work_dir)), "init work repo")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	init_path := filepath.join({work_dir, "init.zsh"})
	content := "name = \"git-temp\"\nversion = \"1.0.0\"\n"
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

	install_result := git.install_to_temp(bare_dir, "git-temp")
	defer git.cleanup_temp_install_result(&install_result)
	if install_result.error_message != "" {
		testing.expect(t, install_result.success, install_result.error_message)
	}
	testing.expect(t, install_result.success, "install_to_temp should succeed")
	if install_result.temp_path != "" {
		testing.expect(t, os.exists(install_result.temp_path), "temp path should exist")
		manifest_path = filepath.join({install_result.temp_path, "module.toml"})
		data, ok := os.read_entire_file(manifest_path)
		testing.expect(t, ok, "module.toml should exist in temp clone")
		if ok {
			contents := string(data)
			testing.expect(t, strings.contains(contents, "name = \"git-temp\""), "manifest should contain module name")
			delete(data)
		}
		delete(manifest_path)
	}

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	ok, final_path := git.move_to_final(install_result.temp_path, modules_dir, "git-temp", false)
	if final_path != "" {
		defer delete(final_path)
	}
	testing.expect(t, ok, "move_to_final should succeed")
	if ok && final_path != "" {
		testing.expect(t, os.exists(final_path), "final path should exist after move")
		testing.expect(t, !os.exists(install_result.temp_path), "temp path should not exist after move")
		cleanup_test_directory(final_path)
	}
	delete(modules_dir)
}

// **Property 15: Installation cleanup on failure**
// **Validates: Requirements 4.8**
@(test)
test_property_git_temp_install_cleanup_on_failure :: proc(t: ^testing.T) {
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

	install_result := git.install_to_temp("https://invalid.example/does-not-exist.git", "bad")
	defer git.cleanup_temp_install_result(&install_result)
	testing.expect(t, !install_result.success, "install_to_temp should fail for invalid URL")
	if install_result.temp_path != "" {
		testing.expect(t, !os.exists(install_result.temp_path), "temp path should be cleaned on failure")
	}
}

// **Unit: temp installer edge cases**
// **Validates: Requirements 4.8**
@(test)
test_git_temp_installer_edge_cases :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	// temp directory creation failure
	temp_dir := setup_test_environment("git_temp_installer_edge")
	defer teardown_test_environment(temp_dir)

	base_file := filepath.join({temp_dir, "base_file"})
	data := "data"
	os.write_entire_file(base_file, transmute([]u8)data)
	invalid_temp := git.create_temp_install_dir_with_base("zephyr-install", base_file)
	if invalid_temp != "" {
		cleanup_test_directory(invalid_temp)
		delete(invalid_temp)
	}
	testing.expect(t, invalid_temp == "", "temp dir creation should fail when base is a file")
	delete(base_file)

	// move operation failure
	source_dir := filepath.join({temp_dir, "source"})
	os.make_directory(source_dir, 0o755)
	modules_file := filepath.join({temp_dir, "modules"})
	os.write_entire_file(modules_file, transmute([]u8)data)

	ok, err := git.move_to_final(source_dir, modules_file, "module", false)
	if err != "" {
		delete(err)
	}
	testing.expect(t, !ok, "move_to_final should fail when modules_dir is a file")
	cleanup_test_directory(source_dir)
	delete(source_dir)
	delete(modules_file)
}

// run_git_cmd and cstring_buffer are provided in property_git_client_test.odin
