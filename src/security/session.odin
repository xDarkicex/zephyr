package security

import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

@(private="file")
_session_registry: Session_Registry

init_session_registry :: proc() {
	_session_registry.sessions = make(map[string]Session_Info)
	sync.mutex_init(&_session_registry.mutex)
}

register_session :: proc(agent_id: string, agent_type: string, session_id: string, parent: string) {
	sync.mutex_lock(&_session_registry.mutex)
	defer sync.mutex_unlock(&_session_registry.mutex)

	role := determine_role(agent_type)

	info := Session_Info{
		session_id     = strings.clone(session_id),
		agent_id       = strings.clone(agent_id),
		agent_type     = strings.clone(agent_type),
		parent_process = strings.clone(parent),
		started_at     = current_timestamp(),
		role           = strings.clone(role),
	}

	_session_registry.sessions[session_id] = info

	log_session_registration(info)
}

determine_role :: proc(agent_type: string) -> string {
	switch agent_type {
	case "human":
		return "user"
	case "claude-code", "cursor", "github-copilot", "vscode", "windsurf", "aider":
		return "agent"
	case:
		return "agent"
	}
}

get_current_session :: proc() -> (Session_Info, bool) {
	session_id := os.get_env("ZEPHYR_SESSION_ID")
	defer delete(session_id)
	if session_id == "" {
		return {}, false
	}

	sync.mutex_lock(&_session_registry.mutex)
	defer sync.mutex_unlock(&_session_registry.mutex)

	info, ok := _session_registry.sessions[session_id]
	return info, ok
}

get_all_sessions :: proc() -> []Session_Info {
	sync.mutex_lock(&_session_registry.mutex)
	defer sync.mutex_unlock(&_session_registry.mutex)

	sessions := make([dynamic]Session_Info)
	for _, info in _session_registry.sessions {
		append(&sessions, info)
	}
	return sessions[:]
}

current_timestamp :: proc() -> string {
	now := time.now()
	return time.format(now, time.RFC3339)
}

