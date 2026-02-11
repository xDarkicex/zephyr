package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:testing"

import "../src/cli"

create_module_manifest :: proc(dir_path: string, name: string, required: []string = nil) {
	module_toml := strings.builder_make()
	defer strings.builder_destroy(&module_toml)
	fmt.sbprintf(&module_toml, "[module]\n")
	fmt.sbprintf(&module_toml, "name = \"%s\"\n", name)
	fmt.sbprintf(&module_toml, "version = \"1.0.0\"\n")
	if required != nil && len(required) > 0 {
		fmt.sbprintf(&module_toml, "\n[dependencies]\nrequired = [")
		for dep, idx in required {
			if idx > 0 {
				fmt.sbprintf(&module_toml, ", ")
			}
			fmt.sbprintf(&module_toml, "\"%s\"", dep)
		}
		fmt.sbprintf(&module_toml, "]\n")
	}
	fmt.sbprintf(&module_toml, "\n[load]\nfiles = [\"init.zsh\"]\n")

	manifest_path := filepath.join({dir_path, "module.toml"})
	defer delete(manifest_path)
	os.write_entire_file(manifest_path, transmute([]u8)strings.to_string(module_toml))
}

setup_modules_dir :: proc(test_dir: string) -> string {
	modules_dir := filepath.join({test_dir, "modules"})
	os.make_directory(modules_dir)
	return modules_dir
}

@(test)
test_uninstall_success_no_dependents :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_success")
	defer teardown_test_environment(temp_dir)

	modules_dir := setup_modules_dir(temp_dir)
	defer delete(modules_dir)

	module_dir := filepath.join({modules_dir, "solo"})
	defer delete(module_dir)
	os.make_directory(module_dir)
	create_module_manifest(module_dir, "solo")

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

	options := cli.Uninstall_Options{module_name = "solo"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, success, "should uninstall module with no dependents")
	if msg != "" { delete(msg) }
	testing.expect(t, !os.exists(module_dir), "module directory should be removed")
}

@(test)
test_uninstall_missing_module :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_missing")
	defer teardown_test_environment(temp_dir)

	modules_dir := setup_modules_dir(temp_dir)
	defer delete(modules_dir)

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

	options := cli.Uninstall_Options{module_name = "missing"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "should fail on missing module")
	testing.expect(t, strings.contains(msg, "not found"), "should mention not found")
	if msg != "" { delete(msg) }
}

@(test)
test_uninstall_blocked_by_dependents :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("uninstall_dependents")
	defer teardown_test_environment(temp_dir)

	modules_dir := setup_modules_dir(temp_dir)
	defer delete(modules_dir)

	module_a := filepath.join({modules_dir, "module-a"})
	defer delete(module_a)
	module_b := filepath.join({modules_dir, "module-b"})
	defer delete(module_b)
	os.make_directory(module_a)
	os.make_directory(module_b)

	create_module_manifest(module_b, "module-b")
	create_module_manifest(module_a, "module-a", []string{"module-b"})

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

	options := cli.Uninstall_Options{module_name = "module-b"}
	success, msg := cli.uninstall_module_internal(options)
	testing.expect(t, !success, "should block uninstall when dependents exist")
	testing.expect(t, strings.contains(msg, "dependents"), "should mention dependents")
	if msg != "" { delete(msg) }
	testing.expect(t, os.exists(module_b), "module directory should remain")
}

@(test)
test_uninstall_option_parsing :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	original_args := os.args
	defer os.args = original_args

	os.args = []string{"zephyr", "uninstall", "demo", "--force", "--yes"}
	options := cli.parse_uninstall_options()
	testing.expect(t, options.module_name == "demo", "should parse module name")
	testing.expect(t, options.force, "should parse --force")
	testing.expect(t, options.yes, "should parse --yes")
}
