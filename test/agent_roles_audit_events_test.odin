package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/security"

@(test)
test_audit_session_log_written :: proc(t: ^testing.T) {
	lock_home_env()
	defer unlock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_audit_session")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	info := security.Session_Info{
		session_id = "sess-1",
		agent_id = "agent-1",
		agent_type = "claude-code",
		parent_process = "zsh",
		started_at = "2026-02-07T10:30:00Z",
		role = "agent",
	}
	security.log_session_registration(info)

	log_path := filepath.join({temp_home, ".zephyr", "audit", "sessions", "sess-1-2026-02-07T10:30:00Z.log"})
	defer delete(log_path)
	testing.expect(t, os.exists(log_path), "session log should exist")
	if !os.exists(log_path) {
		return
	}
	data, ok := os.read_entire_file(log_path)
	testing.expect(t, ok, "should read session log")
	if ok {
		line := string(data)
		testing.expect(t, strings.contains(line, "\"session_id\":\"sess-1\""), "session log should include session_id")
		testing.expect(t, strings.contains(line, "\"agent_type\":\"claude-code\""), "session log should include agent_type")
		delete(data)
	}
}

@(test)
test_audit_command_log_written :: proc(t: ^testing.T) {
	lock_home_env()
	defer unlock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_audit_command")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	security.log_command_scan("cmd-1", "echo \"hi\"", "safe", "ok", 0)

	now := time.now()
	buf: [time.MIN_YYYY_DATE_LEN]u8
	date := strings.clone(time.to_string_yyyy_mm_dd(now, buf[:]))
	defer delete(date)
	log_path := filepath.join({temp_home, ".zephyr", "audit", "commands", date, "cmd-1.log"})
	defer delete(log_path)
	testing.expect(t, os.exists(log_path), "command log should exist")
	if !os.exists(log_path) {
		return
	}
	data, ok := os.read_entire_file(log_path)
	testing.expect(t, ok, "should read command log")
	if ok {
		line := string(data)
		testing.expect(t, strings.contains(line, "\"action\":\"command_scan\""), "command log should include action")
		testing.expect(t, strings.contains(line, "\"exit_code\":0"), "command log should include exit_code")
		delete(data)
	}
}

@(test)
test_audit_operation_log_written :: proc(t: ^testing.T) {
	lock_home_env()
	defer unlock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_audit_operation")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	security.init_session_registry()
	security.register_session("agent-op", "human", "op-1", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "op-1")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	security.log_module_install("test-module", "https://example.com/test", true, "ok", true)

	now := time.now()
	buf: [time.MIN_YYYY_DATE_LEN]u8
	date := strings.clone(time.to_string_yyyy_mm_dd(now, buf[:]))
	defer delete(date)
	log_path := filepath.join({temp_home, ".zephyr", "audit", "operations", date, "operations.log"})
	defer delete(log_path)
	testing.expect(t, os.exists(log_path), "operations log should exist")
	if !os.exists(log_path) {
		return
	}
	data, ok := os.read_entire_file(log_path)
	testing.expect(t, ok, "should read operations log")
	if ok {
		line := string(data)
		testing.expect(t, strings.contains(line, "\"action\":\"install\""), "operations log should include install action")
		testing.expect(t, strings.contains(line, "\"module\":\"test-module\""), "operations log should include module name")
		delete(data)
	}
}

@(test)
test_audit_cleanup_removes_old_entries :: proc(t: ^testing.T) {
	lock_home_env()
	defer unlock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_audit_cleanup")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	zephyr_dir := filepath.join({temp_home, ".zephyr"})
	defer delete(zephyr_dir)
	_ = os.make_directory(zephyr_dir, 0o755)

	audit_dir := filepath.join({zephyr_dir, "audit"})
	defer delete(audit_dir)
	_ = os.make_directory(audit_dir, 0o755)

	operations_dir := filepath.join({audit_dir, "operations"})
	defer delete(operations_dir)
	_ = os.make_directory(operations_dir, 0o755)

	old_dir := filepath.join({operations_dir, "2000-01-01"})
	defer delete(old_dir)
	now := time.now()
	future := time.time_add(now, time.Duration(24*60*60*1e9))
	future_stamp, ok_future := time.time_to_rfc3339(future, 0, false)
	if !ok_future || len(future_stamp) < 10 {
		testing.expect(t, false, "failed to format future date")
		return
	}
	future_date := future_stamp[:10]
	new_dir := filepath.join({operations_dir, future_date})
	defer delete(new_dir)

	_ = os.make_directory(old_dir, 0o755)
	_ = os.make_directory(new_dir, 0o755)

	old_file := filepath.join({old_dir, "operations.log"})
	defer delete(old_file)
	content := "{}"
	_ = os.write_entire_file(old_file, transmute([]u8)content)

	security.cleanup_old_audit_logs(0)

	testing.expect(t, !os.exists(old_dir), "old audit directory should be removed")
	testing.expect(t, os.exists(new_dir), "future audit directory should remain")
}
