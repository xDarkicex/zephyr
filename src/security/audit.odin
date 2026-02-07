package security

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "../debug"

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
