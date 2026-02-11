package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"
import "../src/security"

read_file :: proc(path: string) -> string {
	data, ok := os.read_entire_file(path)
	if !ok {
		return ""
	}
	defer delete(data)
	return strings.clone(string(data))
}

setup_audit_env :: proc(test_name: string) -> (string, string) {
	root_dir := setup_test_environment(test_name)
	modules_dir := filepath.join({root_dir, "modules"})
	os.make_directory(modules_dir)
	return root_dir, modules_dir
}

@(test)
test_uninstall_audit_success :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	root_dir, modules_dir := setup_audit_env("uninstall_audit_success")
	defer teardown_test_environment(root_dir)
	defer delete(modules_dir)

	module_dir := filepath.join({modules_dir, "demo"})
	defer delete(module_dir)
	os.make_directory(module_dir)
	create_uninstall_test_manifest(module_dir, "demo")

	original_home := os.get_env("HOME")
	original_modules := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_modules != "" {
			os.set_env("ZSH_MODULES_DIR", original_modules)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_home)
		delete(original_modules)
	}
	os.set_env("HOME", root_dir)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	options := cli.Uninstall_Options{module_name = "demo"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "should uninstall")
	if msg != "" { delete(msg) }

	log_path := filepath.join({root_dir, ".zephyr", "audit", "operations", security.get_current_date(), "operations.log"})
	data := read_file(log_path)
	defer if data != "" { delete(data) }
	testing.expect(t, strings.contains(data, "\"action\":\"uninstall\""), "audit should log uninstall")
}

@(test)
test_uninstall_audit_blocked :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	root_dir, modules_dir := setup_audit_env("uninstall_audit_blocked")
	defer teardown_test_environment(root_dir)
	defer delete(modules_dir)

	module_a := filepath.join({modules_dir, "module-a"})
	defer delete(module_a)
	module_b := filepath.join({modules_dir, "module-b"})
	defer delete(module_b)
	os.make_directory(module_a)
	os.make_directory(module_b)

	create_uninstall_test_manifest(module_b, "module-b")
	create_uninstall_test_manifest(module_a, "module-a", []string{"module-b"})

	original_home := os.get_env("HOME")
	original_modules := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_modules != "" {
			os.set_env("ZSH_MODULES_DIR", original_modules)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_home)
		delete(original_modules)
	}
	os.set_env("HOME", root_dir)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	options := cli.Uninstall_Options{module_name = "module-b"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "should block uninstall")
	if msg != "" { delete(msg) }

	log_path := filepath.join({root_dir, ".zephyr", "audit", "operations", security.get_current_date(), "operations.log"})
	data := read_file(log_path)
	defer if data != "" { delete(data) }
	testing.expect(t, strings.contains(data, "\"result\":\"failed\""), "audit should log blocked uninstall")
}

@(test)
test_uninstall_audit_agent_blocked :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	root_dir, modules_dir := setup_audit_env("uninstall_audit_agent_blocked")
	defer teardown_test_environment(root_dir)
	defer delete(modules_dir)

	original_home := os.get_env("HOME")
	original_session := os.get_env("ZEPHYR_SESSION_ID")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		if original_session != "" {
			os.set_env("ZEPHYR_SESSION_ID", original_session)
		} else {
			os.unset_env("ZEPHYR_SESSION_ID")
		}
		delete(original_home)
		delete(original_session)
		security.cleanup_session_registry()
	}
	os.set_env("HOME", root_dir)
	os.set_env("ZEPHYR_SESSION_ID", "agent-test-session")
	security.register_session("agent-1", "cursor", "agent-test-session", "parent")

	options := cli.Uninstall_Options{module_name = "stdlib", force = true}
	blocked, _, _ := cli.check_agent_uninstall_policy(options)
	testing.expect(t, blocked, "agent uninstall should be blocked")
	security.log_agent_blocked_uninstall(options.module_name, "force")

	log_path := filepath.join({root_dir, ".zephyr", "audit", "operations", security.get_current_date(), "operations.log"})
	data := read_file(log_path)
	defer if data != "" { delete(data) }
	testing.expect(t, strings.contains(data, "agent_blocked"), "audit should log agent block")
}

@(test)
test_uninstall_audit_failed :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	root_dir, modules_dir := setup_audit_env("uninstall_audit_failed")
	defer teardown_test_environment(root_dir)
	defer delete(modules_dir)

	original_home := os.get_env("HOME")
	defer {
		if original_home != "" {
			os.set_env("HOME", original_home)
		} else {
			os.unset_env("HOME")
		}
		delete(original_home)
	}
	os.set_env("HOME", root_dir)

	options := cli.Uninstall_Options{module_name = "missing"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "should fail uninstall")
	if msg != "" { delete(msg) }

	log_path := filepath.join({root_dir, ".zephyr", "audit", "operations", security.get_current_date(), "operations.log"})
	data := read_file(log_path)
	defer if data != "" { delete(data) }
	testing.expect(t, strings.contains(data, "\"result\":\"failed\""), "audit should log failed uninstall")
}
