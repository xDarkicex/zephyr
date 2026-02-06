package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/git"

// **Property 16: Single module update**
// **Property 18: Update pipeline sequence**
// **Validates: Requirements 5.1, 5.3, 5.5, 5.6, 5.8**
@(test)
test_property_git_update_single_module :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for update tests")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after update tests")
	}

	temp_dir := setup_test_environment("git_update_single")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-update-module", "update-module", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	success, message := git.install_module(bare_dir, opts)
	testing.expect(t, success, fmt.tprintf("install should succeed: %s", message))
	if message != "" {
		delete(message)
	}

	update_bare_repo_version(t, temp_dir, bare_dir, "update-module", "1.0.1")

	update_ok, update_message := git.update_module("update-module", git.Manager_Options{})
	testing.expect(t, update_ok, fmt.tprintf("update should succeed: %s", update_message))
	if update_message != "" {
		normalized := normalize_output(update_message)
		lower := strings.to_lower(normalized)
		testing.expect(t, strings.contains(lower, "update complete"), "update success output should mention update complete")
		delete(lower)
		delete(normalized)
		delete(update_message)
	}

	manifest_path := filepath.join({modules_dir, "update-module", "module.toml"})
	data, ok := os.read_entire_file(manifest_path)
	testing.expect(t, ok, "read updated manifest")
	if ok {
		contents := string(data)
		testing.expect(t, strings.contains(contents, "version = \"1.0.1\""), "module should be updated after pull")
	}
	delete(manifest_path)
	delete(data)
}

// **Property 17: All modules update**
// **Validates: Requirements 5.2, 5.9**
@(test)
test_property_git_update_all_modules :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("git_update_all")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_a, name_a := create_bare_repo(t, temp_dir, "zephyr-update-a", "update-a", "1.0.0")
	bare_b, name_b := create_bare_repo(t, temp_dir, "zephyr-update-b", "update-b", "1.0.0")
	defer {
		if bare_a != "" { delete(bare_a) }
		if bare_b != "" { delete(bare_b) }
		if name_a != "" { delete(name_a) }
		if name_b != "" { delete(name_b) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok_a, msg_a := git.install_module(bare_a, opts)
	ok_b, msg_b := git.install_module(bare_b, opts)
	testing.expect(t, ok_a && ok_b, "install should succeed for both modules")
	if msg_a != "" {
		delete(msg_a)
	}
	if msg_b != "" {
		delete(msg_b)
	}

	update_bare_repo_version(t, temp_dir, bare_a, "update-a", "1.0.1")
	update_bare_repo_version(t, temp_dir, bare_b, "update-b", "1.0.2")

	update_ok, summary := git.update_module("", git.Manager_Options{})
	testing.expect(t, update_ok, fmt.tprintf("update all should succeed: %s", summary))
	if summary != "" { delete(summary) }

	assert_module_version(t, modules_dir, "update-a", "1.0.1")
	assert_module_version(t, modules_dir, "update-b", "1.0.2")
}

// **Property 19: Fetch failure error**
// **Validates: Requirements 5.3, 5.4**
@(test)
test_property_git_update_fetch_failure :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("git_update_fetch_fail")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-update-fetch", "update-fetch", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok, msg := git.install_module(bare_dir, opts)
	testing.expect(t, ok, "install should succeed")
	if msg != "" {
		delete(msg)
	}

	module_path := filepath.join({modules_dir, "update-fetch"})
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q remote remove origin", module_path)), "remove origin remote")

	update_ok, message := git.update_module("update-fetch", git.Manager_Options{})
	testing.expect(t, !update_ok, "update should fail when fetch fails")
	if message != "" {
		normalized := normalize_output(message)
		lower := strings.to_lower(normalized)
		testing.expect(t, strings.contains(lower, "fetch"), "error should mention fetch failure")
		delete(lower)
		delete(normalized)
		delete(message)
	}

	delete(module_path)
}

// **Property 20: Update rollback on validation failure**
// **Validates: Requirements 5.6, 5.7**
@(test)
test_property_git_update_rollback_on_validation_failure :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("git_update_rollback")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-update-rollback", "update-rollback", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok, msg := git.install_module(bare_dir, opts)
	testing.expect(t, ok, "install should succeed")
	if msg != "" {
		delete(msg)
	}

	update_bare_repo_remove_file(t, temp_dir, bare_dir)

	update_ok, message := git.update_module("update-rollback", git.Manager_Options{})
	testing.expect(t, !update_ok, "update should fail when validation fails")
	if message != "" {
		normalized := normalize_output(message)
		lower := strings.to_lower(normalized)
		testing.expect(t, strings.contains(lower, "rollback"), "error should mention rollback")
		delete(lower)
		delete(normalized)
		delete(message)
	}

	assert_module_version(t, modules_dir, "update-rollback", "1.0.0")
}

