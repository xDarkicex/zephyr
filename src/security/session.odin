package security

import "core:os"
import "core:strings"
import "core:sync"
import "core:time"
import "core:fmt"
import "core:path/filepath"
import "core:os/os2"

@(private="file")
_session_registry: Session_Registry

init_session_registry :: proc() {
	_session_registry.sessions = make(map[string]Session_Info)
}

ensure_session_registry :: proc() {
	if _session_registry.sessions == nil {
		init_session_registry()
	}
}

cleanup_session_registry :: proc() {
	ensure_session_registry()
	sync.mutex_lock(&_session_registry.mutex)
	defer sync.mutex_unlock(&_session_registry.mutex)

	for _, info in _session_registry.sessions {
		if info.session_id != "" {
			delete(info.session_id)
		}
		if info.agent_id != "" {
			delete(info.agent_id)
		}
		if info.agent_type != "" {
			delete(info.agent_type)
		}
		if info.parent_process != "" {
			delete(info.parent_process)
		}
		if info.started_at != "" {
			delete(info.started_at)
		}
		if info.role != "" {
			delete(info.role)
		}
	}
	delete(_session_registry.sessions)
	_session_registry.sessions = make(map[string]Session_Info)
}

register_session :: proc(agent_id: string, agent_type: string, session_id: string, parent: string) {
	ensure_session_registry()
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

	ensure_session_registry()
	sync.mutex_lock(&_session_registry.mutex)
	defer sync.mutex_unlock(&_session_registry.mutex)

	info, ok := _session_registry.sessions[session_id]
	if ok {
		return info, true
	}

	loaded, ok_loaded := load_session_from_logs(session_id)
	if ok_loaded {
		_session_registry.sessions[session_id] = loaded
		return loaded, true
	}

	return {}, false
}

is_agent_environment :: proc() -> bool {
	session, ok := get_current_session()
	if !ok {
		return false
	}
	return session.role == "agent"
}

get_all_sessions :: proc() -> []Session_Info {
	ensure_session_registry()
	sync.mutex_lock(&_session_registry.mutex)
	defer sync.mutex_unlock(&_session_registry.mutex)

	sessions := make([dynamic]Session_Info)
	if len(_session_registry.sessions) == 0 {
		loaded := load_all_sessions_from_logs()
		for session in loaded {
			append(&sessions, session)
		}
		if loaded != nil {
			delete(loaded)
		}
		return sessions[:]
	}

	for _, info in _session_registry.sessions {
		append(&sessions, info)
	}
	return sessions[:]
}

current_timestamp :: proc() -> string {
	now := time.now()
	stamp, ok := time.time_to_rfc3339(now, 0, false)
	if !ok {
		return fmt.tprintf("%v", now)
	}
	return stamp
}

load_session_from_logs :: proc(session_id: string) -> (Session_Info, bool) {
	if session_id == "" {
		return {}, false
	}
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		return {}, false
	}

	sessions_dir := filepath.join({home, ".zephyr", "audit", "sessions"})
	defer delete(sessions_dir)
	if !os.exists(sessions_dir) {
		return {}, false
	}

	files, err := os2.read_all_directory_by_path(sessions_dir, context.temp_allocator)
	if err != nil {
		return {}, false
	}
	defer os2.file_info_slice_delete(files, context.temp_allocator)

	prefix := strings.concatenate({session_id, "-"})
	defer delete(prefix)
	best_file := ""

	for file in files {
		if file.type == os2.File_Type.Directory {
			continue
		}
		if !strings.has_prefix(file.name, prefix) || !strings.has_suffix(file.name, ".log") {
			continue
		}
		if best_file == "" || file.name > best_file {
			if best_file != "" {
				delete(best_file)
			}
			best_file = strings.clone(file.name)
		}
	}

	if best_file == "" {
		return {}, false
	}
	defer delete(best_file)

	log_path := filepath.join({sessions_dir, best_file})
	defer delete(log_path)
	data, ok := os.read_entire_file(log_path)
	if !ok {
		return {}, false
	}
	defer delete(data)

	line := strings.trim_space(string(data))
	if line == "" {
		return {}, false
	}

	info := parse_session_line(line)
	if info.session_id == "" {
		return {}, false
	}
	return info, true
}

load_all_sessions_from_logs :: proc() -> [dynamic]Session_Info {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		return nil
	}
	sessions_dir := filepath.join({home, ".zephyr", "audit", "sessions"})
	defer delete(sessions_dir)
	if !os.exists(sessions_dir) {
		return nil
	}

	files, err := os2.read_all_directory_by_path(sessions_dir, context.temp_allocator)
	if err != nil {
		return nil
	}
	defer os2.file_info_slice_delete(files, context.temp_allocator)

	sessions := make([dynamic]Session_Info)
	for file in files {
		if file.type == os2.File_Type.Directory {
			continue
		}
		if !strings.has_suffix(file.name, ".log") {
			continue
		}
		log_path := filepath.join({sessions_dir, file.name})
		data, ok := os.read_entire_file(log_path)
		if ok {
			line := strings.trim_space(string(data))
			if line != "" {
				info := parse_session_line(line)
				if info.session_id != "" {
					append(&sessions, info)
				}
			}
			delete(data)
		}
		delete(log_path)
	}
	return sessions
}

parse_session_line :: proc(line: string) -> Session_Info {
	info := Session_Info{}
	info.session_id = json_extract_string(line, "session_id")
	info.agent_id = json_extract_string(line, "agent_id")
	info.agent_type = json_extract_string(line, "agent_type")
	info.parent_process = json_extract_string(line, "parent_process")
	info.started_at = json_extract_string(line, "started_at")
	info.role = json_extract_string(line, "role")
	return info
}

json_extract_string :: proc(line: string, key: string) -> string {
	if line == "" || key == "" {
		return ""
	}
	prefix := fmt.aprintf("\"%s\":\"", key)
	defer delete(prefix)
	idx := strings.index(line, prefix)
	if idx < 0 {
		return ""
	}
	rest := line[idx+len(prefix):]
	end := strings.index(rest, "\"")
	if end < 0 {
		return ""
	}
	return strings.clone(rest[:end])
}
