package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"
import "../src/loader"
import "../src/manifest"
import "../src/security"

set_modules_dir_env :: proc(modules_dir: string) -> string {
	original := os.get_env("ZSH_MODULES_DIR")
	os.set_env("ZSH_MODULES_DIR", modules_dir)
	return original
}

restore_modules_dir_env :: proc(original: string) {
	if original != "" {
		os.set_env("ZSH_MODULES_DIR", original)
	} else {
		os.unset_env("ZSH_MODULES_DIR")
	}
	delete(original)
}

@(test)
test_uninstall_integration_graph_and_uninstall :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_integration_graph")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	module_a := filepath.join({modules_dir, "module-a"})
	module_b := filepath.join({modules_dir, "module-b"})
	os.make_directory(module_a)
	os.make_directory(module_b)
	defer delete(module_a)
	defer delete(module_b)

	create_uninstall_test_manifest(module_b, "module-b")
	create_uninstall_test_manifest(module_a, "module-a", []string{"module-b"})
	original_env := set_modules_dir_env(modules_dir)
	defer restore_modules_dir_env(original_env)

	modules := loader.discover(modules_dir)
	testing.expect(t, modules != nil && len(modules) == 2, "should discover modules")
	compatible := loader.filter_compatible_indices(modules)
	resolved, err := loader.resolve_filtered(modules, compatible)
	testing.expect(t, err == "", "resolve_filtered should succeed")
	if err != "" { delete(err) }

	graph := cli.generate_mermaid_graph(resolved, false)
	testing.expect(t, strings.contains(graph, "graph TD"), "graph header should exist")
	testing.expect(t, strings.contains(graph, "module-a"), "graph should include module-a")
	testing.expect(t, strings.contains(graph, "module-b"), "graph should include module-b")
	delete(graph)

	json_bytes, marshal_err := cli.generate_json_with_graph(
		modules_dir,
		modules,
		compatible,
		resolved,
		"",
		false,
		"mermaid",
		false,
	)
	testing.expect(t, marshal_err == nil, "JSON graph should serialize")
	if json_bytes != nil {
		json_str := string(json_bytes)
		testing.expect(t, strings.contains(json_str, "\"dependency_graph\""), "JSON should include dependency_graph")
		delete(json_bytes)
	}

	manifest.cleanup_modules(modules[:])
	delete(modules)
	delete(compatible)
	delete(resolved)

	options := cli.Uninstall_Options{module_name = "module-b"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "should block uninstall with dependents")
	if msg != "" { delete(msg) }

	options.force = true
	options.yes = true
	success, msg = cli.uninstall_module_internal(options)
	testing.expect(t, success, "force uninstall should succeed")
	if msg != "" { delete(msg) }
}

@(test)
test_uninstall_integration_agent_vs_human :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_integration_agent")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir)
	defer delete(modules_dir)

	module_dir := filepath.join({modules_dir, "demo"})
	os.make_directory(module_dir)
	defer delete(module_dir)
	create_uninstall_test_manifest(module_dir, "demo")
	original_env := set_modules_dir_env(modules_dir)
	defer restore_modules_dir_env(original_env)

	security.init_session_registry()
	defer security.cleanup_session_registry()

	os.set_env("ZEPHYR_SESSION_ID", "agent-test-session")
	os.set_env("ZEPHYR_AGENT_ID", "agent-test")
	os.set_env("ZEPHYR_AGENT_TYPE", "test-agent")
	security.register_session("agent-test", "test-agent", "agent-test-session", "parent")
	defer {
		os.unset_env("ZEPHYR_SESSION_ID")
		os.unset_env("ZEPHYR_AGENT_ID")
		os.unset_env("ZEPHYR_AGENT_TYPE")
	}

	options := cli.Uninstall_Options{module_name = "demo", force = true}
	blocked, code, _ := cli.check_agent_uninstall_policy(options)
	testing.expect(t, blocked, "agent force uninstall should be blocked")
	testing.expect(t, code == 0, "agent block should exit 0")

	options.force = false
	blocked, _, _ = cli.check_agent_uninstall_policy(options)
	testing.expect(t, !blocked, "agent uninstall allowed for non-critical without force")

	options.skip_permission = true
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "agent should uninstall non-critical module")
	if msg != "" { delete(msg) }
}
