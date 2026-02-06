package security

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:text/regex"
import "core:time"

import "../debug"

// Module security scanner with regex-based pattern matching.
// Ownership: all strings stored in Scan_Result and Finding are owned by the caller.

Pattern_Type :: enum {
	Critical,
	Warning,
}

Pattern :: struct {
	type:        Pattern_Type,
	pattern:     string,
	description: string,
}

Finding :: struct {
	pattern:     Pattern,
	file_path:   string,
	line_number: int,
	line_text:   string,
}

Scan_Result :: struct {
	success:        bool,
	critical_count: int,
	warning_count:  int,
	findings:       [dynamic]Finding,
	error_message:  string,
	summary:        Scan_Summary,
}

Scan_Summary :: struct {
	files_scanned: int,
	lines_scanned: int,
	duration_ms:   i64,
}

Scan_Options :: struct {
	unsafe_mode: bool,
	verbose:     bool,
}

Input_Reader :: proc() -> string
input_reader_override: Input_Reader

Compiled_Pattern :: struct {
	pattern: Pattern,
	re:      regex.Regular_Expression,
}

get_critical_patterns :: proc() -> [dynamic]Pattern {
	patterns := make([dynamic]Pattern)
	append(&patterns, Pattern{.Critical, `curl\s+.*\|\s*bash`, "Download and execute via curl"})
	append(&patterns, Pattern{.Critical, `wget\s+.*\|\s*sh`, "Download and execute via wget"})
	append(&patterns, Pattern{.Critical, `eval\s+\$\(curl`, "Remote code execution via eval"})
	append(&patterns, Pattern{.Critical, `base64\s+.*-d.*\|\s*(bash|sh)`, "Obfuscated payload via base64 decode"})
	append(&patterns, Pattern{.Critical, `\$\([^)]*(curl|wget)`, "Command substitution with network fetch"})
	append(&patterns, Pattern{.Critical, `<\([^)]*(curl|wget)`, "Process substitution with network fetch"})
	append(&patterns, Pattern{.Critical, `printf\s+\"\\\\x[0-9a-fA-F]{2}`, "Hex-escaped command construction"})
	append(&patterns, Pattern{.Critical, `xxd\s+-r\s+-p`, "Hex decode pipeline"})
	append(&patterns, Pattern{.Critical, `rm\s+-rf\s+/`, "Destructive filesystem operation"})
	append(&patterns, Pattern{.Critical, `dd\s+if=`, "Low-level disk operation"})
	return patterns
}

get_warning_patterns :: proc() -> [dynamic]Pattern {
	patterns := make([dynamic]Pattern)
	append(&patterns, Pattern{.Warning, `curl\s+http://`, "Insecure HTTP download"})
	append(&patterns, Pattern{.Warning, `chmod\s+\+s`, "Setuid/setgid operation"})
	append(&patterns, Pattern{.Warning, `sudo\s+`, "Privilege escalation"})
	append(&patterns, Pattern{.Warning, `>>\s+~/.zshrc`, "Shell config modification (zsh)"})
	append(&patterns, Pattern{.Warning, `>>\s+~/.bashrc`, "Shell config modification (bash)"})
	return patterns
}

scan_module :: proc(module_path: string, options: Scan_Options) -> Scan_Result {
	result := Scan_Result{success = true}
	if module_path == "" {
		result.success = false
		result.error_message = strings.clone("empty module path")
		return result
	}

	start_time := time.now()

	all_patterns := make([dynamic]Pattern)
	critical_patterns := get_critical_patterns()
	warning_patterns := get_warning_patterns()
	for p in critical_patterns {
		append(&all_patterns, p)
	}
	for p in warning_patterns {
		append(&all_patterns, p)
	}
	delete(critical_patterns)
	delete(warning_patterns)

	compiled, err := compile_patterns(all_patterns[:])
	delete(all_patterns)
	if err != "" {
		result.success = false
		result.error_message = err
		return result
	}
	defer cleanup_compiled_patterns(compiled)

	files := walk_module_files(module_path)
	defer cleanup_string_list(files)
	result.summary.files_scanned = len(files)

	total_lines := 0
	for file_path in files {
		if file_path == "" do continue
		total_lines += scan_file(file_path, compiled[:], &result)
	}

	result.summary.lines_scanned = total_lines
	duration := time.since(start_time)
	result.summary.duration_ms = i64(duration / time.Millisecond)

	return result
}

