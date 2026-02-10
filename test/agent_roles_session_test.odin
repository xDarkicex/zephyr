package test

import "core:testing"
import "core:os"

import "../src/security"

@(test)
test_session_registration_and_retrieval :: proc(t: ^testing.T) {
	security.init_session_registry()

	security.register_session("alice", "human", "111", "zsh")
	os.set_env("ZEPHYR_SESSION_ID", "111")
	defer os.unset_env("ZEPHYR_SESSION_ID")

	session, ok := security.get_current_session()
	testing.expect(t, ok, "Session should be found")
	testing.expect(t, session.agent_id == "alice", "Agent ID should match")
	testing.expect(t, session.agent_type == "human", "Agent type should match")
	testing.expect(t, session.role == "user", "Role should be user")
}

@(test)
test_role_determination :: proc(t: ^testing.T) {
	testing.expect(t, security.determine_role("human") == "user", "Human should map to user")
	testing.expect(t, security.determine_role("claude-code") == "agent", "Claude should map to agent")
	testing.expect(t, security.determine_role("cursor") == "agent", "Cursor should map to agent")
}

