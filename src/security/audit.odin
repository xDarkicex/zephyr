package security

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:strconv"
import "core:os/os2"

import "../debug"

AUDIT_SCHEMA_VERSION :: "1.0"

ensure_directory :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	if os.exists(path) {
		return true
	}
	parent := filepath.dir(path)
	defer delete(parent)
	if parent != "" && parent != path {
		if !ensure_directory(parent) {
			return false
		}
	}
	_ = os.make_directory(path, 0o755)
	return os.exists(path)
}

// Session and agent audit logging (agent roles feature).
log_session_registration :: proc(info: Session_Info) {
	log_path := get_session_log_path(info.session_id, info.started_at)
	if log_path == "" {
		return
	}
	defer delete(log_path)

	json_line := format_session_json(info)
	defer delete(json_line)
	append_line(log_path, json_line)
}

log_command_scan :: proc(session_id: string, command: string, result: string, reason: string, exit_code: int) {
	session, ok := get_current_session()
	if !ok {
		session = Session_Info{
			session_id = session_id,
			agent_id = os.get_env("USER"),
			agent_type = "human",
			role = "user",
		}
	}

	event := Audit_Event{
		timestamp = current_timestamp(),
		session_id = session.session_id,
		agent_id = session.agent_id,
		agent_type = session.agent_type,
		role = session.role,
		action = "command_scan",
		result = result,
		reason = reason,
	}

	log_path := get_command_log_path(session_id)
	if log_path == "" {
		return
	}
	defer delete(log_path)

	json_line := format_command_scan_json(event, command, exit_code)
	defer delete(json_line)
	append_line(log_path, json_line)
}

log_audit_event :: proc(event: Audit_Event) {
	log_path := get_operations_log_path()
	if log_path == "" {
		return
	}
	defer delete(log_path)

	json_line := format_audit_json(event)
	defer delete(json_line)
	append_line(log_path, json_line)
}

log_permission_denied :: proc(session: Session_Info, perm: Permission, operation: string) {
	event := Audit_Event{
		timestamp = current_timestamp(),
		session_id = session.session_id,
		agent_id = session.agent_id,
		agent_type = session.agent_type,
		role = session.role,
		action = "permission_denied",
		result = "denied",
		reason = fmt.aprintf("Missing permission: %v for %s", perm, operation),
	}
	defer delete(event.reason)

	log_audit_event(event)
}

log_module_install :: proc(module: string, source: string, success: bool, reason: string, signed: bool) {
	session, ok := get_current_session()
	if !ok {
		session = Session_Info{
			session_id = "unknown",
			agent_id = os.get_env("USER"),
			agent_type = "human",
			role = "user",
		}
	}

	result := "success"
	if !success {
		result = "failed"
	}

	event := Audit_Event{
		timestamp = current_timestamp(),
		session_id = session.session_id,
		agent_id = session.agent_id,
		agent_type = session.agent_type,
		role = session.role,
		action = "install",
		module = module,
		source = source,
		result = result,
		reason = reason,
		signature_verified = signed,
	}

	log_audit_event(event)
}

get_session_log_path :: proc(session_id: string, timestamp: string) -> string {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		return ""
	}

	filename := fmt.aprintf("%s-%s.log", session_id, timestamp)
	defer delete(filename)
	return filepath.join({home, ".zephyr", "audit", "sessions", filename})
}

get_command_log_path :: proc(session_id: string) -> string {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		return ""
	}

	date := get_current_date()
	defer delete(date)
	filename := fmt.aprintf("%s.log", session_id)
	defer delete(filename)
	return filepath.join({home, ".zephyr", "audit", "commands", date, filename})
}

get_operations_log_path :: proc() -> string {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		return ""
	}

	date := get_current_date()
	defer delete(date)
	return filepath.join({home, ".zephyr", "audit", "operations", date, "operations.log"})
}

get_current_date :: proc() -> string {
	now := time.now()
	buf: [time.MIN_YYYY_DATE_LEN]u8
	return strings.clone(time.to_string_yyyy_mm_dd(now, buf[:]))
}

