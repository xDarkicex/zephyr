package test

import "core:testing"
import "core:os"

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

