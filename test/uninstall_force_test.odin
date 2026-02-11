package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"

test_confirm_yes :: proc() -> string {
	return strings.clone("y")
}

test_confirm_no :: proc() -> string {
	return strings.clone("n")
}

@(test)
test_uninstall_force_with_dependents_confirmed :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_force_yes")
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

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_env != "" {
			os.set_env("ZSH_MODULES_DIR", original_env)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_env)
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	original_reader := cli.confirm_reader
	defer cli.confirm_reader = original_reader
	cli.confirm_reader = test_confirm_yes

	options := cli.Uninstall_Options{module_name = "module-b", force = true}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "should uninstall when confirmed")
	if msg != "" { delete(msg) }
	testing.expect(t, !os.exists(module_b), "module directory should be removed")
}

@(test)
test_uninstall_force_with_dependents_declined :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_force_no")
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

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_env != "" {
			os.set_env("ZSH_MODULES_DIR", original_env)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_env)
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	original_reader := cli.confirm_reader
	defer cli.confirm_reader = original_reader
	cli.confirm_reader = test_confirm_no

	options := cli.Uninstall_Options{module_name = "module-b", force = true}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "should cancel uninstall when declined")
	if msg != "" { delete(msg) }
	testing.expect(t, os.exists(module_b), "module directory should remain")
}

@(test)
test_uninstall_force_yes_skips_prompt :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_force_skip")
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

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer {
		if original_env != "" {
			os.set_env("ZSH_MODULES_DIR", original_env)
		} else {
			os.unset_env("ZSH_MODULES_DIR")
		}
		delete(original_env)
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	options := cli.Uninstall_Options{module_name = "module-b", force = true, yes = true}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "should uninstall when --yes is set")
	if msg != "" { delete(msg) }
	testing.expect(t, !os.exists(module_b), "module directory should be removed")
}

@(test)
test_uninstall_force_critical_module_warning :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	// Exercise critical-module warning path (stdlib is critical).
	confirmed := cli.show_force_warning("stdlib", []string{"dependent"}, true)
	testing.expect(t, confirmed, "should allow uninstall when skipping prompt")
}
