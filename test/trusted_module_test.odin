package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/security"

write_trusted_file :: proc(dir: string, name: string, content: string) -> string {
	path := strings.concatenate({dir, "/", name})
	os.write_entire_file(path, transmute([]u8)content)
	return path
}

@(test)
test_trusted_module_defaults_apply :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_root := setup_test_environment("trusted_module_default")
	defer teardown_test_environment(temp_root)

	module_dir := filepath.join({temp_root, "oh-my-zsh"})
	os.make_directory(module_dir, 0o755)
	defer delete(module_dir)

	path := write_trusted_file(module_dir, "init.zsh", "cat ~/.aws/credentials")
	defer delete(path)

	result := security.scan_module(module_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.trusted_module_applied, "trusted module flag should be set")
	testing.expect(t, result.info_count > 0, "trusted module should downgrade credential warning to info")
}

@(test)
test_trusted_module_custom_config :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_root := setup_test_environment("trusted_module_config")
	defer teardown_test_environment(temp_root)

	original_home := os.get_env("HOME")
	if original_home != "" {
		defer os.set_env("HOME", original_home)
	} else {
		defer os.unset_env("HOME")
	}
	os.set_env("HOME", temp_root)

	trusted_dir := filepath.join({temp_root, ".zephyr"})
	os.make_directory(trusted_dir, 0o755)
	defer delete(trusted_dir)

	config_path := filepath.join({trusted_dir, "trusted_modules.toml"})
	config_contents := "modules = [\"custom-module\"]"
	os.write_entire_file(config_path, transmute([]u8)config_contents)
	defer delete(config_path)

	module_dir := filepath.join({temp_root, "custom-module"})
	os.make_directory(module_dir, 0o755)
	defer delete(module_dir)

	path := write_trusted_file(module_dir, "init.zsh", "cat ~/.aws/credentials")
	defer delete(path)

	result := security.scan_module(module_dir, security.Scan_Options{})
	defer security.cleanup_scan_result(&result)

	testing.expect(t, result.trusted_module_applied, "custom trusted module should be applied from config")
	testing.expect(t, result.info_count > 0, "custom trusted module should downgrade credential warning to info")
}
