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

Severity :: enum {
	Info,
	Warning,
	Critical,
}

Pattern :: struct {
	severity:    Severity,
	pattern:     string,
	description: string,
}

Finding :: struct {
	pattern:     Pattern,
	severity:    Severity,
	file_path:   string,
	line_number: int,
	line_text:   string,
}

Symlink_Finding :: struct {
	file_path: string,
	real_path: string,
}

Git_Hook_Finding :: struct {
	hook_name:     string,
	file_path:     string,
	is_executable: bool,
	shebang_issue: string,
}

Reverse_Shell_Type :: enum {
	Bash_TCP,
	Bash_UDP,
	Netcat,
	Socat,
	Python,
	Perl,
}

Reverse_Shell_Finding :: struct {
	file_path:   string,
	line_number: int,
	shell_type:  Reverse_Shell_Type,
	line_text:   string,
}

Credential_Type :: enum {
	AWS,
	SSH,
	GPG,
	Docker,
	Kubernetes,
	NPM,
	PyPI,
	RubyGems,
	Cargo,
	Gradle,
	Maven,
	FTP,
	Anthropic_API,
	OpenAI_API,
	Grok_API,
	XAI_API,
	Shell_History,
}

Credential_Finding :: struct {
	file_path:        string,
	line_number:      int,
	credential_type:  Credential_Type,
	has_exfiltration: bool,
	line_text:        string,
}

