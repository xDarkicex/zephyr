package test

import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../src/cli"
import "../src/security"

join_posix_test :: proc(base: string, rest: string) -> string {
	if base == "" {
		return strings.clone(rest)
	}
	trimmed := base
	if strings.has_suffix(trimmed, "/") {
		trimmed = trimmed[:len(trimmed)-1]
	}
	if rest == "" {
		return strings.clone(trimmed)
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, trimmed)
	strings.write_string(&builder, "/")
	strings.write_string(&builder, rest)
	return strings.clone(strings.to_string(builder))
}

setup_cli_home :: proc(t: ^testing.T, name: string) -> (string, string) {
	lock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment(name)
	os.set_env("HOME", temp_home)
	return temp_home, original_home
}

@(test)
test_cli_session_command_runs :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_cli_home(t, "agent_roles_cli_session")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_home != "" {
			delete(original_home)
		}
		teardown_test_environment(temp_home)
		unlock_home_env()
	}

	security.init_session_registry()
	defer security.cleanup_session_registry()
	os.set_env("ZEPHYR_SESSION_ID", "cli-session-1")
	defer os.unset_env("ZEPHYR_SESSION_ID")
	security.register_session("agent-1", "cursor", "cli-session-1", "zsh")

	cli.session_command()
}

@(test)
test_cli_sessions_command_runs :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_cli_home(t, "agent_roles_cli_sessions")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_home != "" {
			delete(original_home)
		}
		teardown_test_environment(temp_home)
		unlock_home_env()
	}

	security.init_session_registry()
	defer security.cleanup_session_registry()
	security.register_session("agent-1", "cursor", "cli-session-2", "zsh")
	security.register_session("agent-2", "claude-code", "cli-session-3", "zsh")

	cli.sessions_command()
}

@(test)
test_cli_register_session_command :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_cli_home(t, "agent_roles_cli_register")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_home != "" {
			delete(original_home)
		}
		teardown_test_environment(temp_home)
		unlock_home_env()
	}

	security.init_session_registry()
	defer security.cleanup_session_registry()

	original_args := os.args
	defer os.args = original_args
	os.args = []string{"zephyr", "register-session", "--agent-id=test-agent", "--agent-type=cursor", "--session-id=cli-session-4", "--parent=zsh"}

	os.set_env("ZEPHYR_SESSION_ID", "cli-session-4")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	cli.register_session_command()

	_, ok := security.get_current_session()
	testing.expect(t, ok, "register-session should create current session")
}

@(test)
test_cli_audit_command_runs :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_cli_home(t, "agent_roles_cli_audit")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_home != "" {
			delete(original_home)
		}
		teardown_test_environment(temp_home)
		unlock_home_env()
	}

	base := join_posix_test(temp_home, ".zephyr/audit")
	defer delete(base)
	sessions_dir := join_posix_test(base, "sessions")
	_ = os.make_directory(sessions_dir, 0o755)
	delete(sessions_dir)
	commands_dir := join_posix_test(base, "commands")
	commands_date_dir := join_posix_test(commands_dir, "2026-02-10")
	_ = os.make_directory(commands_date_dir, 0o755)
	delete(commands_date_dir)
	delete(commands_dir)
	operations_dir := join_posix_test(base, "operations")
	operations_date_dir := join_posix_test(operations_dir, "2026-02-10")
	_ = os.make_directory(operations_date_dir, 0o755)
	delete(operations_date_dir)
	delete(operations_dir)

	session_dir := join_posix_test(base, "sessions")
	session_log := join_posix_test(session_dir, "cli-session-5-2026-02-10T00:00:00Z.log")
	delete(session_dir)
	command_dir := join_posix_test(base, "commands")
	command_date_dir := join_posix_test(command_dir, "2026-02-10")
	command_log := join_posix_test(command_date_dir, "cli-session-5.log")
	delete(command_date_dir)
	delete(command_dir)
	operation_dir := join_posix_test(base, "operations")
	operation_date_dir := join_posix_test(operation_dir, "2026-02-10")
	operation_log := join_posix_test(operation_date_dir, "operations.log")
	delete(operation_date_dir)
	delete(operation_dir)
	defer {
		delete(session_log)
		delete(command_log)
		delete(operation_log)
	}

	session_line := `{"session_id":"cli-session-5","agent_id":"agent-5","agent_type":"cursor","parent_process":"zsh","started_at":"2026-02-10T00:00:00Z","role":"agent"}`
	command_line := `{"timestamp":"2026-02-10T00:00:01Z","session_id":"cli-session-5","agent_id":"agent-5","agent_type":"cursor","role":"agent","action":"command_scan","command":"echo test","result":"warning","reason":"test","exit_code":2}`
	operation_line := `{"timestamp":"2026-02-10T00:00:02Z","session_id":"cli-session-5","agent_id":"agent-5","agent_type":"cursor","role":"agent","action":"install","module":"demo","source":"demo","result":"blocked","reason":"test","signature_verified":false}`

	_ = os.write_entire_file(session_log, transmute([]u8)session_line)
	_ = os.write_entire_file(command_log, transmute([]u8)command_line)
	_ = os.write_entire_file(operation_log, transmute([]u8)operation_line)

	original_args := os.args
	defer os.args = original_args
	os.args = []string{"zephyr", "audit", "--type=operations", "--filter=blocked"}

	cli.audit_command()
}