// **Property 21: Update success output**
// **Property 22: Batch update resilience**
// **Property 23: Batch update summary**
// **Validates: Requirements 5.8, 5.9, 5.10**
@(test)
test_property_git_update_batch_summary :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("git_update_summary")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_good, name_good := create_bare_repo(t, temp_dir, "zephyr-update-good", "update-good", "1.0.0")
	bare_bad, name_bad := create_bare_repo(t, temp_dir, "zephyr-update-bad", "update-bad", "1.0.0")
	defer {
		if bare_good != "" { delete(bare_good) }
		if bare_bad != "" { delete(bare_bad) }
		if name_good != "" { delete(name_good) }
		if name_bad != "" { delete(name_bad) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok_good, msg_good := git.install_module(bare_good, opts)
	ok_bad, msg_bad := git.install_module(bare_bad, opts)
	testing.expect(t, ok_good && ok_bad, "install should succeed for both modules")
	if msg_good != "" {
		delete(msg_good)
	}
	if msg_bad != "" {
		delete(msg_bad)
	}

	update_bare_repo_version(t, temp_dir, bare_good, "update-good", "1.0.1")

	module_path := filepath.join({modules_dir, "update-bad"})
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q remote remove origin", module_path)), "remove origin remote")
	delete(module_path)

	update_ok, summary := git.update_module("", git.Manager_Options{})
	testing.expect(t, !update_ok, "batch update should report failure when one module fails")
	if summary != "" {
		normalized := normalize_output(summary)
		lower := strings.to_lower(normalized)
		testing.expect(t, strings.contains(lower, "update summary"), "summary should include header")
		testing.expect(t, strings.contains(lower, "success"), "summary should include success count")
		testing.expect(t, strings.contains(lower, "errors"), "summary should include error count")
		delete(lower)
		delete(normalized)
		delete(summary)
	}

	assert_module_version(t, modules_dir, "update-good", "1.0.1")
}

update_bare_repo_version :: proc(t: ^testing.T, temp_dir: string, bare_dir: string, module_name: string, version: string) {
	work_dir := filepath.join({temp_dir, fmt.tprintf("%s-update-%d", module_name, time.now()._nsec)})
	testing.expect(t, run_git_cmd(fmt.tprintf("git clone %q %q", bare_dir, work_dir)), "clone for update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	manifest_path := filepath.join({work_dir, "module.toml"})
	content := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"%s\"\n\n[load]\nfiles = [\"init.zsh\"]\n", module_name, version)
	os.write_entire_file(manifest_path, transmute([]u8)content)
	delete(manifest_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"update\"", work_dir)), "git commit update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push", work_dir)), "git push update")

	cleanup_test_directory(work_dir)
	delete(work_dir)
}

update_bare_repo_remove_file :: proc(t: ^testing.T, temp_dir: string, bare_dir: string) {
	work_dir := filepath.join({temp_dir, fmt.tprintf("update-remove-%d", time.now()._nsec)})
	testing.expect(t, run_git_cmd(fmt.tprintf("git clone %q %q", bare_dir, work_dir)), "clone for invalid update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", work_dir)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", work_dir)), "git config name")

	init_path := filepath.join({work_dir, "init.zsh"})
	os.remove(init_path)
	delete(init_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", work_dir)), "git add invalid update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"invalid update\"", work_dir)), "git commit invalid update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push", work_dir)), "git push invalid update")

	cleanup_test_directory(work_dir)
	delete(work_dir)
}

assert_module_version :: proc(t: ^testing.T, modules_dir: string, module_name: string, version: string) {
	manifest_path := filepath.join({modules_dir, module_name, "module.toml"})
	data, ok := os.read_entire_file(manifest_path)
	testing.expect(t, ok, fmt.tprintf("read manifest for %s", module_name))
	if ok {
		contents := string(data)
		testing.expect(t, strings.contains(contents, fmt.tprintf("version = \"%s\"", version)),
			fmt.tprintf("module %s should be version %s", module_name, version))
	}
	delete(manifest_path)
	delete(data)
}

normalize_output :: proc(input: string) -> string {
	if input == "" {
		return strings.clone("")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	i := 0
	for i < len(input) {
		c := input[i]

		if c == 0 {
			i += 1
			continue
		}

		if c == 0x1b { // ESC
			i += 1
			if i < len(input) && input[i] == '[' {
				i += 1
				for i < len(input) && input[i] != 'm' {
					i += 1
				}
				if i < len(input) {
					i += 1
				}
				continue
			}
		}

		if c < 0x20 {
			i += 1
			continue
		}

		fmt.sbprintf(&builder, "%c", c)
		i += 1
	}

	return strings.clone(strings.to_string(builder))
}
