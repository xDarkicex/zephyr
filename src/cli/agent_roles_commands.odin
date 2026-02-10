package cli

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "core:os/os2"
import "core:strconv"

import "../colors"
import "../security"

Audit_Options :: struct {
	show_sessions:   bool,
	show_commands:   bool,
	show_operations: bool,
	filter:          string,
	agent_filter:    string,
	session_filter:  string,
	since_set:       bool,
	until_set:       bool,
	since_time:      time.Time,
	until_time:      time.Time,
}

Audit_Entry :: struct {
	kind:       string,
	timestamp:  string,
	sort_key:   string,
	session_id: string,
	agent_id:   string,
	agent_type: string,
	role:       string,
	action:     string,
	module:     string,
	source:     string,
	result:     string,
	reason:     string,
	command:    string,
	parent:     string,
	started_at: string,
	exit_code:  int,
}

session_command :: proc() {
	session, ok := security.get_current_session()
	if !ok {
		fmt.println("No active session.")
		return
	}

	fmt.println(colors.bold("Current Session"))
	fmt.printf("  Session ID: %s\n", session.session_id)
	fmt.printf("  Agent: %s (%s)\n", session.agent_id, session.agent_type)
	fmt.printf("  Role: %s\n", session.role)
	fmt.printf("  Parent: %s\n", session.parent_process)
	fmt.printf("  Started: %s\n", session.started_at)

	role_config := security.load_role_config(session.role)
	fmt.println("")
	fmt.println(colors.bold("Permissions"))
	print_permission("Install", role_config.can_install)
	print_permission("Install Unsigned", role_config.can_install_unsigned)
	print_permission("Use --unsafe", role_config.can_use_unsafe)
	print_permission("Uninstall", role_config.can_uninstall)
	print_permission("Modify Config", role_config.can_modify_config)
	print_permission("Require Confirmation", role_config.require_confirmation)
}

sessions_command :: proc() {
	sessions := security.get_all_sessions()
	defer delete(sessions)
	if len(sessions) == 0 {
		fmt.println("No active sessions.")
		return
	}

	fmt.println(colors.bold("Active Sessions"))
	fmt.printf("%-20s %-15s %-12s %-8s %-20s\n", "Session ID", "Agent", "Type", "Role", "Started")
	for session in sessions {
		fmt.printf("%-20s %-15s %-12s %-8s %-20s\n",
			session.session_id,
			session.agent_id,
			session.agent_type,
			session.role,
			session.started_at,
		)
	}
}

audit_command :: proc() {
	opts := parse_audit_options()

	if !opts.show_sessions && !opts.show_commands && !opts.show_operations {
		opts.show_sessions = true
		opts.show_commands = true
		opts.show_operations = true
	}

	events := make([dynamic]Audit_Entry)
	read_audit_events(&events, opts)
	if len(events) == 0 {
		fmt.println("No audit events found.")
		delete(events)
		return
	}

	sort_events_by_timestamp(&events)
	print_audit_events(events[:])
	delete(events)
}

register_session_command :: proc() {
	args := os.args[1:]
	agent_id := ""
	agent_type := ""
	session_id := ""
	parent := ""

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		if arg == "register-session" || is_global_flag(arg) {
			continue
		}
		if strings.has_prefix(arg, "--agent-id=") {
			agent_id = strings.trim_prefix(arg, "--agent-id=")
			continue
		}
		if strings.has_prefix(arg, "--agent-type=") {
			agent_type = strings.trim_prefix(arg, "--agent-type=")
			continue
		}
		if strings.has_prefix(arg, "--session-id=") {
			session_id = strings.trim_prefix(arg, "--session-id=")
			continue
		}
		if strings.has_prefix(arg, "--parent=") {
			parent = strings.trim_prefix(arg, "--parent=")
			continue
		}
		if arg == "--agent-id" && i+1 < len(args) {
			i += 1
			agent_id = args[i]
			continue
		}
		if arg == "--agent-type" && i+1 < len(args) {
			i += 1
			agent_type = args[i]
			continue
		}
		if arg == "--session-id" && i+1 < len(args) {
			i += 1
			session_id = args[i]
			continue
		}
		if arg == "--parent" && i+1 < len(args) {
			i += 1
			parent = args[i]
			continue
		}
	}

	if agent_type == "" {
		agent_type = security.detect_agent_type()
	}
	if agent_id == "" {
		agent_id = security.get_agent_id(agent_type)
	}
	if session_id == "" {
		env_session := os.get_env("ZEPHYR_SESSION_ID")
		if env_session != "" {
			session_id = env_session
		} else {
			session_id = fmt.tprintf("%d", time.now()._nsec)
		}
		delete(env_session)
	}
	if parent == "" {
		parent = "unknown"
	}

	security.register_session(agent_id, agent_type, session_id, parent)
	fmt.println("Session registered.")
}