cleanup_scan_result :: proc(result: ^Scan_Result) {
	if result == nil do return
	for &finding in result.findings {
		if finding.file_path != "" {
			delete(finding.file_path)
		}
		if finding.line_text != "" {
			delete(finding.line_text)
		}
	}
	if result.findings != nil {
		delete(result.findings)
	}
	if result.error_message != "" {
		delete(result.error_message)
	}
	result.findings = nil
	result.error_message = ""
	result.success = false
	result.critical_count = 0
	result.warning_count = 0
	result.summary = Scan_Summary{}
}

format_scan_report :: proc(result: ^Scan_Result, module_name: string) -> string {
	if result == nil || len(result.findings) == 0 {
		return strings.clone("No security findings.")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "Security Issues Detected in module '%s'\n\n", module_name)

	has_critical := result.critical_count > 0
	has_warning := result.warning_count > 0

	if has_critical {
		fmt.sbprintf(&builder, "CRITICAL (blocks installation):\n")
		for finding in result.findings {
			if finding.pattern.type != .Critical do continue
			fmt.sbprintf(&builder, "  ✗ %s\n", finding.pattern.description)
			fmt.sbprintf(&builder, "    Pattern: %s\n", finding.pattern.pattern)
			fmt.sbprintf(&builder, "    File: %s:%d\n", finding.file_path, finding.line_number)
			fmt.sbprintf(&builder, "    Line: %s\n\n", finding.line_text)
		}
	}

	if has_warning {
		fmt.sbprintf(&builder, "WARNINGS (require confirmation):\n")
		for finding in result.findings {
			if finding.pattern.type != .Warning do continue
			fmt.sbprintf(&builder, "  ⚠ %s\n", finding.pattern.description)
			fmt.sbprintf(&builder, "    Pattern: %s\n", finding.pattern.pattern)
			fmt.sbprintf(&builder, "    File: %s:%d\n", finding.file_path, finding.line_number)
			fmt.sbprintf(&builder, "    Line: %s\n\n", finding.line_text)
		}
	}

	if has_critical {
		fmt.sbprintf(&builder, "Installation blocked. Use --unsafe to override if you trust this module.\n")
	}

	return strings.clone(strings.to_string(builder))
}

should_block_install :: proc(result: ^Scan_Result, unsafe_mode: bool) -> bool {
	if result == nil do return false
	if unsafe_mode do return false
	return result.critical_count > 0
}

prompt_user_for_warnings :: proc(
	result: ^Scan_Result,
	module_name: string,
	input_reader: Input_Reader = default_input_reader,
) -> bool {
	if result == nil || result.warning_count == 0 {
		return true
	}

	report := format_scan_report(result, module_name)
	defer delete(report)
	fmt.println(report)

	for {
		fmt.print("Continue with installation? (y/n): ")
		response := input_reader()
		if response == "" {
			return false
		}
		lower := strings.to_lower(response)
		defer delete(lower)
		if lower == "y" || lower == "yes" {
			return true
		}
		if lower == "n" || lower == "no" {
			return false
		}
		fmt.println("Please enter 'y' or 'n'.")
	}
}

default_input_reader :: proc() -> string {
	if input_reader_override != nil {
		return input_reader_override()
	}
	buf: [256]byte
	n, err := os.read(os.stdin, buf[:])
	if err != os.ERROR_NONE || n <= 0 {
		return ""
	}
	return strings.trim_space(string(buf[:n]))
}

// set_input_reader_override installs a test override for prompt input.
set_input_reader_override :: proc(reader: Input_Reader) {
	input_reader_override = reader
}