format_session_json :: proc(info: Session_Info) -> string {
	agent_id := escape_json_string(info.agent_id)
	agent_type := escape_json_string(info.agent_type)
	parent := escape_json_string(info.parent_process)
	started := escape_json_string(info.started_at)
	role := escape_json_string(info.role)
	session_id := escape_json_string(info.session_id)
	user_name := escape_json_string(os.get_env("USER"))
	host_name := escape_json_string(os.get_env("HOSTNAME"))
	defer {
		delete(agent_id)
		delete(agent_type)
		delete(parent)
		delete(started)
		delete(role)
		delete(session_id)
		delete(user_name)
		delete(host_name)
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "{")
	fmt.sbprintf(&builder, "\"schema_version\":\"%s\",", AUDIT_SCHEMA_VERSION)
	fmt.sbprintf(&builder, "\"@timestamp\":\"%s\",", started)
	fmt.sbprintf(&builder, "\"session_id\":\"%s\",", session_id)
	fmt.sbprintf(&builder, "\"agent_id\":\"%s\",", agent_id)
	fmt.sbprintf(&builder, "\"agent_type\":\"%s\",", agent_type)
	fmt.sbprintf(&builder, "\"user_name\":\"%s\",", user_name)
	fmt.sbprintf(&builder, "\"host_name\":\"%s\",", host_name)
	fmt.sbprintf(&builder, "\"parent_process\":\"%s\",", parent)
	fmt.sbprintf(&builder, "\"started_at\":\"%s\",", started)
	fmt.sbprintf(&builder, "\"role\":\"%s\"", role)
	fmt.sbprintf(&builder, ",\"action\":\"session_registered\"")
	fmt.sbprintf(&builder, ",\"event_action\":\"session_registered\"")
	fmt.sbprintf(&builder, ",\"event_outcome\":\"success\"")
	fmt.sbprintf(&builder, ",\"event_category\":\"session\"")
	fmt.sbprintf(&builder, "}")
	return strings.clone(strings.to_string(builder))
}

format_audit_json :: proc(event: Audit_Event) -> string {
	timestamp := escape_json_string(event.timestamp)
	session_id := escape_json_string(event.session_id)
	agent_id := escape_json_string(event.agent_id)
	agent_type := escape_json_string(event.agent_type)
	role := escape_json_string(event.role)
	action := escape_json_string(event.action)
	module := escape_json_string(event.module)
	source := escape_json_string(event.source)
	result := escape_json_string(event.result)
	reason := escape_json_string(event.reason)
	user_name := escape_json_string(os.get_env("USER"))
	host_name := escape_json_string(os.get_env("HOSTNAME"))
	event_category := escape_json_string(event_category_for_action(event.action))
	defer {
		delete(timestamp)
		delete(session_id)
		delete(agent_id)
		delete(agent_type)
		delete(role)
		delete(action)
		delete(module)
		delete(source)
		delete(result)
		delete(reason)
		delete(user_name)
		delete(host_name)
		delete(event_category)
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "{")
	fmt.sbprintf(&builder, "\"schema_version\":\"%s\",", AUDIT_SCHEMA_VERSION)
	fmt.sbprintf(&builder, "\"@timestamp\":\"%s\",", timestamp)
	fmt.sbprintf(&builder, "\"timestamp\":\"%s\",", timestamp)
	fmt.sbprintf(&builder, "\"session_id\":\"%s\",", session_id)
	fmt.sbprintf(&builder, "\"agent_id\":\"%s\",", agent_id)
	fmt.sbprintf(&builder, "\"agent_type\":\"%s\",", agent_type)
	fmt.sbprintf(&builder, "\"user_name\":\"%s\",", user_name)
	fmt.sbprintf(&builder, "\"host_name\":\"%s\",", host_name)
	fmt.sbprintf(&builder, "\"role\":\"%s\",", role)
	fmt.sbprintf(&builder, "\"action\":\"%s\",", action)
	fmt.sbprintf(&builder, "\"module\":\"%s\",", module)
	fmt.sbprintf(&builder, "\"source\":\"%s\",", source)
	fmt.sbprintf(&builder, "\"result\":\"%s\",", result)
	fmt.sbprintf(&builder, "\"reason\":\"%s\",", reason)
	fmt.sbprintf(&builder, "\"event_action\":\"%s\",", action)
	fmt.sbprintf(&builder, "\"event_outcome\":\"%s\",", result)
	fmt.sbprintf(&builder, "\"event_category\":\"%s\",", event_category)
	fmt.sbprintf(&builder, "\"signature_verified\":%v", event.signature_verified)
	fmt.sbprintf(&builder, "}")
	return strings.clone(strings.to_string(builder))
}

