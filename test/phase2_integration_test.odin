package test

import "core:os"
import "core:path/filepath"
import "core:testing"

import "../src/security"

scan_fixture :: proc(t: ^testing.T, name: string) -> security.Scan_Result {
	modules_dir := get_test_modules_dir()
	defer delete(modules_dir)
	module_path := filepath.join({modules_dir, name})
	defer delete(module_path)
	if !os.exists(module_path) {
		testing.fail(t, "missing test module: " + name)
	}
	return security.scan_module(module_path, security.Scan_Options{})
}

@(test)
test_phase2_attack_credential_exfiltration :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := scan_fixture(t, "credential-exfiltration")
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count > 0, "credential exfiltration should be critical")
	testing.expect(t, len(result.credential_findings) > 0, "credential findings should be present")
	testing.expect(t, result.credential_findings[0].has_exfiltration, "exfiltration should be detected")
}

@(test)
test_phase2_attack_reverse_shell :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := scan_fixture(t, "reverse-shell")
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count > 0, "reverse shell should be critical")
	testing.expect(t, len(result.reverse_shell_findings) > 0, "reverse shell findings should be present")
}

@(test)
test_phase2_attack_cicd_manipulation :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := scan_fixture(t, "cicd-manipulation")
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.warning_count+result.critical_count > 0, "ci/cd manipulation should be detected")
}

@(test)
test_phase2_attack_history_mining :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := scan_fixture(t, "history-mining")
	defer security.cleanup_scan_result(&result)

	testing.expect(t, len(result.credential_findings) > 0, "history mining should be reported as credential access")
	testing.expect(t, result.warning_count+result.critical_count > 0, "history mining should be detected")
}

scan_if_installed :: proc(t: ^testing.T, path: string) -> (security.Scan_Result, bool) {
	if !os.exists(path) {
		testing.skip(t, "module not installed: " + path)
		return security.Scan_Result{}, false
	}
	result := security.scan_module(path, security.Scan_Options{})
	return result, true
}

@(test)
test_phase2_trusted_oh_my_zsh :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	path := os.get_env("HOME") + "/.oh-my-zsh"
	result, ok := scan_if_installed(t, path)
	if !ok do return
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.trusted_module_applied, "trusted module allowlist should apply to oh-my-zsh")
	testing.expect(t, result.critical_count == 0, "trusted module should not block install")
}

@(test)
test_phase2_trusted_zinit :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	path := os.get_env("HOME") + "/.zinit"
	result, ok := scan_if_installed(t, path)
	if !ok do return
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.trusted_module_applied, "trusted module allowlist should apply to zinit")
	testing.expect(t, result.critical_count == 0, "trusted module should not block install")
}

@(test)
test_phase2_trusted_nvm :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	path := os.get_env("HOME") + "/.nvm"
	result, ok := scan_if_installed(t, path)
	if !ok do return
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.trusted_module_applied, "trusted module allowlist should apply to nvm")
	testing.expect(t, result.critical_count == 0, "trusted module should not block install")
}

@(test)
test_phase2_trusted_rbenv :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	path := os.get_env("HOME") + "/.rbenv"
	result, ok := scan_if_installed(t, path)
	if !ok do return
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.trusted_module_applied, "trusted module allowlist should apply to rbenv")
	testing.expect(t, result.critical_count == 0, "trusted module should not block install")
}
