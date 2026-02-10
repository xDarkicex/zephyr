package security

import "core:os"
import "core:strings"
import "core:os/os2"

detect_agent_type :: proc() -> string {
	// Claude Code
	if env_set("ANTHROPIC_API_KEY") || env_set("ANTHROPIC_AGENT_ID") {
		return "claude-code"
	}

	// Cursor
	if env_equals("TERM_PROGRAM", "cursor") || env_set("CURSOR_AGENT_ID") {
		return "cursor"
	}

	// GitHub Copilot
	if env_set("GITHUB_COPILOT_TOKEN") || env_set("GITHUB_COPILOT_SESSION") {
		return "github-copilot"
	}

	// VS Code
	if env_equals("TERM_PROGRAM", "vscode") {
		return "vscode"
	}

	// Windsurf
	if env_set("WINDSURF_SESSION") || env_equals("TERM_PROGRAM", "windsurf") {
		return "windsurf"
	}

	// Aider
	if env_set("AIDER_SESSION") {
		return "aider"
	}

	return detect_agent_from_parent()
}

detect_agent_from_parent :: proc() -> string {
	ppid := os2.get_ppid()
	if ppid <= 0 {
		return "human"
	}

	parent_cmd := get_process_name(ppid)
	if parent_cmd == "" {
		return "human"
	}
	defer delete(parent_cmd)

	lower := strings.to_lower(parent_cmd)
	defer delete(lower)

	if strings.contains(lower, "cursor") {
		return "cursor"
	}
	if strings.contains(lower, "code") {
		return "vscode"
	}
	if strings.contains(lower, "anthropic") {
		return "claude-code"
	}

	return "human"
}

get_process_name :: proc(pid: int) -> string {
	selection := os2.Process_Info_Fields{.Executable_Path, .Command_Line}
	info, err := os2.process_info_by_pid(pid, selection, context.temp_allocator)
	defer os2.free_process_info(info, context.temp_allocator)
	if err != .None {
		return ""
	}

	if info.executable_path != "" {
		return strings.clone(info.executable_path)
	}
	if info.command_line != "" {
		return strings.clone(info.command_line)
	}
	return ""
}

get_agent_id :: proc(agent_type: string) -> string {
	switch agent_type {
	case "claude-code":
		if id := env_value("ANTHROPIC_AGENT_ID"); id != "" {
			return id
		}
	case "cursor":
		if id := env_value("CURSOR_AGENT_ID"); id != "" {
			return id
		}
	case "github-copilot":
		if id := env_value("GITHUB_COPILOT_SESSION"); id != "" {
			return id
		}
	case "windsurf":
		if id := env_value("WINDSURF_SESSION"); id != "" {
			return id
		}
	case "aider":
		if id := env_value("AIDER_SESSION"); id != "" {
			return id
		}
	}

	if user := env_value("USER"); user != "" {
		return user
	}

	return strings.clone("unknown")
}

env_set :: proc(name: string) -> bool {
	value := os.get_env(name)
	defer delete(value)
	return value != ""
}

env_equals :: proc(name: string, expected: string) -> bool {
	value := os.get_env(name)
	defer delete(value)
	return value == expected
}

env_value :: proc(name: string) -> string {
	value := os.get_env(name)
	if value == "" {
		delete(value)
		return ""
	}
	return value
}