format_command_scan_json :: proc(event: Audit_Event, command: string, exit_code: int) -> string {
	timestamp := escape_json_string(event.timestamp)
	session_id := escape_json_string(event.session_id)
	agent_id := escape_json_string(event.agent_id)
	agent_type := escape_json_string(event.agent_type)
	role := escape_json_string(event.role)
	command_escaped := escape_json_string(command)
	result := escape_json_string(event.result)
	reason := escape_json_string(event.reason)
	user_name := escape_json_string(os.get_env("USER"))
	host_name := escape_json_string(os.get_env("HOSTNAME"))
	defer {
		delete(timestamp)
		delete(session_id)
		delete(agent_id)
		delete(agent_type)
		delete(role)
		delete(command_escaped)
		delete(result)
		delete(reason)
		delete(user_name)
		delete(host_name)
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "{")
	fmt.sbprintf(&builder, "\"schema_version\":\"%s\",", AUDIT_SCHEMA_VERSION)
	fmt.sbprintf(&builder, "\"@timestamp\":\"%s\",", timestamp)
	fmt.sbprintf(&builder, "\"timestamp\":\"%s\",", timestamp)
	fmt.sbprintf(&builder, "\"session_id\":\"%s\",", session_id)
	fmt.sbprintf(&builder, "\"agent_id\":\"%s\",", agent_id)
	fmt.sbprintf(&builder, "\"agent_type\":\"%s\",", agent_type)
	fmt.sbprintf(&builder, "\"user_name\":\"%s\",", user_name)
	fmt.sbprintf(&builder, "\"host_name\":\"%s\",", host_name)
	fmt.sbprintf(&builder, "\"role\":\"%s\",", role)
	fmt.sbprintf(&builder, "\"action\":\"command_scan\",")
	fmt.sbprintf(&builder, "\"command\":\"%s\",", command_escaped)
	fmt.sbprintf(&builder, "\"result\":\"%s\",", result)
	fmt.sbprintf(&builder, "\"reason\":\"%s\",", reason)
	fmt.sbprintf(&builder, "\"event_action\":\"command_scan\",")
	fmt.sbprintf(&builder, "\"event_outcome\":\"%s\",", result)
	fmt.sbprintf(&builder, "\"event_category\":\"process\",")
	fmt.sbprintf(&builder, "\"exit_code\":%d", exit_code)
	fmt.sbprintf(&builder, "}")
	return strings.clone(strings.to_string(builder))
}

event_category_for_action :: proc(action: string) -> string {
	switch action {
	case "command_scan":
		return "process"
	case "install", "uninstall":
		return "package"
	case "permission_denied":
		return "security"
	case "config_modify":
		return "configuration"
	}
	return "zephyr"
}

append_line :: proc(path: string, line: string) {
	dir := filepath.dir(path)
	defer delete(dir)
	if !ensure_directory(dir) {
		return
	}

	data := transmute([]u8)line

	if os.exists(path) {
		existing, ok := os.read_entire_file(path)
		if ok {
			combined := make([]u8, len(existing)+len(data)+1)
			copy(combined[:len(existing)], existing)
			copy(combined[len(existing):len(existing)+len(data)], data)
			combined[len(existing)+len(data)] = '\n'
			_ = os.write_entire_file(path, combined)
			delete(existing)
			delete(combined)
			return
		}
	}

	combined := make([]u8, len(data)+1)
	copy(combined[:len(data)], data)
	combined[len(data)] = '\n'
	_ = os.write_entire_file(path, combined)
	delete(combined)
}

cleanup_old_audit_logs :: proc(retention_days: int = 30) {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		return
	}

	audit_base := filepath.join({home, ".zephyr", "audit"})
	defer delete(audit_base)
	if !os.exists(audit_base) {
		return
	}

	cutoff := time.time_add(time.now(), -time.Duration(retention_days * 24 * 60 * 60 * 1e9))

	cleanup_dated_logs(filepath.join({audit_base, "commands"}), cutoff)
	cleanup_dated_logs(filepath.join({audit_base, "operations"}), cutoff)
	cleanup_session_logs(filepath.join({audit_base, "sessions"}), cutoff)
}

cleanup_dated_logs :: proc(base_path: string, cutoff: time.Time) {
	if !os.exists(base_path) {
		return
	}

	cutoff_stamp, ok_cutoff := time.time_to_rfc3339(cutoff, 0, false)
	if !ok_cutoff || len(cutoff_stamp) < 10 {
		return
	}
	cutoff_date := cutoff_stamp[:10]

	dirs, err := os2.read_all_directory_by_path(base_path, context.temp_allocator)
	if err != nil {
		return
	}
	defer os2.file_info_slice_delete(dirs, context.temp_allocator)

	for dir in dirs {
		if dir.type != os2.File_Type.Directory {
			continue
		}

		if len(dir.name) != 10 {
			continue
		}
		if dir.name[4] != '-' || dir.name[7] != '-' {
			continue
		}

		if dir.name < cutoff_date {
			dir_path := filepath.join({base_path, dir.name})
			os2.remove_all(dir_path)
			delete(dir_path)
		}
	}
}

