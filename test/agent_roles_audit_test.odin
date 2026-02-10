package test

import "core:testing"
import "core:os"
import "core:path/filepath"

import "../src/security"

@(test)
test_audit_log_paths_created :: proc(t: ^testing.T) {
	home := os.get_env("HOME")
	defer delete(home)
	testing.expect(t, home != "", "HOME not set")
	if home == "" {
		return
	}

	security.init_session_registry()
	security.register_session("tester", "human", "300", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "300")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	security.log_module_install("test-module", "https://example.com/test", true, "ok", true)

	base := filepath.join({home, ".zephyr", "audit", "operations"})
	defer delete(base)
	testing.expect(t, os.exists(base), "operations audit directory should exist")
}
