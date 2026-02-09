package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../src/security"

write_file :: proc(path: string, contents: string) -> bool {
	data := []u8(contents)
	defer delete(data)
	return os.write_entire_file(path, data)
}

create_perf_module :: proc(base_dir: string, file_count: int, lines_per_file: int) -> (module_dir: string, total_bytes: int) {
	module_dir = filepath.join({base_dir, "perf-module"})
	os.make_directory(module_dir, 0o755)

	module_toml := strings.concatenate({
		"[module]\n",
		"name = \"perf-module\"\n",
		"version = \"0.1.0\"\n\n",
		"[load]\n",
		"files = []\n",
	})
	defer delete(module_toml)

	module_toml_path := filepath.join({module_dir, "module.toml"})
	defer delete(module_toml_path)
	_ = write_file(module_toml_path, module_toml)
	
	payload_line := "export TEST_VAR=\"value\"\n"
	payload_builder := strings.builder_make()
	defer strings.builder_destroy(&payload_builder)
	for _ in 0..<lines_per_file {
		strings.builder_write_string(&payload_builder, payload_line)
	}
	payload := strings.clone(strings.to_string(payload_builder))
	defer delete(payload)

	for i in 0..<file_count {
		file_name := fmt.tprintf("file_%03d.sh", i)
		defer delete(file_name)
		file_path := filepath.join({module_dir, file_name})
		defer delete(file_path)
		_ = write_file(file_path, payload)
		total_bytes += len(payload)
	}
	return
}

estimate_scan_memory :: proc(result: security.Scan_Result, total_bytes: int) -> int {
	// Rough estimate similar to loader benchmarks: result structures + input size.
	bytes := total_bytes
	bytes += len(result.findings) * size_of(security.Finding)
	bytes += len(result.credential_findings) * size_of(security.Credential_Finding)
	bytes += len(result.reverse_shell_findings) * size_of(security.Reverse_Shell_Finding)
	bytes += len(result.symlink_evasions) * size_of(security.Symlink_Evasion)
	bytes += size_of(security.Scan_Result)
	return bytes
}

@(test)
test_phase2_scanner_performance :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	if !require_long_tests() {
		return
	}

	temp_dir := setup_test_environment("phase2_perf_scan")
	defer teardown_test_environment(temp_dir)

	module_dir, total_bytes := create_perf_module(temp_dir, 100, 8)
	defer delete(module_dir)

	start := time.now()
	result := security.scan_module(module_dir, security.Scan_Options{})
	duration := time.since(start)
	security.cleanup_scan_result(&result)

	max_duration := time.Millisecond * 75
	testing.expect(t, duration < max_duration,
		fmt.tprintf("Phase 2 scan should complete < %v for 100 files, got %v", max_duration, duration))

	estimated_memory := estimate_scan_memory(result, total_bytes)
	max_memory := 15 * 1024 * 1024
	testing.expect(t, estimated_memory <= max_memory,
		fmt.tprintf("Estimated scan memory %d bytes exceeds %d bytes", estimated_memory, max_memory))
}

@(test)
test_phase2_pattern_compilation_cached_per_scan :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	if !require_long_tests() {
		return
	}

	temp_dir := setup_test_environment("phase2_perf_cache")
	defer teardown_test_environment(temp_dir)

	module_dir, _ := create_perf_module(temp_dir, 20, 4)
	defer delete(module_dir)

	first_start := time.now()
	result_a := security.scan_module(module_dir, security.Scan_Options{})
	first_duration := time.since(first_start)
	security.cleanup_scan_result(&result_a)

	second_start := time.now()
	result_b := security.scan_module(module_dir, security.Scan_Options{})
	second_duration := time.since(second_start)
	security.cleanup_scan_result(&result_b)

	// Compilation happens once per scan; ensure second run is not wildly slower.
	testing.expect(t, second_duration <= first_duration*2,
		fmt.tprintf("Second scan should not be >2x slower (first=%v, second=%v)", first_duration, second_duration))
}