Scan_Result :: struct {
	success:        bool,
	critical_count: int,
	warning_count:  int,
	info_count:     int,
	findings:       [dynamic]Finding,
	symlink_evasions: [dynamic]Symlink_Finding,
	git_hooks:      [dynamic]Git_Hook_Finding,
	reverse_shell_findings: [dynamic]Reverse_Shell_Finding,
	credential_findings: [dynamic]Credential_Finding,
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

MAX_LINE_LENGTH :: 100_000
MAX_FILE_SIZE :: 1_048_576
MAX_TOTAL_PATTERN_SIZE :: 10_000_000

Input_Reader :: proc() -> string
input_reader_override: Input_Reader

Compiled_Pattern :: struct {
	pattern: Pattern,
	re:      regex.Regular_Expression,
}

get_critical_patterns :: proc() -> [dynamic]Pattern {
	patterns := make([dynamic]Pattern)
	// CVE-2026-24887 patterns
	append(&patterns, Pattern{.Critical, `;\s*\$\(`, "Command substitution injection (CVE-2026-24887)"})
	append(&patterns, Pattern{.Critical, `\|\s*\$\(`, "Pipe with command substitution (CVE-2026-24887)"})
	append(&patterns, Pattern{.Critical, `&&\s*curl`, "Command chaining with curl (CVE-2026-24887)"})
	append(&patterns, Pattern{.Critical, `\|\|\s*wget`, "Command chaining with wget (CVE-2026-24887)"})
	// CVE-2026-25723 patterns
	append(&patterns, Pattern{.Critical, `\|\s*sed.*-e.*\|`, "Chained sed operations (CVE-2026-25723)"})
	append(&patterns, Pattern{.Critical, `sed.*'s/.*\$\([^']*\)'`, "Sed with command substitution (CVE-2026-25723)"})

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
	append(&patterns, Pattern{.Critical, `>\s*/dev/sda`, "Direct disk overwrite (/dev/sda)"})
	append(&patterns, Pattern{.Critical, `>\s*/dev/nvme`, "Direct disk overwrite (/dev/nvme)"})
	append(&patterns, Pattern{.Critical, `ptrace`, "Process inspection/manipulation via ptrace"})
	append(&patterns, Pattern{.Critical, `/proc/[^\\s]+/mem`, "Direct process memory access"})
	append(&patterns, Pattern{.Critical, `LD_PRELOAD`, "Dynamic loader injection (LD_PRELOAD)"})
	append(&patterns, Pattern{.Critical, `DYLD_INSERT_LIBRARIES`, "Dynamic loader injection (DYLD_INSERT_LIBRARIES)"})
	append(&patterns, Pattern{.Critical, `/proc/self/exe`, "Container escape via /proc/self/exe"})
	append(&patterns, Pattern{.Critical, `/proc/\\d+/root`, "Container escape via /proc/<pid>/root"})
	append(&patterns, Pattern{.Critical, `nsenter`, "Namespace escape via nsenter"})
	append(&patterns, Pattern{.Critical, `/sys/fs/cgroup`, "Container escape via cgroup access"})
	reverse_shell_patterns := get_reverse_shell_patterns()
	for p in reverse_shell_patterns {
		append(&patterns, p)
	}
	delete(reverse_shell_patterns)
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

get_credential_patterns :: proc() -> [dynamic]Pattern {
	patterns := make([dynamic]Pattern)

	// AWS credentials
	append(&patterns, Pattern{.Warning, `\.aws/credentials`, "AWS credentials file access"})
	append(&patterns, Pattern{.Warning, `AWS_ACCESS_KEY_ID`, "AWS access key environment variable"})
	append(&patterns, Pattern{.Warning, `AWS_SECRET_ACCESS_KEY`, "AWS secret key environment variable"})

	// SSH keys
	append(&patterns, Pattern{.Warning, `\.ssh/id_rsa`, "SSH private key access (RSA)"})
	append(&patterns, Pattern{.Warning, `\.ssh/id_dsa`, "SSH private key access (DSA)"})
	append(&patterns, Pattern{.Warning, `\.ssh/id_ed25519`, "SSH private key access (Ed25519)"})

	// GPG keys
	append(&patterns, Pattern{.Warning, `\.gnupg`, "GPG key directory access"})

	// Docker credentials
	append(&patterns, Pattern{.Warning, `\.docker/config\.json`, "Docker credentials access"})

	// Kubernetes credentials
	append(&patterns, Pattern{.Warning, `\.kube/config`, "Kubernetes credentials access"})

	// Package manager credentials
	append(&patterns, Pattern{.Warning, `\.npmrc`, "NPM credentials access"})
	append(&patterns, Pattern{.Warning, `\.pypirc`, "PyPI credentials access"})
	append(&patterns, Pattern{.Warning, `\.gem/credentials`, "RubyGems credentials access"})
	append(&patterns, Pattern{.Warning, `\.cargo/credentials`, "Cargo/Rust credentials access"})
	append(&patterns, Pattern{.Warning, `\.gradle/gradle\.properties`, "Gradle credentials access"})
	append(&patterns, Pattern{.Warning, `\.m2/settings\.xml`, "Maven credentials access"})
	append(&patterns, Pattern{.Warning, `\.netrc`, "FTP credentials access"})

	// AI API keys
	append(&patterns, Pattern{.Critical, `ANTHROPIC_API_KEY`, "Anthropic API key access"})
	append(&patterns, Pattern{.Critical, `OPENAI_API_KEY`, "OpenAI API key access"})
	append(&patterns, Pattern{.Critical, `GROK_API_KEY`, "Grok API key access"})
	append(&patterns, Pattern{.Critical, `XAI_API_KEY`, "xAI API key access"})
	append(&patterns, Pattern{.Critical, `anthropic\.com/api`, "Anthropic API endpoint access"})
	append(&patterns, Pattern{.Critical, `openai\.com/api`, "OpenAI API endpoint access"})
	append(&patterns, Pattern{.Critical, `x\.ai/api`, "xAI API endpoint access"})
	append(&patterns, Pattern{.Critical, `\.grok/credentials`, "Grok credentials file access"})

	// Shell history (credential mining)
	append(&patterns, Pattern{.Warning, `~?/\.zsh_history`, "ZSH history access"})
	append(&patterns, Pattern{.Warning, `~?/\.bash_history`, "Bash history access"})
	append(&patterns, Pattern{.Warning, `history\s+\|\s+grep`, "History searching for secrets"})

	return patterns
}

get_reverse_shell_patterns :: proc() -> [dynamic]Pattern {
	patterns := make([dynamic]Pattern)
	append(&patterns, Pattern{.Critical, `/dev/tcp/`, "Reverse shell via /dev/tcp"})
	append(&patterns, Pattern{.Critical, `/dev/udp/`, "Reverse shell via /dev/udp"})
	append(&patterns, Pattern{.Critical, `nc\s+.*-e\s+/bin/sh`, "Reverse shell via netcat (sh)"})
	append(&patterns, Pattern{.Critical, `nc\s+.*-e\s+/bin/bash`, "Reverse shell via netcat (bash)"})
	append(&patterns, Pattern{.Critical, `netcat\s+.*-e`, "Reverse shell via netcat"})
	append(&patterns, Pattern{.Critical, `socat\s+exec:`, "Reverse shell via socat"})
	append(&patterns, Pattern{.Critical, `python.*socket.*subprocess`, "Reverse shell via python"})
	append(&patterns, Pattern{.Critical, `perl.*socket.*open.*STDIN`, "Reverse shell via perl"})
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
	module_root := get_module_directory(module_path)
	if module_root == "" {
		module_root = strings.clone(module_path)
	}
	module_root_real := module_root
	root_real, real_err := os.absolute_path_from_relative(module_root)
	if real_err == os.ERROR_NONE {
		delete(module_root)
		module_root_real = root_real
	}
	defer delete(module_root_real)

	scan_for_git_hooks(module_root_real, &result)
	if len(result.git_hooks) > 0 && !options.unsafe_mode {
		result.success = false
		result.error_message = strings.clone("git hooks detected")
		return result
	}

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

	credential_patterns := get_credential_patterns()
	credential_compiled, credential_err := compile_patterns(credential_patterns[:])
	delete(credential_patterns)
	if credential_err == "" {
		defer cleanup_compiled_patterns(credential_compiled)
	} else {
		debug.debug_warn("security scan: credential pattern compile failed: %s", credential_err)
	}

	files := walk_module_files(module_root_real, &result)
	defer cleanup_string_list(files)
	result.summary.files_scanned = len(files)

	total_lines := 0
	for file_path in files {
		if file_path == "" do continue
		total_lines += scan_file(file_path, compiled[:], credential_compiled[:], credential_err, &result)
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
	for &symlink in result.symlink_evasions {
		if symlink.file_path != "" {
			delete(symlink.file_path)
		}
		if symlink.real_path != "" {
			delete(symlink.real_path)
		}
	}
	if result.symlink_evasions != nil {
		delete(result.symlink_evasions)
	}
	for &hook in result.git_hooks {
		if hook.hook_name != "" {
			delete(hook.hook_name)
		}
		if hook.file_path != "" {
			delete(hook.file_path)
		}
		if hook.shebang_issue != "" {
			delete(hook.shebang_issue)
		}
	}
	if result.git_hooks != nil {
		delete(result.git_hooks)
	}
	for &shell_finding in result.reverse_shell_findings {
		if shell_finding.file_path != "" {
			delete(shell_finding.file_path)
		}
		if shell_finding.line_text != "" {
			delete(shell_finding.line_text)
		}
	}
	if result.reverse_shell_findings != nil {
		delete(result.reverse_shell_findings)
	}
	for &cred_finding in result.credential_findings {
		if cred_finding.file_path != "" {
			delete(cred_finding.file_path)
		}
		if cred_finding.line_text != "" {
			delete(cred_finding.line_text)
		}
	}
	if result.credential_findings != nil {
		delete(result.credential_findings)
	}
	if result.error_message != "" {
		delete(result.error_message)
	}
	result.findings = nil
	result.symlink_evasions = nil
	result.git_hooks = nil
	result.reverse_shell_findings = nil
	result.credential_findings = nil
	result.error_message = ""
	result.success = false
	result.critical_count = 0
	result.warning_count = 0
	result.info_count = 0
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
			if finding.pattern.severity != .Critical do continue
			fmt.sbprintf(&builder, "  ✗ %s\n", finding.pattern.description)
			fmt.sbprintf(&builder, "    Pattern: %s\n", finding.pattern.pattern)
			fmt.sbprintf(&builder, "    File: %s:%d\n", finding.file_path, finding.line_number)
			fmt.sbprintf(&builder, "    Line: %s\n\n", finding.line_text)
		}
	}

	if has_warning {
		fmt.sbprintf(&builder, "WARNINGS (require confirmation):\n")
		for finding in result.findings {
			if finding.pattern.severity != .Warning do continue
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

get_reverse_shell_type_from_pattern :: proc(pattern: Pattern) -> (Reverse_Shell_Type, bool) {
	desc := strings.to_lower(pattern.description)
	switch {
	case strings.contains(desc, "/dev/tcp"):
		return .Bash_TCP, true
	case strings.contains(desc, "/dev/udp"):
		return .Bash_UDP, true
	case strings.contains(desc, "netcat") || strings.contains(desc, "nc"):
		return .Netcat, true
	case strings.contains(desc, "socat"):
		return .Socat, true
	case strings.contains(desc, "python"):
		return .Python, true
	case strings.contains(desc, "perl"):
		return .Perl, true
	}
	return .Bash_TCP, false
}

get_credential_type_from_pattern :: proc(pattern: Pattern) -> Credential_Type {
	desc := strings.to_lower(pattern.description)
	switch {
	case strings.contains(desc, "aws"):
		return .AWS
	case strings.contains(desc, "ssh"):
		return .SSH
	case strings.contains(desc, "gpg"):
		return .GPG
	case strings.contains(desc, "docker"):
		return .Docker
	case strings.contains(desc, "kubernetes"):
		return .Kubernetes
	case strings.contains(desc, "npm"):
		return .NPM
	case strings.contains(desc, "pypi"):
		return .PyPI
	case strings.contains(desc, "rubygems"):
		return .RubyGems
	case strings.contains(desc, "cargo") || strings.contains(desc, "rust"):
		return .Cargo
	case strings.contains(desc, "gradle"):
		return .Gradle
	case strings.contains(desc, "maven"):
		return .Maven
	case strings.contains(desc, "ftp") || strings.contains(desc, "netrc"):
		return .FTP
	case strings.contains(desc, "anthropic"):
		return .Anthropic_API
	case strings.contains(desc, "openai"):
		return .OpenAI_API
	case strings.contains(desc, "grok"):
		return .Grok_API
	case strings.contains(desc, "xai") || strings.contains(desc, "x.ai"):
		return .XAI_API
	case strings.contains(desc, "history"):
		return .Shell_History
	}
	return .AWS
}

check_exfiltration :: proc(line: string) -> bool {
	lower := strings.to_lower(line)
	exfil_patterns := []string{
		"curl", "wget", "post", "nc ", "netcat", "scp", "rsync", "ftp", "tftp",
	}
	for pattern in exfil_patterns {
		if strings.contains(lower, pattern) {
			return true
		}
	}
	return false
}

record_credential_finding :: proc(result: ^Scan_Result, pattern: Pattern, file_path: string, line_number: int, line: string, has_exfiltration: bool) {
	cred_type := get_credential_type_from_pattern(pattern)
	severity := pattern.severity
	if has_exfiltration {
		severity = .Critical
	}
	credential := Credential_Finding{
		file_path = strings.clone(file_path),
		line_number = line_number,
		credential_type = cred_type,
		has_exfiltration = has_exfiltration,
		line_text = strings.clone(line),
	}
	append(&result.credential_findings, credential)

	finding := Finding{
		pattern = pattern,
		severity = severity,
		file_path = strings.clone(file_path),
		line_number = line_number,
		line_text = strings.clone(line),
	}
	append(&result.findings, finding)

	if severity == .Critical {
		result.critical_count += 1
	} else {
		result.warning_count += 1
	}
}

scan_file :: proc(file_path: string, patterns: []Compiled_Pattern, credential_patterns: []Compiled_Pattern, credential_err: string, result: ^Scan_Result) -> int {
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
	in_heredoc := false
	heredoc_marker := ""
	defer {
		if heredoc_marker != "" {
			delete(heredoc_marker)
		}
	}

	for i := 0; i <= len(content); i += 1 {
		is_end := i == len(content)
		if !is_end && content[i] != '\n' {
			continue
		}

		line := content[start:i]
		start = i + 1

		lines_scanned += 1

		if len(line) > MAX_LINE_LENGTH {
			if result != nil {
				oversize := Finding{
					pattern = Pattern{severity = .Warning, pattern = "line_length", description = "Line exceeds max scan length"},
					severity = .Warning,
					file_path = strings.clone(file_path),
					line_number = line_number,
					line_text = strings.clone(fmt.tprintf("len=%d bytes", len(line))),
				}
				append(&result.findings, oversize)
				result.warning_count += 1
			}
			line_number += 1
			continue
		}

		if in_heredoc {
			trimmed := strings.trim_space(line)
			if trimmed == heredoc_marker {
				in_heredoc = false
				delete(heredoc_marker)
				heredoc_marker = ""
			}
			line_number += 1
			continue
		}

		if should_skip_line(line) {
			line_number += 1
			continue
		}

		if is_whitelisted(file_path, line) {
			line_number += 1
			continue
		}

		if credential_err == "" {
			for cred in credential_patterns {
				cred_capture, cred_matched := regex.match_and_allocate_capture(cred.re, line)
				cred_start := 0
				if len(cred_capture.pos) > 0 {
					cred_start = cred_capture.pos[0][0]
				}
				if cred_capture.groups != nil || cred_capture.pos != nil {
					regex.destroy_capture(cred_capture)
				}

				if cred_matched && !match_is_ignored(line, cred_start) {
					has_exfiltration := check_exfiltration(line)
					record_credential_finding(result, cred.pattern, file_path, line_number, line, has_exfiltration)
				}
			}
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
				append_finding(&result.findings, &result.critical_count, &result.warning_count, &result.info_count, compiled.pattern, file_path, line_number, line)
				shell_type, ok := get_reverse_shell_type_from_pattern(compiled.pattern)
				if ok {
					append(&result.reverse_shell_findings, Reverse_Shell_Finding{
						file_path = strings.clone(file_path),
						line_number = line_number,
						shell_type = shell_type,
						line_text = strings.clone(line),
					})
				}
			}
		}

		if marker := parse_heredoc_marker(line); marker != "" {
			if heredoc_marker != "" {
				delete(heredoc_marker)
			}
			heredoc_marker = marker
			in_heredoc = true
		}

		line_number += 1
	}

	return lines_scanned
}

is_scannable_file :: proc(file_path: string, module_root: string, result: ^Scan_Result) -> bool {
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

	if module_root != "" {
		real_path, real_err := os.absolute_path_from_relative(file_path)
		if real_err != os.ERROR_NONE {
			return false
		}
		defer delete(real_path)

		if !path_within_root(real_path, module_root) {
			log_symlink_evasion(file_path, real_path, result)
			return false
		}
	}

	if fi.size > MAX_FILE_SIZE {
		if result != nil {
			oversize := Finding{
				pattern = Pattern{severity = .Warning, pattern = "file_size", description = "File exceeds max scan size (1MB)"},
				severity = .Warning,
				file_path = strings.clone(file_path),
				line_number = 0,
				line_text = strings.clone(fmt.tprintf("size=%d bytes", fi.size)),
			}
			append(&result.findings, oversize)
			result.warning_count += 1
		}
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

	return true
}

walk_module_files :: proc(module_path: string, result: ^Scan_Result) -> [dynamic]string {
	paths := make([dynamic]string)
	walk_module_files_internal(module_path, module_path, result, &paths)
	return paths
}

walk_module_files_internal :: proc(dir_path: string, module_root: string, result: ^Scan_Result, paths: ^[dynamic]string) {
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
		if is_git_metadata_path(full_path) {
			delete(full_path)
			continue
		}
		if entry.is_dir {
			walk_module_files_internal(full_path, module_root, result, paths)
		} else if is_scannable_file(full_path, module_root, result) {
			append(paths, strings.clone(full_path))
		}
		delete(full_path)
	}
}

path_within_root :: proc(path: string, root: string) -> bool {
	if root == "" || path == "" {
		return false
	}
	if path == root {
		return true
	}
	if !strings.has_prefix(path, root) {
		return false
	}
	if len(path) <= len(root) {
		return true
	}
	next := path[len(root)]
	return next == '/' || next == '\\'
}

first_line :: proc(content: string) -> string {
	idx := strings.index_byte(content, '\n')
	if idx == -1 {
		return content
	}
	return content[:idx]
}

log_symlink_evasion :: proc(file_path: string, real_path: string, result: ^Scan_Result) {
	if result == nil {
		return
	}

	symlink := Symlink_Finding{
		file_path = strings.clone(file_path),
		real_path = strings.clone(real_path),
	}
	append(&result.symlink_evasions, symlink)

	pattern := Pattern{
		severity = .Critical,
		pattern = "symlink",
		description = "Symlink points outside module directory",
	}

	finding := Finding{
		pattern = pattern,
		severity = pattern.severity,
		file_path = strings.clone(file_path),
		line_number = 0,
		line_text = strings.clone(real_path),
	}
	append(&result.findings, finding)
	result.critical_count += 1
}

scan_for_git_hooks :: proc(module_root: string, result: ^Scan_Result) {
	if module_root == "" || result == nil {
		return
	}

	hooks_dir := filepath.join({module_root, ".git", "hooks"})
	defer delete(hooks_dir)

	if !os.exists(hooks_dir) {
		return
	}

	handle, open_err := os.open(hooks_dir)
	if open_err != os.ERROR_NONE {
		debug.debug_warn("security scan: unable to open %s", hooks_dir)
		return
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		debug.debug_warn("security scan: unable to read %s", hooks_dir)
		return
	}
	defer os.file_info_slice_delete(entries)

	for entry in entries {
		if entry.is_dir do continue
		if strings.has_suffix(entry.name, ".sample") {
			continue
		}

		hook_path := filepath.join({hooks_dir, entry.name})
		fi, stat_err := os.stat(hook_path)
		if stat_err != os.ERROR_NONE {
			delete(hook_path)
			continue
		}
		is_exec := (fi.mode & 0o111) != 0
		os.file_info_delete(fi)

		shebang_issue := ""
		data, ok := os.read_entire_file(hook_path)
		if ok && len(data) > 2 {
			content := string(data)
			if strings.has_prefix(content, "#!") {
				line := first_line(content)
				lower := strings.to_lower(line)
				defer delete(lower)
				if strings.contains(lower, "python") {
					shebang_issue = strings.clone("Python interpreter hook")
				} else if strings.contains(lower, "perl") {
					shebang_issue = strings.clone("Perl interpreter hook")
				} else if strings.contains(lower, "ruby") {
					shebang_issue = strings.clone("Ruby interpreter hook")
				} else if strings.contains(lower, "node") {
					shebang_issue = strings.clone("Node.js interpreter hook")
				}
			}
			delete(data)
		} else if ok {
			delete(data)
		}

		hook := Git_Hook_Finding{
			hook_name = strings.clone(entry.name),
			file_path = strings.clone(hook_path),
			is_executable = is_exec,
			shebang_issue = shebang_issue,
		}
		append(&result.git_hooks, hook)

		pattern := Pattern{
			severity = .Critical,
			pattern = "git hook",
			description = "Git hook present in module",
		}
		finding := Finding{
			pattern = pattern,
			severity = pattern.severity,
			file_path = strings.clone(hook_path),
			line_number = 0,
			line_text = "",
		}
		append(&result.findings, finding)
		result.critical_count += 1

		delete(hook_path)
	}
}

get_module_directory :: proc(file_path: string) -> string {
	if file_path == "" {
		return ""
	}

	dir := ""
	fi, err := os.stat(file_path)
	if err == os.ERROR_NONE {
		if !fi.is_dir {
			dir = filepath.dir(file_path)
		} else {
			dir = strings.clone(file_path)
		}
		os.file_info_delete(fi)
	} else {
		dir = filepath.dir(file_path)
	}

	start_dir := strings.clone(dir)
	found := false
	for {
		manifest := filepath.join({dir, "module.toml"})
		exists := os.exists(manifest)
		delete(manifest)
		if exists {
			found = true
			break
		}

		parent := filepath.dir(dir)
		if parent == dir {
			delete(parent)
			break
		}
		delete(dir)
		dir = parent
	}

	if !found {
		delete(dir)
		dir = strings.clone(start_dir)
	}
	delete(start_dir)

	result := strings.clone(dir)
	delete(dir)
	return result
}

validate_pattern_set_size :: proc(patterns: []Pattern) -> (ok: bool, message: string) {
	total_size := 0
	for pattern in patterns {
		total_size += len(pattern.pattern)
		if total_size > MAX_TOTAL_PATTERN_SIZE {
			message := strings.clone(fmt.tprintf("pattern set too large: %d bytes (max %d)", total_size, MAX_TOTAL_PATTERN_SIZE))
			return false, message
		}
	}
	return true, ""
}

compile_patterns :: proc(patterns: []Pattern) -> ([dynamic]Compiled_Pattern, string) {
	ok, message := validate_pattern_set_size(patterns)
	if !ok {
		return nil, message
	}
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
	info_count: ^int,
	pattern: Pattern,
	file_path: string,
	line_number: int,
	line_text: string,
) {
	trimmed_line := strings.trim_space(line_text)
	adjusted_pattern := pattern
	if is_documentation_path(file_path) {
		if adjusted_pattern.severity == .Critical {
			adjusted_pattern.severity = .Warning
		} else if adjusted_pattern.severity == .Warning {
			adjusted_pattern.severity = .Info
		}
	}
	finding := Finding{
		pattern = adjusted_pattern,
		severity = adjusted_pattern.severity,
		file_path = strings.clone(file_path),
		line_number = line_number,
		line_text = strings.clone(trimmed_line),
	}
	append(findings, finding)

	if adjusted_pattern.severity == .Critical {
		critical_count^ += 1
	} else if adjusted_pattern.severity == .Warning {
		warning_count^ += 1
	} else {
		info_count^ += 1
	}
}

escape_json_string :: proc(value: string) -> string {
	if value == "" {
		return strings.clone("")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for c in value {
		// Handle special characters
		handled := false
		switch c {
		case '"':
			strings.write_string(&builder, "\\\"")
			handled = true
		case '\\':
			strings.write_string(&builder, "\\\\")
			handled = true
		case '\n':
			strings.write_string(&builder, "\\n")
			handled = true
		case '\r':
			strings.write_string(&builder, "\\r")
			handled = true
		case '\t':
			strings.write_string(&builder, "\\t")
			handled = true
		}
		
		// Handle control characters and normal characters outside switch
		if !handled {
			if c < 0x20 {
				fmt.sbprintf(&builder, "\\u%04x", c)
			} else {
				strings.write_rune(&builder, c)
			}
		}
	}

	result_str := strings.to_string(builder)
	result := strings.clone(result_str)
	return result
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

	strings.write_string(&builder, "{")
	strings.write_string(&builder, "\"schema_version\":\"1.0\",")
	strings.write_string(&builder, "\"source\":{")
	strings.write_string(&builder, "\"type\":\"git\",")
	fmt.sbprintf(&builder, "\"url\":\"%s\"", source_escaped)
	if commit != "" {
		fmt.sbprintf(&builder, ",\"commit\":\"%s\"", commit_escaped)
	}
	strings.write_string(&builder, "},")
	strings.write_string(&builder, "\"scan_summary\":{")
	fmt.sbprintf(&builder, "\"files_scanned\":%d,\"lines_scanned\":%d,\"duration_ms\":%d,\"critical_findings\":%d,\"warning_findings\":%d",
		result.summary.files_scanned,
		result.summary.lines_scanned,
		result.summary.duration_ms,
		result.critical_count,
		result.warning_count,
	)
	strings.write_string(&builder, "},")

	policy := "allow"
	if result.critical_count > 0 {
		policy = "block"
	} else if result.warning_count > 0 {
		policy = "warn"
	}
	fmt.sbprintf(&builder, "\"policy_recommendation\":\"%s\",", policy)
	fmt.sbprintf(&builder, "\"exit_code_hint\":%d,", exit_code_for_scan(result))
	strings.write_string(&builder, "\"findings\":[")

	for i in 0..<len(result.findings) {
		finding := result.findings[i]
		if i > 0 {
			strings.write_string(&builder, ",")
		}
		pattern_escaped := escape_json_string(finding.pattern.pattern)
		description_escaped := escape_json_string(finding.pattern.description)
		file_escaped := escape_json_string(finding.file_path)
		snippet_escaped := escape_json_string(finding.line_text)
		severity := "info"
		bypass := "none"
		if finding.pattern.severity == .Critical {
			severity = "critical"
			bypass = "--unsafe"
		} else if finding.pattern.severity == .Warning {
			severity = "warning"
			bypass = "user_approval"
		}
		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, "\"severity\":\"%s\",", severity)
		fmt.sbprintf(&builder, "\"pattern\":\"%s\",", pattern_escaped)
		fmt.sbprintf(&builder, "\"description\":\"%s\",", description_escaped)
		fmt.sbprintf(&builder, "\"file\":\"%s\",", file_escaped)
		fmt.sbprintf(&builder, "\"line\":%d,", finding.line_number)
		fmt.sbprintf(&builder, "\"snippet\":\"%s\",", snippet_escaped)
		fmt.sbprintf(&builder, "\"bypass_required\":\"%s\"", bypass)
		strings.write_string(&builder, "}")
		delete(pattern_escaped)
		delete(description_escaped)
		delete(file_escaped)
		delete(snippet_escaped)
	}

	strings.write_string(&builder, "]}")
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

is_whitelisted :: proc(file_path: string, line: string) -> bool {
	if !is_documentation_path(file_path) {
		return false
	}
	trimmed := strings.trim_space(line)
	if trimmed == "" {
		return false
	}
	lower := strings.to_lower(trimmed)
	defer delete(lower)

	if strings.contains(lower, "ssh ") || strings.has_prefix(lower, "ssh-") {
		return true
	}
	if strings.contains(lower, "curl") && strings.contains(lower, "example") {
		return true
	}
	return false
}

is_documentation_path :: proc(file_path: string) -> bool {
	if file_path == "" {
		return false
	}
	lower := strings.to_lower(file_path)
	defer delete(lower)

	if strings.contains(lower, "/docs/") || strings.contains(lower, "/example/") || strings.contains(lower, "/examples/") {
		return true
	}
	base := filepath.base(lower)
	return base == "readme.md" || base == "readme"
}

is_git_metadata_path :: proc(file_path: string) -> bool {
	if file_path == "" {
		return false
	}
	lower := strings.to_lower(file_path)
	defer delete(lower)

	if strings.contains(lower, "/.git/") || strings.contains(lower, "\\.git\\") {
		return true
	}
	if strings.has_suffix(lower, "/.git") || strings.has_suffix(lower, "\\.git") {
		return true
	}
	return false
}

parse_heredoc_marker :: proc(line: string) -> string {
	idx := strings.index(line, "<<")
	if idx < 0 {
		return ""
	}
	i := idx + 2
	if i < len(line) && line[i] == '-' {
		i += 1
	}
	for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
		i += 1
	}
	if i >= len(line) {
		return ""
	}

	quote := byte(0)
	if line[i] == '\'' || line[i] == '"' {
		quote = line[i]
		i += 1
	}
	start := i
	if quote != 0 {
		for i < len(line) && line[i] != quote {
			i += 1
		}
		if i == start {
			return ""
		}
		return strings.clone(line[start:i])
	}
	for i < len(line) && line[i] != ' ' && line[i] != '\t' && line[i] != '\r' {
		i += 1
	}
	if i == start {
		return ""
	}
	return strings.clone(line[start:i])
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
