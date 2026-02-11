package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"
import "../src/security"

@(test)
test_uninstall_agent_force_blocked :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	original_session := os.get_env("ZEPHYR_SESSION_ID")
	defer {
		if original_session != "" {
			os.set_env("ZEPHYR_SESSION_ID", original_session)
		} else {
			os.unset_env("ZEPHYR_SESSION_ID")
		}
		delete(original_session)
		security.cleanup_session_registry()
	}
	os.set_env("ZEPHYR_SESSION_ID", "agent-test-session")
	security.register_session("agent-1", "cursor", "agent-test-session", "parent")

	options := cli.Uninstall_Options{module_name = "demo", force = true}
		blocked, code, _ := cli.check_agent_uninstall_policy(options)
	testing.expect(t, blocked, "agent force should be blocked")
	testing.expect(t, code == 0, "agent force block should exit 0")
}

@(test)
test_uninstall_agent_critical_blocked :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	original_session := os.get_env("ZEPHYR_SESSION_ID")
	defer {
		if original_session != "" {
			os.set_env("ZEPHYR_SESSION_ID", original_session)
		} else {
			os.unset_env("ZEPHYR_SESSION_ID")
		}
		delete(original_session)
		security.cleanup_session_registry()
	}
	os.set_env("ZEPHYR_SESSION_ID", "agent-test-session")
	security.register_session("agent-1", "cursor", "agent-test-session", "parent")

	options := cli.Uninstall_Options{module_name = "stdlib"}
		blocked, code, _ := cli.check_agent_uninstall_policy(options)
	testing.expect(t, blocked, "agent critical uninstall should be blocked")
	testing.expect(t, code == 0, "agent critical block should exit 0")
}

@(test)
test_uninstall_agent_allowed_non_critical :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_agent_allowed")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	defer delete(modules_dir)
	os.make_directory(modules_dir)

	module_dir := filepath.join({modules_dir, "demo"})
	defer delete(module_dir)
	os.make_directory(module_dir)
	create_uninstall_test_manifest(module_dir, "demo")

	original_session := os.get_env("ZEPHYR_SESSION_ID")
	original_modules := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_session != "" {
			os.set_env("ZEPHYR_SESSION_ID", original_session)
		} else {
			os.unset_env("ZEPHYR_SESSION_ID")
		}
		delete(original_session)
		if original_modules != "" {
			os.set_env("ZSH_MODULES_DIR", original_modules)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_modules)
		security.cleanup_session_registry()
	}
	os.set_env("ZEPHYR_SESSION_ID", "agent-test-session")
	security.register_session("agent-1", "cursor", "agent-test-session", "parent")
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	options := cli.Uninstall_Options{module_name = "demo", skip_permission = true}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "agent should be allowed to uninstall non-critical")
	if msg != "" { delete(msg) }
	testing.expect(t, !os.exists(module_dir), "module directory should be removed")
}

@(test)
test_uninstall_agent_with_dependents_blocked :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_agent_dependents")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	defer delete(modules_dir)
	os.make_directory(modules_dir)

	module_a := filepath.join({modules_dir, "module-a"})
	defer delete(module_a)
	module_b := filepath.join({modules_dir, "module-b"})
	defer delete(module_b)
	os.make_directory(module_a)
	os.make_directory(module_b)

	create_uninstall_test_manifest(module_b, "module-b")
	create_uninstall_test_manifest(module_a, "module-a", []string{"module-b"})

	original_session := os.get_env("ZEPHYR_SESSION_ID")
	original_modules := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_session != "" {
			os.set_env("ZEPHYR_SESSION_ID", original_session)
		} else {
			os.unset_env("ZEPHYR_SESSION_ID")
		}
		delete(original_session)
		if original_modules != "" {
			os.set_env("ZSH_MODULES_DIR", original_modules)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_modules)
		security.cleanup_session_registry()
	}
	os.set_env("ZEPHYR_SESSION_ID", "agent-test-session")
	security.register_session("agent-1", "cursor", "agent-test-session", "parent")
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	options := cli.Uninstall_Options{module_name = "module-b", skip_permission = true}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "agent should be blocked by dependents")
	testing.expect(t, strings.contains(msg, "dependents"), "should mention dependents")
	if msg != "" { delete(msg) }
}

@(test)
test_uninstall_human_force_allowed :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_human_force")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	defer delete(modules_dir)
	os.make_directory(modules_dir)

	module_a := filepath.join({modules_dir, "module-a"})
	defer delete(module_a)
	module_b := filepath.join({modules_dir, "module-b"})
	defer delete(module_b)
	os.make_directory(module_a)
	os.make_directory(module_b)

	create_uninstall_test_manifest(module_b, "module-b")
	create_uninstall_test_manifest(module_a, "module-a", []string{"module-b"})

	original_modules := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_modules != "" {
			os.set_env("ZSH_MODULES_DIR", original_modules)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_modules)
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	options := cli.Uninstall_Options{module_name = "module-b", force = true, yes = true}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "human force uninstall should succeed")
	if msg != "" { delete(msg) }
}