// clear_input_reader_override removes any prompt input override.
clear_input_reader_override :: proc() {
	input_reader_override = nil
}

scan_file :: proc(file_path: string, patterns: []Compiled_Pattern, result: ^Scan_Result) -> int {
	if result == nil || file_path == "" {
		return 0
	}

	data, ok := os.read_entire_file(file_path)
	if !ok {
		debug.debug_warn("security scan: failed to read %s", file_path)
		return 0
	}
	defer delete(data)

	if is_binary_data(data) {
		return 0
	}

	content := string(data)
	if len(content) == 0 {
		return 0
	}
	line_number := 1
	start := 0
	lines_scanned := 0

	for i := 0; i <= len(content); i += 1 {
		is_end := i == len(content)
		if !is_end && content[i] != '\n' {
			continue
		}

		line := content[start:i]
		start = i + 1

		lines_scanned += 1

		if should_skip_line(line) {
			line_number += 1
			continue
		}

		for compiled in patterns {
			capture, matched := regex.match_and_allocate_capture(compiled.re, line)
			match_start := 0
			if len(capture.pos) > 0 {
				match_start = capture.pos[0][0]
			}
			if capture.groups != nil || capture.pos != nil {
				regex.destroy_capture(capture)
			}

			if matched && !match_is_ignored(line, match_start) {
				append_finding(&result.findings, &result.critical_count, &result.warning_count, compiled.pattern, file_path, line_number, line)
			}
		}

		line_number += 1
	}

	return lines_scanned
}

is_scannable_file :: proc(file_path: string) -> bool {
	if file_path == "" {
		return false
	}

	fi, stat_err := os.stat(file_path)
	if stat_err != os.ERROR_NONE {
		return false
	}
	defer os.file_info_delete(fi)

	if fi.is_dir {
		return false
	}

	if fi.size > 1_048_576 {
		debug.debug_warn("security scan: skipping large file %s", file_path)
		return false
	}

	data, ok := os.read_entire_file(file_path)
	if !ok {
		return false
	}
	defer delete(data)

	if is_binary_data(data) {
		return false
	}

	if has_supported_extension(file_path) {
		return true
	}

	line := first_line(string(data))
	return has_shell_shebang(line)
}

walk_module_files :: proc(module_path: string) -> [dynamic]string {
	paths := make([dynamic]string)
	walk_module_files_internal(module_path, &paths)
	return paths
}

walk_module_files_internal :: proc(dir_path: string, paths: ^[dynamic]string) {
	if dir_path == "" || !os.exists(dir_path) do return

	handle, open_err := os.open(dir_path)
	if open_err != os.ERROR_NONE {
		debug.debug_warn("security scan: unable to open %s", dir_path)
		return
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		debug.debug_warn("security scan: unable to read %s", dir_path)
		return
	}
	defer os.file_info_slice_delete(entries)

	for entry in entries {
		full_path := filepath.join({dir_path, entry.name})
		if entry.is_dir {
			walk_module_files_internal(full_path, paths)
		} else if is_scannable_file(full_path) {
			append(paths, strings.clone(full_path))
		}
		delete(full_path)
	}
}

compile_patterns :: proc(patterns: []Pattern) -> ([dynamic]Compiled_Pattern, string) {
	compiled := make([dynamic]Compiled_Pattern, 0, len(patterns))
	for pattern in patterns {
		re, err := regex.create(pattern.pattern)
		if err != nil {
			message := strings.clone(fmt.tprintf("regex compile failed for '%s': %v", pattern.pattern, err))
			cleanup_compiled_patterns(compiled)
			return nil, message
		}
		append(&compiled, Compiled_Pattern{pattern = pattern, re = re})
	}
	return compiled, ""
}

cleanup_compiled_patterns :: proc(patterns: [dynamic]Compiled_Pattern) {
	for compiled in patterns {
		regex.destroy_regex(compiled.re)
	}
	if patterns != nil {
		delete(patterns)
	}
}

