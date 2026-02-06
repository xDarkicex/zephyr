package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

import "../src/git"
import "../src/security"

prompt_call_count: int

counting_reader :: proc() -> string {
	prompt_call_count += 1
	return "no"
}

// **Property 4: Critical Pattern Blocking**
// **Validates: Requirements 2.6**
@(test)
test_property_security_critical_blocks_install :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for critical blocking test")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after critical blocking test")
	}

	temp_dir := setup_test_environment("security_critical_block")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-critical-block",
		"critical-block",
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	ok, msg := git.install_module(bare_dir, git.Manager_Options{allow_local = true})
	testing.expect(t, !ok, fmt.tprintf("install should be blocked by critical pattern: %s", msg))
	if msg != "" {
		delete(msg)
	}

	installed_path := filepath.join({modules_dir, "critical-block"})
	testing.expect(t, !os.exists(installed_path), "blocked module should not be installed")
	delete(installed_path)
}

// **Property 6: Warning Display and Prompt**
// **Validates: Requirements 3.6, 3.7**
@(test)
test_property_security_warning_prompt_invoked :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_warning_prompt")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-warning-prompt",
		"warning-prompt",
		"1.0.0",
		"sudo ls -la\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	prompt_call_count = 0
	security.set_input_reader_override(counting_reader)
	defer security.clear_input_reader_override()

	ok, msg := git.install_module(bare_dir, git.Manager_Options{allow_local = true})
	testing.expect(t, !ok, fmt.tprintf("install should be cancelled by prompt: %s", msg))
	if msg != "" {
		delete(msg)
	}
	testing.expect(t, prompt_call_count == 1, "prompt should be invoked once for warning-only module")

	installed_path := filepath.join({modules_dir, "warning-prompt"})
	testing.expect(t, !os.exists(installed_path), "module should not be installed when prompt rejects")
	delete(installed_path)
}