print_permission :: proc(label: string, allowed: bool) {
	symbol := colors.success_symbol()
	if !allowed {
		symbol = colors.error_symbol()
	}
	fmt.printf("  %s %s\n", symbol, label)
}

parse_audit_options :: proc() -> Audit_Options {
	opts := Audit_Options{}
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		if arg == "audit" || is_global_flag(arg) {
			continue
		}
		if strings.has_prefix(arg, "--type=") {
			set_type_filter(&opts, strings.trim_prefix(arg, "--type="))
			continue
		}
		if strings.has_prefix(arg, "--filter=") {
			opts.filter = strings.trim_prefix(arg, "--filter=")
			continue
		}
		if strings.has_prefix(arg, "--agent=") {
			opts.agent_filter = strings.trim_prefix(arg, "--agent=")
			continue
		}
		if strings.has_prefix(arg, "--session=") {
			opts.session_filter = strings.trim_prefix(arg, "--session=")
			continue
		}
		if strings.has_prefix(arg, "--since=") {
			parse_time_filter(&opts, strings.trim_prefix(arg, "--since="), true)
			continue
		}
		if strings.has_prefix(arg, "--until=") {
			parse_time_filter(&opts, strings.trim_prefix(arg, "--until="), false)
			continue
		}
		if arg == "--type" && i+1 < len(args) {
			i += 1
			set_type_filter(&opts, args[i])
			continue
		}
		if arg == "--filter" && i+1 < len(args) {
			i += 1
			opts.filter = args[i]
			continue
		}
		if arg == "--agent" && i+1 < len(args) {
			i += 1
			opts.agent_filter = args[i]
			continue
		}
		if arg == "--session" && i+1 < len(args) {
			i += 1
			opts.session_filter = args[i]
			continue
		}
		if arg == "--since" && i+1 < len(args) {
			i += 1
			parse_time_filter(&opts, args[i], true)
			continue
		}
		if arg == "--until" && i+1 < len(args) {
			i += 1
			parse_time_filter(&opts, args[i], false)
			continue
		}
	}
	return opts
}

set_type_filter :: proc(opts: ^Audit_Options, value: string) {
	switch value {
	case "sessions":
		opts.show_sessions = true
	case "commands":
		opts.show_commands = true
	case "operations":
		opts.show_operations = true
	}
}

parse_time_filter :: proc(opts: ^Audit_Options, value: string, is_since: bool) {
	parsed, ok := parse_time_value(value)
	if !ok {
		return
	}
	if is_since {
		opts.since_set = true
		opts.since_time = parsed
	} else {
		opts.until_set = true
		opts.until_time = parsed
	}
}

parse_time_value :: proc(value: string) -> (time.Time, bool) {
	if value == "" {
		return {}, false
	}
	if len(value) == 10 {
		return security.parse_date_yyyy_mm_dd(value)
	}
	return security.parse_rfc3339_time(value)
}

read_audit_events :: proc(events: ^[dynamic]Audit_Entry, opts: Audit_Options) {
	home := os.get_env("HOME")
	if home == "" {
		return
	}
	defer delete(home)

	base := join_posix(home, ".zephyr/audit")
	defer delete(base)

	if opts.show_sessions {
		path := join_posix(base, "sessions")
		read_session_logs(path, events, opts)
		delete(path)
	}
	if opts.show_commands {
		path := join_posix(base, "commands")
		read_command_logs(path, events, opts)
		delete(path)
	}
	if opts.show_operations {
		path := join_posix(base, "operations")
		read_operations_logs(path, events, opts)
		delete(path)
	}
}

