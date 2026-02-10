package test

import "core:testing"
import "core:os"

import "../src/security"

@(test)
test_detect_claude_code :: proc(t: ^testing.T) {
	os.set_env("ANTHROPIC_API_KEY", "test-key")
	defer os.unset_env("ANTHROPIC_API_KEY")

	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "claude-code", "Should detect Claude Code")
	delete(agent_type)
}

@(test)
test_detect_cursor :: proc(t: ^testing.T) {
	os.set_env("TERM_PROGRAM", "cursor")
	defer os.unset_env("TERM_PROGRAM")

	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "cursor", "Should detect Cursor")
	delete(agent_type)
}

@(test)
test_detect_github_copilot :: proc(t: ^testing.T) {
	os.set_env("GITHUB_COPILOT_TOKEN", "token")
	defer os.unset_env("GITHUB_COPILOT_TOKEN")

	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "github-copilot", "Should detect GitHub Copilot")
	delete(agent_type)
}

@(test)
test_detect_vscode :: proc(t: ^testing.T) {
	os.set_env("TERM_PROGRAM", "vscode")
	defer os.unset_env("TERM_PROGRAM")

	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "vscode", "Should detect VS Code")
	delete(agent_type)
}

@(test)
test_detect_windsurf :: proc(t: ^testing.T) {
	os.set_env("WINDSURF_SESSION", "session")
	defer os.unset_env("WINDSURF_SESSION")

	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "windsurf", "Should detect Windsurf")
	delete(agent_type)
}

@(test)
test_detect_aider :: proc(t: ^testing.T) {
	os.set_env("AIDER_SESSION", "session")
	defer os.unset_env("AIDER_SESSION")

	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "aider", "Should detect Aider")
	delete(agent_type)
}

@(test)
test_detect_human_default :: proc(t: ^testing.T) {
	agent_type := security.detect_agent_type()
	testing.expect(t, agent_type == "human", "Should default to human")
	delete(agent_type)
}

