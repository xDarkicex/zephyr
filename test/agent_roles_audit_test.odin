package test

import "core:testing"
import "core:os"
import "core:path/filepath"

import "../src/security"

@(test)
test_audit_log_paths_created :: proc(t: ^testing.T) {
	lock_home_env()
	defer unlock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_audit_home")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	security.init_session_registry()
	security.register_session("tester", "human", "300", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "300")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	security.log_module_install("test-module", "https://example.com/test", true, "ok", true)

	base := filepath.join({temp_home, ".zephyr", "audit", "operations"})
	defer delete(base)
	testing.expect(t, os.exists(base), "operations audit directory should exist")
}
