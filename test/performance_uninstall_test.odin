package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

import "../src/cli"
import "../src/loader"
import "../src/manifest"

@(test)
test_performance_graph_generation :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	if !require_long_tests() {
		return
	}

	temp_dir := setup_test_environment("perf_uninstall_graph")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	for i in 0..<100 {
		name := fmt.tprintf("mod-%d", i)
		module_dir := filepath.join({modules_dir, name})
		os.make_directory(module_dir)
		create_uninstall_test_manifest(module_dir, name)
		delete(module_dir)
	}

	modules := loader.discover(modules_dir)
	compatible := loader.filter_compatible_indices(modules)
	resolved, err := loader.resolve_filtered(modules, compatible)
	testing.expect(t, err == "", "resolve should succeed")
	if err != "" { delete(err) }

	start := time.now()
	graph := cli.generate_mermaid_graph(resolved, false)
	elapsed := time.since(start)
	fmt.printf("graph generation took: %v\n", elapsed)
	delete(graph)

	testing.expect(t, elapsed < 100*time.Millisecond, "graph generation should be under 100ms")

	manifest.cleanup_modules(modules[:])
	delete(modules)
	delete(compatible)
	delete(resolved)
}

@(test)
test_performance_reverse_deps :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	if !require_long_tests() {
		return
	}

	temp_dir := setup_test_environment("perf_uninstall_reverse")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	for i in 0..<100 {
		name := fmt.tprintf("dep-%d", i)
		module_dir := filepath.join({modules_dir, name})
		os.make_directory(module_dir)
		deps := []string{}
		if i > 0 {
			deps = []string{fmt.tprintf("dep-%d", i-1)}
		}
		create_uninstall_test_manifest(module_dir, name, deps)
		delete(module_dir)
	}

	modules := loader.discover(modules_dir)
	compatible := loader.filter_compatible_indices(modules)
	resolved, err := loader.resolve_filtered(modules, compatible)
	testing.expect(t, err == "", "resolve should succeed")
	if err != "" { delete(err) }

	start := time.now()
	reverse := loader.build_reverse_deps(resolved)
	elapsed := time.since(start)
	fmt.printf("reverse deps build took: %v\n", elapsed)
	loader.cleanup_reverse_deps(reverse)

	testing.expect(t, elapsed < 100*time.Millisecond, "reverse deps should be under 100ms")

	manifest.cleanup_modules(modules[:])
	delete(modules)
	delete(compatible)
	delete(resolved)
}

@(test)
test_performance_uninstall_validation :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)
	if !require_long_tests() {
		return
	}

	temp_dir := setup_test_environment("perf_uninstall_validation")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	module_dir := filepath.join({modules_dir, "single"})
	os.make_directory(module_dir)
	create_uninstall_test_manifest(module_dir, "single")
	delete(module_dir)

	os.set_env("ZSH_MODULES_DIR", modules_dir)
	defer os.unset_env("ZSH_MODULES_DIR")

	start := time.now()
	options := cli.Uninstall_Options{module_name = "single"}
	success, msg := cli.uninstall_module_internal(options)
	elapsed := time.since(start)
	if msg != "" { delete(msg) }

	testing.expect(t, success, "uninstall should succeed")
	fmt.printf("uninstall validation took: %v\n", elapsed)
	testing.expect(t, elapsed < 100*time.Millisecond, "uninstall validation should be under 100ms")
}