read_session_logs :: proc(base_path: string, events: ^[dynamic]Audit_Entry, opts: Audit_Options) {
	if !os.exists(base_path) {
		return
	}
	files, err := os2.read_all_directory_by_path(base_path, context.temp_allocator)
	if err != nil {
		return
	}
	defer os2.file_info_slice_delete(files, context.temp_allocator)

	for file in files {
		if file.type == os2.File_Type.Directory {
			continue
		}
		path := join_posix(base_path, file.name)
		read_json_lines_log(path, "session", events, opts)
		delete(path)
	}
}

read_command_logs :: proc(base_path: string, events: ^[dynamic]Audit_Entry, opts: Audit_Options) {
	if !os.exists(base_path) {
		return
	}
	dirs, err := os2.read_all_directory_by_path(base_path, context.temp_allocator)
	if err != nil {
		return
	}
	defer os2.file_info_slice_delete(dirs, context.temp_allocator)

	for dir in dirs {
		if dir.type != os2.File_Type.Directory {
			continue
		}
		dir_path := join_posix(base_path, dir.name)
		files, err_files := os2.read_all_directory_by_path(dir_path, context.temp_allocator)
		if err_files != nil {
			delete(dir_path)
			continue
		}
		for file in files {
			if file.type == os2.File_Type.Directory {
				continue
			}
			path := join_posix(dir_path, file.name)
			read_json_lines_log(path, "command", events, opts)
			delete(path)
		}
		os2.file_info_slice_delete(files, context.temp_allocator)
		delete(dir_path)
	}
}

read_operations_logs :: proc(base_path: string, events: ^[dynamic]Audit_Entry, opts: Audit_Options) {
	if !os.exists(base_path) {
		return
	}
	dirs, err := os2.read_all_directory_by_path(base_path, context.temp_allocator)
	if err != nil {
		return
	}
	defer os2.file_info_slice_delete(dirs, context.temp_allocator)

	for dir in dirs {
		if dir.type != os2.File_Type.Directory {
			continue
		}
		dir_path := join_posix(base_path, dir.name)
		path := join_posix(dir_path, "operations.log")
		read_json_lines_log(path, "operation", events, opts)
		delete(path)
		delete(dir_path)
	}
}

read_json_lines_log :: proc(path: string, kind: string, events: ^[dynamic]Audit_Entry, opts: Audit_Options) {
	data, ok := os.read_entire_file(path)
	if !ok {
		return
	}
	defer delete(data)
	lines := strings.split(string(data), "\n")
	defer delete(lines)

	for line in lines {
		if strings.trim_space(line) == "" {
			continue
		}
		entry := parse_audit_line(line, kind)
		if entry.sort_key == "" {
			continue
		}
		if !audit_entry_matches(entry, opts) {
			continue
		}
		append(events, entry)
	}
}