append_finding :: proc(
	findings: ^[dynamic]Finding,
	critical_count: ^int,
	warning_count: ^int,
	pattern: Pattern,
	file_path: string,
	line_number: int,
	line_text: string,
) {
	trimmed_line := strings.trim_space(line_text)
	finding := Finding{
		pattern = pattern,
		file_path = strings.clone(file_path),
		line_number = line_number,
		line_text = strings.clone(trimmed_line),
	}
	append(findings, finding)

	if pattern.type == .Critical {
		critical_count^ += 1
	} else {
		warning_count^ += 1
	}
}

escape_json_string :: proc(value: string) -> string {
	if value == "" {
		return strings.clone("")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for c in value {
		switch c {
		case '"':
			fmt.sbprintf(&builder, "\\\"")
		case '\\':
			fmt.sbprintf(&builder, "\\\\")
		case '\n':
			fmt.sbprintf(&builder, "\\n")
		case '\r':
			fmt.sbprintf(&builder, "\\r")
		case '\t':
			fmt.sbprintf(&builder, "\\t")
		default:
			if c < 0x20 {
				fmt.sbprintf(&builder, "\\u%04x", c)
			} else {
				fmt.sbprintf(&builder, "%c", c)
			}
		}
	}

	return strings.clone(strings.to_string(builder))
}

exit_code_for_scan :: proc(result: ^Scan_Result) -> int {
	if result == nil {
		return 2
	}
	if result.critical_count > 0 {
		return 2
	}
	if result.warning_count > 0 {
		return 1
	}
	return 0
}

format_scan_report_json :: proc(result: ^Scan_Result, source_url: string, commit: string) -> string {
	if result == nil {
		return strings.clone("{\"error\":\"scan_result_nil\"}")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	source_escaped := escape_json_string(source_url)
	commit_escaped := escape_json_string(commit)
	defer {
		delete(source_escaped)
		delete(commit_escaped)
	}

	fmt.sbprintf(&builder, "{")
	fmt.sbprintf(&builder, "\"schema_version\":\"1.0\",")
	fmt.sbprintf(&builder, "\"source\":{\"type\":\"git\",\"url\":\"%s\"", source_escaped)
	if commit != "" {
		fmt.sbprintf(&builder, ",\"commit\":\"%s\"", commit_escaped)
	}
	fmt.sbprintf(&builder, "},")
	fmt.sbprintf(&builder, "\"scan_summary\":{\"files_scanned\":%d,\"lines_scanned\":%d,\"duration_ms\":%d,\"critical_findings\":%d,\"warning_findings\":%d},",
		result.summary.files_scanned,
		result.summary.lines_scanned,
		result.summary.duration_ms,
		result.critical_count,
		result.warning_count,
	)

	policy := "allow"
	if result.critical_count > 0 {
		policy = "block"
	} else if result.warning_count > 0 {
		policy = "warn"
	}
	fmt.sbprintf(&builder, "\"policy_recommendation\":\"%s\",", policy)
	fmt.sbprintf(&builder, "\"exit_code_hint\":%d,", exit_code_for_scan(result))
	fmt.sbprintf(&builder, "\"findings\":[")

	for i in 0..<len(result.findings) {
		finding := result.findings[i]
		if i > 0 {
			fmt.sbprintf(&builder, ",")
		}
		pattern_escaped := escape_json_string(finding.pattern.pattern)
		description_escaped := escape_json_string(finding.pattern.description)
		file_escaped := escape_json_string(finding.file_path)
		snippet_escaped := escape_json_string(finding.line_text)
		severity := "warning"
		bypass := "user_approval"
		if finding.pattern.type == .Critical {
			severity = "critical"
			bypass = "--unsafe"
		}
		fmt.sbprintf(&builder, "{")
		fmt.sbprintf(&builder, "\"severity\":\"%s\",", severity)
		fmt.sbprintf(&builder, "\"pattern\":\"%s\",", pattern_escaped)
		fmt.sbprintf(&builder, "\"description\":\"%s\",", description_escaped)
		fmt.sbprintf(&builder, "\"file\":\"%s\",", file_escaped)
		fmt.sbprintf(&builder, "\"line\":%d,", finding.line_number)
		fmt.sbprintf(&builder, "\"snippet\":\"%s\",", snippet_escaped)
		fmt.sbprintf(&builder, "\"bypass_required\":\"%s\"", bypass)
		fmt.sbprintf(&builder, "}")
		delete(pattern_escaped)
		delete(description_escaped)
		delete(file_escaped)
		delete(snippet_escaped)
	}

	fmt.sbprintf(&builder, "]}")
	return strings.clone(strings.to_string(builder))
}

cleanup_string_list :: proc(list: [dynamic]string) {
	if list == nil do return
	for item in list {
		if item != "" {
			delete(item)
		}
	}
	delete(list)
}

has_supported_extension :: proc(file_path: string) -> bool {
	last_dot := strings.last_index_byte(file_path, '.')
	last_slash := strings.last_index_byte(file_path, '/')
	last_backslash := strings.last_index_byte(file_path, '\\')
	if last_backslash > last_slash {
		last_slash = last_backslash
	}
	if last_dot == -1 || last_dot < last_slash {
		return false
	}

	ext := file_path[last_dot:]
	lower := strings.to_lower(ext)
	defer delete(lower)

	switch lower {
	case ".sh", ".bash", ".zsh", ".fish", ".py", ".rb", ".js":
		return true
	}
	return false
}

first_line :: proc(content: string) -> string {
	idx := strings.index_byte(content, '\n')
	if idx == -1 {
		return content
	}
	return content[:idx]
}

has_shell_shebang :: proc(line: string) -> bool {
	trimmed := strings.trim_space(line)
	if !strings.has_prefix(trimmed, "#!") {
		return false
	}
	lower := strings.to_lower(trimmed)
	defer delete(lower)
	return strings.contains(lower, "sh") || strings.contains(lower, "bash") || strings.contains(lower, "zsh") || strings.contains(lower, "fish")
}

is_binary_data :: proc(data: []byte) -> bool {
	limit := 512
	if len(data) < limit {
		limit = len(data)
	}
	for b in data[:limit] {
		if b == 0 {
			return true
		}
	}
	return false
}

should_skip_line :: proc(line: string) -> bool {
	trimmed := strings.trim_space(line)
	if trimmed == "" {
		return true
	}
	if strings.has_prefix(trimmed, "#") ||
		strings.has_prefix(trimmed, "//") ||
		strings.has_prefix(trimmed, "/*") ||
		strings.has_prefix(trimmed, "*") {
		return true
	}
	return false
}

match_is_ignored :: proc(line: string, match_start: int) -> bool {
	if match_start < 0 {
		return true
	}

	comment_start := find_comment_start(line)
	if comment_start >= 0 && match_start >= comment_start {
		return true
	}

	return match_inside_quotes(line, match_start)
}

find_comment_start :: proc(line: string) -> int {
	in_single := false
	in_double := false
	escaped := false

	for i := 0; i < len(line); i += 1 {
		c := line[i]

		if escaped {
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if c == '"' && !in_single {
			in_double = !in_double
			continue
		}
		if c == '\'' && !in_double {
			in_single = !in_single
			continue
		}
		if in_single || in_double {
			continue
		}

		if c == '#' {
			return i
		}
		if c == '/' && i+1 < len(line) && line[i+1] == '/' {
			return i
		}
	}

	return -1
}

match_inside_quotes :: proc(line: string, match_start: int) -> bool {
	in_single := false
	in_double := false
	escaped := false

	for i := 0; i < len(line) && i < match_start; i += 1 {
		c := line[i]

		if escaped {
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if c == '"' && !in_single {
			in_double = !in_double
			continue
		}
		if c == '\'' && !in_double {
			in_single = !in_single
			continue
		}
	}

	return in_single || in_double
}
