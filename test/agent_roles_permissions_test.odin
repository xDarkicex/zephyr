package test

import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "../src/security"

@(test)
test_permissions_user_role :: proc(t: ^testing.T) {
	security.init_session_registry()
	security.register_session("user1", "human", "200", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "200")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	testing.expect(t, security.check_permission(.Install), "User can install")
	testing.expect(t, security.check_permission(.Install_Unsigned), "User can install unsigned")
	testing.expect(t, security.check_permission(.Use_Unsafe), "User can use unsafe")
	testing.expect(t, security.check_permission(.Uninstall), "User can uninstall")
	testing.expect(t, security.check_permission(.Modify_Config), "User can modify config")
}

@(test)
test_permissions_agent_role :: proc(t: ^testing.T) {
	security.init_session_registry()
	security.register_session("agent1", "claude-code", "201", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "201")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	testing.expect(t, security.check_permission(.Install), "Agent can install")
	testing.expect(t, !security.check_permission(.Install_Unsigned), "Agent cannot install unsigned")
	testing.expect(t, !security.check_permission(.Use_Unsafe), "Agent cannot use unsafe")
	testing.expect(t, !security.check_permission(.Uninstall), "Agent cannot uninstall")
	testing.expect(t, !security.check_permission(.Modify_Config), "Agent cannot modify config")
}

@(test)
test_permissions_missing_session_defaults_allow :: proc(t: ^testing.T) {
	os.unset_env("ZEPHYR_SESSION_ID")
	testing.expect(t, security.check_permission(.Install), "Missing session should allow install")
	testing.expect(t, security.check_permission(.Use_Unsafe), "Missing session should allow unsafe")
}

@(test)
test_require_permission_logs_denial :: proc(t: ^testing.T) {
	lock_home_env()
	defer unlock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_perm_log")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	security.init_session_registry()
	security.register_session("agent-log", "claude-code", "perm-1", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "perm-1")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	ok := security.require_permission(.Install_Unsigned, "install unsigned module")
	testing.expect(t, !ok, "Agent should be denied install unsigned module")

	now := time.now()
	buf: [time.MIN_YYYY_DATE_LEN]u8
	date := strings.clone(time.to_string_yyyy_mm_dd(now, buf[:]))
	defer delete(date)
	log_path := filepath.join({temp_home, ".zephyr", "audit", "operations", date, "operations.log"})
	defer delete(log_path)

	testing.expect(t, os.exists(log_path), "permission denial should create operations log")
	if !os.exists(log_path) {
		return
	}

	data, read_ok := os.read_entire_file(log_path)
	testing.expect(t, read_ok, "should read operations log")
	if read_ok {
		line := string(data)
		testing.expect(t, strings.contains(line, "\"action\":\"permission_denied\""), "log should include permission_denied action")
		testing.expect(t, strings.contains(line, "Install_Unsigned"), "log should include permission name")
		delete(data)
	}
}