parse_audit_line :: proc(line: string, kind: string) -> Audit_Entry {
	entry := Audit_Entry{kind = kind}
	switch kind {
	case "session":
		entry.session_id = json_extract_string(line, "session_id")
		entry.agent_id = json_extract_string(line, "agent_id")
		entry.agent_type = json_extract_string(line, "agent_type")
		entry.parent = json_extract_string(line, "parent_process")
		entry.started_at = json_extract_string(line, "started_at")
		entry.role = json_extract_string(line, "role")
		entry.timestamp = entry.started_at
		entry.sort_key = entry.started_at
	case "command":
		entry.timestamp = json_extract_string(line, "timestamp")
		entry.session_id = json_extract_string(line, "session_id")
		entry.agent_id = json_extract_string(line, "agent_id")
		entry.agent_type = json_extract_string(line, "agent_type")
		entry.role = json_extract_string(line, "role")
		entry.action = json_extract_string(line, "action")
		entry.command = json_extract_string(line, "command")
		entry.result = json_extract_string(line, "result")
		entry.reason = json_extract_string(line, "reason")
		entry.exit_code = json_extract_int(line, "exit_code")
		entry.sort_key = entry.timestamp
	case "operation":
		entry.timestamp = json_extract_string(line, "timestamp")
		entry.session_id = json_extract_string(line, "session_id")
		entry.agent_id = json_extract_string(line, "agent_id")
		entry.agent_type = json_extract_string(line, "agent_type")
		entry.role = json_extract_string(line, "role")
		entry.action = json_extract_string(line, "action")
		entry.module = json_extract_string(line, "module")
		entry.source = json_extract_string(line, "source")
		entry.result = json_extract_string(line, "result")
		entry.reason = json_extract_string(line, "reason")
		entry.sort_key = entry.timestamp
	}
	return entry
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

json_extract_int :: proc(line: string, key: string) -> int {
	if line == "" || key == "" {
		return 0
	}
	prefix := fmt.aprintf("\"%s\":", key)
	defer delete(prefix)
	idx := strings.index(line, prefix)
	if idx < 0 {
		return 0
	}
	rest := line[idx+len(prefix):]
	value := strings.trim_space(rest)
	if value == "" {
		return 0
	}
	return parse_int_prefix(value)
}

parse_int_prefix :: proc(value: string) -> int {
	sign := 1
	idx := 0
	if len(value) > 0 && value[0] == '-' {
		sign = -1
		idx = 1
	}
	number := 0
	for i := idx; i < len(value); i += 1 {
		c := value[i]
		if c < '0' || c > '9' {
			break
		}
		number = number*10 + int(c-'0')
	}
	return number * sign
}

audit_entry_matches :: proc(entry: Audit_Entry, opts: Audit_Options) -> bool {
	if opts.agent_filter != "" && entry.agent_id != opts.agent_filter {
		return false
	}
	if opts.session_filter != "" && entry.session_id != opts.session_filter {
		return false
	}
	if opts.filter != "" {
		if !matches_filter(entry, opts.filter) {
			return false
		}
	}
	if opts.since_set || opts.until_set {
		event_time, ok := parse_time_value(entry.sort_key)
		if ok {
			if opts.since_set && time.time_to_unix(event_time) < time.time_to_unix(opts.since_time) {
				return false
			}
			if opts.until_set && time.time_to_unix(event_time) > time.time_to_unix(opts.until_time) {
				return false
			}
		}
	}
	return true
}

matches_filter :: proc(entry: Audit_Entry, filter: string) -> bool {
	switch filter {
	case "blocked":
		return entry.result == "blocked" || entry.result == "failed"
	case "denied":
		return entry.result == "denied" || entry.action == "permission_denied"
	case "safe":
		return entry.result == "success"
	case "warning":
		return entry.result == "warning"
	}
	return true
}

sort_events_by_timestamp :: proc(events: ^[dynamic]Audit_Entry) {
	if len(events^) < 2 {
		return
	}
	for i := 1; i < len(events^); i += 1 {
		current := events^[i]
		j := i - 1
		for j >= 0 && events^[j].sort_key < current.sort_key {
			events^[j+1] = events^[j]
			j -= 1
		}
		events^[j+1] = current
	}
}

print_audit_events :: proc(events: []Audit_Entry) {
	for entry in events {
		switch entry.kind {
		case "session":
			print_session_event(entry)
		case "command":
			print_command_event(entry)
		case "operation":
			print_operation_event(entry)
		}
	}
}

print_session_event :: proc(entry: Audit_Entry) {
	fmt.printf("%s %s session %s (%s) role=%s\n",
		colors.info_symbol(),
		entry.started_at,
		entry.agent_id,
		entry.agent_type,
		entry.role,
	)
}

print_command_event :: proc(entry: Audit_Entry) {
	label := event_label(entry)
	fmt.printf("%s %s agent=%s session=%s command \"%s\" result=%s exit=%d\n",
		label,
		entry.timestamp,
		entry.agent_id,
		entry.session_id,
		entry.command,
		entry.result,
		entry.exit_code,
	)
}

print_operation_event :: proc(entry: Audit_Entry) {
	label := event_label(entry)
	if entry.module != "" {
		fmt.printf("%s %s agent=%s session=%s %s module=%s result=%s\n",
			label,
			entry.timestamp,
			entry.agent_id,
			entry.session_id,
			entry.action,
			entry.module,
			entry.result,
		)
	} else {
		fmt.printf("%s %s agent=%s session=%s %s result=%s\n",
			label,
			entry.timestamp,
			entry.agent_id,
			entry.session_id,
			entry.action,
			entry.result,
		)
	}
}

event_label :: proc(entry: Audit_Entry) -> string {
	switch entry.result {
	case "blocked", "denied", "failed":
		return colors.error_symbol()
	case "warning":
		return colors.warning_symbol()
	case "success":
		return colors.success_symbol()
	}
	return colors.info_symbol()
}

// join_posix joins audit paths without filepath.join to avoid stdlib lazy_buffer_string allocations in tests.
join_posix :: proc(base: string, rest: string) -> string {
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