cleanup_session_logs :: proc(base_path: string, cutoff: time.Time) {
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

		parts := strings.split(file.name, "-")
		defer delete(parts)
		if len(parts) < 2 {
			continue
		}

		timestamp_part := strings.trim_suffix(parts[len(parts)-1], ".log")
		file_time, ok := parse_rfc3339_time(timestamp_part)
		if !ok {
			continue
		}

		file_unix := time.time_to_unix(file_time)
		cutoff_unix := time.time_to_unix(cutoff)
		if file_unix < cutoff_unix {
			file_path := filepath.join({base_path, file.name})
			os.remove(file_path)
			delete(file_path)
		}
	}
}

parse_date_yyyy_mm_dd :: proc(value: string) -> (time.Time, bool) {
	if len(value) != 10 {
		return {}, false
	}
	year64, ok_year := strconv.parse_int(value[:4], 10)
	if !ok_year {
		return {}, false
	}
	month64, ok_month := strconv.parse_int(value[5:7], 10)
	if !ok_month {
		return {}, false
	}
	day64, ok_day := strconv.parse_int(value[8:10], 10)
	if !ok_day {
		return {}, false
	}
	year := int(year64)
	month := int(month64)
	day := int(day64)
	if year <= 0 || month <= 0 || day <= 0 {
		return {}, false
	}
	tm, ok_time := time.datetime_to_time(year, time.Month(month), day, 0, 0, 0, 0)
	return tm, ok_time
}

parse_rfc3339_time :: proc(value: string) -> (time.Time, bool) {
	tm, consumed := time.rfc3339_to_time_utc(value)
	if consumed == 0 {
		return {}, false
	}
	return tm, true
}

// audit_unsafe_usage writes an audit record when --unsafe is used.
audit_unsafe_usage :: proc(module_name: string, source: string, result: ^Scan_Result) {
	log_path := audit_log_path()
	if log_path == "" {
		return
	}
	defer delete(log_path)

	audit_module := module_name
	if audit_module == "" && source != "" {
		base := filepath.base(source)
		trimmed := strings.trim_suffix(base, ".git")
		if strings.has_prefix(trimmed, "zephyr-module-") {
			trimmed = strings.trim_prefix(trimmed, "zephyr-module-")
		} else if strings.has_prefix(trimmed, "zephyr-") {
			trimmed = strings.trim_prefix(trimmed, "zephyr-")
		}
		if trimmed != "" {
			audit_module = trimmed
		}
	}

	timestamp := fmt.tprintf("%v", time.now())
	timestamp_escaped := escape_json_string(timestamp)
	module_escaped := escape_json_string(audit_module)
	source_escaped := escape_json_string(source)
	defer {
		delete(timestamp_escaped)
		delete(module_escaped)
		delete(source_escaped)
	}

	critical := 0
	warning := 0
	if result != nil {
		critical = result.critical_count
		warning = result.warning_count
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "{")
	fmt.sbprintf(&builder, "\"timestamp\":\"%s\",", timestamp_escaped)
	fmt.sbprintf(&builder, "\"module\":\"%s\",", module_escaped)
	fmt.sbprintf(&builder, "\"source\":\"%s\",", source_escaped)
	fmt.sbprintf(&builder, "\"critical\":%d,", critical)
	fmt.sbprintf(&builder, "\"warning\":%d", warning)
	fmt.sbprintf(&builder, "}\n")

	line := strings.clone(strings.to_string(builder))
	defer delete(line)

	if !append_audit_line(log_path, line) {
		debug.debug_warn("security audit: failed to write audit log")
	}
}

audit_log_path :: proc() -> string {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		debug.debug_warn("security audit: HOME not set")
		return ""
	}

	zephyr_dir := filepath.join({home, ".zephyr"})
	if zephyr_dir == "" {
		return ""
	}
	defer delete(zephyr_dir)

	if !os.exists(zephyr_dir) {
		os.make_directory(zephyr_dir, 0o755)
		if !os.exists(zephyr_dir) {
			debug.debug_warn("security audit: failed to create %s", zephyr_dir)
			return ""
		}
	}

	return filepath.join({home, ".zephyr", "security.log"})
}

append_audit_line :: proc(path: string, line: string) -> bool {
	data := transmute([]u8)line

	if os.exists(path) {
		existing, ok := os.read_entire_file(path)
		if ok {
			combined := make([]u8, len(existing)+len(data))
			copy(combined[:len(existing)], existing)
			copy(combined[len(existing):], data)
			ok = os.write_entire_file(path, combined)
			delete(existing)
			delete(combined)
			return ok
		}
	}

	return os.write_entire_file(path, data)
}
