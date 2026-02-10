package test

import "core:testing"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../src/cli"
import "../src/security"

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

	base := filepath.join({temp_home, ".zephyr", "audit"})
	defer delete(base)
	_ = os.make_directory(filepath.join({base, "sessions"}), 0o755)
	_ = os.make_directory(filepath.join({base, "commands", "2026-02-10"}), 0o755)
	_ = os.make_directory(filepath.join({base, "operations", "2026-02-10"}), 0o755)

	session_log := filepath.join({base, "sessions", "cli-session-5-2026-02-10T00:00:00Z.log"})
	command_log := filepath.join({base, "commands", "2026-02-10", "cli-session-5.log"})
	operation_log := filepath.join({base, "operations", "2026-02-10", "operations.log"})
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
