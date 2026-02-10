package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"
import "../src/git"
import "../src/security"

setup_agent_session :: proc(t: ^testing.T, home_name: string, session_id: string) -> (string, string) {
	lock_home_env()
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment(home_name)
	os.set_env("HOME", temp_home)
	security.init_session_registry()
	security.register_session("agent-1", "cursor", session_id, "zsh")
	os.set_env("ZEPHYR_SESSION_ID", session_id)
	return temp_home, original_home
}

@(test)
test_install_unsigned_blocked_for_agent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_agent_session(t, "agent_roles_perm_install_unsigned", "perm-install-1")
	defer cleanup_agent_session(temp_home, original_home)

	options := git.Manager_Options{}
	success, message := git.install_module("https://example.com/repo.git", options)
	testing.expect(t, !success, "agent unsigned install should be blocked")
	if message != "" {
		testing.expect(t, strings.contains(message, "Permission denied"), "should report permission denied")
		delete(message)
	}
}

@(test)
test_install_unsafe_blocked_for_agent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_agent_session(t, "agent_roles_perm_install_unsafe", "perm-install-2")
	defer cleanup_agent_session(temp_home, original_home)

	options := git.Manager_Options{unsafe = true}
	success, message := git.install_module("https://example.com/repo.git", options)
	testing.expect(t, !success, "agent unsafe install should be blocked")
	if message != "" {
		testing.expect(t, strings.contains(message, "Permission denied"), "should report permission denied")
		delete(message)
	}
}

@(test)
test_uninstall_blocked_for_agent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_agent_session(t, "agent_roles_perm_uninstall", "perm-uninstall-1")
	defer cleanup_agent_session(temp_home, original_home)

	options := git.Manager_Options{}
	success, message := git.uninstall_module("demo-module", options)
	testing.expect(t, !success, "agent uninstall should be blocked")
	if message != "" {
		testing.expect(t, strings.contains(message, "Permission denied"), "should report permission denied")
		delete(message)
	}
}

@(test)
test_modify_config_blocked_for_agent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	temp_home, original_home := setup_agent_session(t, "agent_roles_perm_config", "perm-config-1")
	defer cleanup_agent_session(temp_home, original_home)

	cli.Create_Config_File_For_Test()

	config_path := filepath.join({temp_home, ".zephyr", "config.toml"})
	defer delete(config_path)
	testing.expect(t, !os.exists(config_path), "config should not be created for agent")
}

cleanup_agent_session :: proc(temp_home: string, original_home: string) {
	os.unset_env("ZEPHYR_SESSION_ID")
	if original_home != "" {
		os.set_env("HOME", original_home)
		delete(original_home)
	} else {
		os.unset_env("HOME")
	}
	security.cleanup_session_registry()
	teardown_test_environment(temp_home)
	unlock_home_env()
}
