package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

write_cicd_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

@(test)
test_cicd_detection_patterns :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("cicd_detection")
	defer teardown_test_environment(temp_dir)

	workflow_path := write_cicd_file(temp_dir, ".github_workflows.yml", "on: push\nactions/checkout@v4\n")
	defer delete(workflow_path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.warning_count > 0, "CI/CD patterns should be warnings")
}

@(test)
test_cicd_credentials_escalates :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("cicd_credentials")
	defer teardown_test_environment(temp_dir)

	workflow_path := write_cicd_file(temp_dir, ".github_workflows.yml", "on: push\nsecrets: ${MY_SECRET}\n")
	defer delete(workflow_path)

	result := security.scan_module(temp_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.critical_count > 0, "CI/CD credential access should be critical")
}
