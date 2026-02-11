package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"
import "../src/loader"
import "../src/manifest"
import "../src/security"

@(test)
test_property_graph_is_mermaid :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("property_graph_mermaid")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	for i in 0..<5 {
		name := fmt.tprintf("module-%d", i)
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

	graph := cli.generate_mermaid_graph(resolved, false)
	testing.expect(t, strings.has_prefix(graph, "graph "), "graph should start with mermaid header")
	delete(graph)

	manifest.cleanup_modules(modules[:])
	delete(modules)
	delete(compatible)
	delete(resolved)
}

@(test)
test_property_reverse_deps_match_forward :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("property_reverse_deps")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	module_a := filepath.join({modules_dir, "a"})
	module_b := filepath.join({modules_dir, "b"})
	module_c := filepath.join({modules_dir, "c"})
	os.make_directory(module_a)
	os.make_directory(module_b)
	os.make_directory(module_c)
	create_uninstall_test_manifest(module_c, "c")
	create_uninstall_test_manifest(module_b, "b", []string{"c"})
	create_uninstall_test_manifest(module_a, "a", []string{"b"})
	delete(module_a)
	delete(module_b)
	delete(module_c)

	modules := loader.discover(modules_dir)
	compatible := loader.filter_compatible_indices(modules)
	resolved, err := loader.resolve_filtered(modules, compatible)
	testing.expect(t, err == "", "resolve should succeed")
	if err != "" { delete(err) }

	reverse := loader.build_reverse_deps(resolved)
	defer loader.cleanup_reverse_deps(reverse)
	deps, ok := loader.get_dependents("c", reverse)
	testing.expect(t, ok, "c should have dependents")
	testing.expect(t, len(deps) == 1 && deps[0] == "b", "c should be depended on by b")

	manifest.cleanup_modules(modules[:])
	delete(modules)
	delete(compatible)
	delete(resolved)
}

@(test)
test_property_agent_blocks_consistent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	security.init_session_registry()
	defer security.cleanup_session_registry()

	os.set_env("ZEPHYR_SESSION_ID", "agent-prop-session")
	os.set_env("ZEPHYR_AGENT_ID", "agent-prop")
	os.set_env("ZEPHYR_AGENT_TYPE", "test-agent")
	security.register_session("agent-prop", "test-agent", "agent-prop-session", "parent")
	defer {
		os.unset_env("ZEPHYR_SESSION_ID")
		os.unset_env("ZEPHYR_AGENT_ID")
		os.unset_env("ZEPHYR_AGENT_TYPE")
	}

	options := cli.Uninstall_Options{module_name = "core", force = true}
	blocked, _, _ := cli.check_agent_uninstall_policy(options)
	testing.expect(t, blocked, "agent should be blocked for critical forced uninstall")
}

@(test)
test_property_dependents_block_without_force :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("property_dependents_block")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	module_a := filepath.join({modules_dir, "module-a"})
	module_b := filepath.join({modules_dir, "module-b"})
	os.make_directory(module_a)
	os.make_directory(module_b)
	create_uninstall_test_manifest(module_b, "module-b")
	create_uninstall_test_manifest(module_a, "module-a", []string{"module-b"})
	delete(module_a)
	delete(module_b)

	os.set_env("ZSH_MODULES_DIR", modules_dir)
	defer os.unset_env("ZSH_MODULES_DIR")

	options := cli.Uninstall_Options{module_name = "module-b"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "uninstall should be blocked when dependents exist")
	if msg != "" { delete(msg) }
}

@(test)
test_property_uninstall_logs_event :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("property_uninstall_logs")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	module_dir := filepath.join({modules_dir, "demo"})
	os.make_directory(module_dir)
	create_uninstall_test_manifest(module_dir, "demo")
	delete(module_dir)

	os.set_env("ZSH_MODULES_DIR", modules_dir)
	os.set_env("HOME", temp_dir)
	defer {
		os.unset_env("ZSH_MODULES_DIR")
		os.unset_env("HOME")
	}

	options := cli.Uninstall_Options{module_name = "demo"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "uninstall should succeed")
	if msg != "" { delete(msg) }

	log_path := filepath.join({temp_dir, ".zephyr", "audit", "operations"})
	testing.expect(t, os.exists(log_path), "audit log directory should exist")
	delete(log_path)
	security.cleanup_old_audit_logs(0)
}

@(test)
test_property_exit_codes_consistent :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	security.init_session_registry()
	defer security.cleanup_session_registry()

	os.set_env("ZEPHYR_SESSION_ID", "agent-exit-session")
	os.set_env("ZEPHYR_AGENT_ID", "agent-exit")
	os.set_env("ZEPHYR_AGENT_TYPE", "test-agent")
	security.register_session("agent-exit", "test-agent", "agent-exit-session", "parent")
	defer {
		os.unset_env("ZEPHYR_SESSION_ID")
		os.unset_env("ZEPHYR_AGENT_ID")
		os.unset_env("ZEPHYR_AGENT_TYPE")
	}

	options := cli.Uninstall_Options{module_name = "core", force = true}
	blocked, code, _ := cli.check_agent_uninstall_policy(options)
	testing.expect(t, blocked, "agent force should be blocked")
	testing.expect(t, code == 0, "blocked agent uninstall should exit 0")
}
