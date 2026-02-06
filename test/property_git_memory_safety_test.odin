package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

import "../src/git"

// **Property: Memory safety in success/error paths**
// **Validates: Requirements 10.7**
@(test)
test_property_git_memory_safety_paths :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for memory safety test")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after memory safety test")
	}

	temp_dir := setup_test_environment("git_memory_safety")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-mem-module", "mem-module", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true}
	ok, msg := git.install_module(bare_dir, opts)
	testing.expect(t, ok, fmt.tprintf("install should succeed: %s", msg))
	if msg != "" { delete(msg) }

	update_bare_repo_version(t, temp_dir, bare_dir, "mem-module", "1.0.1")
	update_ok, update_msg := git.update_module("mem-module", git.Manager_Options{})
	testing.expect(t, update_ok, fmt.tprintf("update should succeed: %s", update_msg))
	if update_msg != "" { delete(update_msg) }

	uninstall_ok, uninstall_msg := git.uninstall_module("mem-module", git.Manager_Options{confirm = true})
	testing.expect(t, uninstall_ok, fmt.tprintf("uninstall should succeed: %s", uninstall_msg))
	if uninstall_msg != "" { delete(uninstall_msg) }

	// Error path: invalid install source should return a message we free.
	err_ok, err_msg := git.install_module("", git.Manager_Options{})
	testing.expect(t, !err_ok, "empty install source should fail")
	if err_msg != "" { delete(err_msg) }
}
