package test

import "core:testing"
import "core:os"
import "core:path/filepath"

import "../src/security"

@(test)
test_default_role_config_values :: proc(t: ^testing.T) {
	config := security.get_default_security_config()

	user := config.roles["user"]
	testing.expect(t, user.can_install, "User can install")
	testing.expect(t, user.can_install_unsigned, "User can install unsigned")
	testing.expect(t, user.can_use_unsafe, "User can use unsafe")
	testing.expect(t, user.can_uninstall, "User can uninstall")
	testing.expect(t, user.can_modify_config, "User can modify config")
	testing.expect(t, !user.require_confirmation, "User does not require confirmation")

	agent := config.roles["agent"]
	testing.expect(t, agent.can_install, "Agent can install")
	testing.expect(t, !agent.can_install_unsigned, "Agent cannot install unsigned")
	testing.expect(t, !agent.can_use_unsafe, "Agent cannot use unsafe")
	testing.expect(t, !agent.can_uninstall, "Agent cannot uninstall")
	testing.expect(t, !agent.can_modify_config, "Agent cannot modify config")
	testing.expect(t, agent.require_confirmation, "Agent requires confirmation")
}

@(test)
test_create_default_security_config_file :: proc(t: ^testing.T) {
	original_home := os.get_env("HOME")
	temp_home := setup_test_environment("agent_roles_home")
	defer teardown_test_environment(temp_home)
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	}
	os.set_env("HOME", temp_home)

	config_path := filepath.join({temp_home, ".zephyr", "security.toml"})
	defer delete(config_path)

	// Clean previous file
	if os.exists(config_path) {
		os.remove(config_path)
	}

	security.create_default_security_config()

	testing.expect(t, os.exists(config_path), "security.toml should be created")
}
