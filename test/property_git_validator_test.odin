package test

import "core:os"
import "core:path/filepath"
import "core:fmt"
import "core:testing"
import "core:strings"

import "../src/git"
import "../src/loader"

@(test)
test_property_git_validation_pipeline :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_validation_pipeline")
	defer teardown_test_environment(temp_dir)

	module_dir := filepath.join({temp_dir, "module"})
	os.make_directory(module_dir, 0o755)
	defer delete(module_dir)

	result := git.validate_module(module_dir, "")
	testing.expect(t, !result.valid, "missing manifest should fail validation")
	testing.expect(t, result.error == .No_Manifest, "expected No_Manifest error")
	git.cleanup_validation_result(&result)

	manifest_path := filepath.join({module_dir, "module.toml"})
	invalid_content := "invalid"
	os.write_entire_file(manifest_path, transmute([]u8)invalid_content)
	delete(manifest_path)

	result = git.validate_module(module_dir, "")
	testing.expect(t, !result.valid, "invalid manifest should fail validation")
	testing.expect(t, result.error == .Invalid_Manifest, "expected Invalid_Manifest error")
	git.cleanup_validation_result(&result)
}

@(test)
test_property_git_validation_missing_name :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_validation_missing_name")
	defer teardown_test_environment(temp_dir)

	module_dir := filepath.join({temp_dir, "module"})
	os.make_directory(module_dir, 0o755)
	defer delete(module_dir)

	manifest_path := filepath.join({module_dir, "module.toml"})
	missing_name := "[module]\nversion = \"1.0.0\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)missing_name)
	delete(manifest_path)

	result := git.validate_module(module_dir, "")
	defer git.cleanup_validation_result(&result)
	testing.expect(t, !result.valid, "missing name should fail validation")
	testing.expect(t, result.error == .Invalid_Manifest, "expected Invalid_Manifest error")
}

@(test)
test_property_git_validation_name_mismatch_warning :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_validation_name_mismatch")
	defer teardown_test_environment(temp_dir)

	module_dir := filepath.join({temp_dir, "module"})
	os.make_directory(module_dir, 0o755)
	defer delete(module_dir)

	manifest_path := filepath.join({module_dir, "module.toml"})
	name_mismatch := "[module]\nname = \"actual-name\"\nversion = \"1.0.0\"\n"
	os.write_entire_file(manifest_path, transmute([]u8)name_mismatch)
	delete(manifest_path)

	result := git.validate_module(module_dir, "expected-name")
	defer git.cleanup_validation_result(&result)
	testing.expect(t, result.valid, "name mismatch should not fail validation")
	testing.expect(t, result.warning != "", "name mismatch should produce warning")
}

@(test)
test_property_git_validation_platform_and_files :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_validation_platform_files")
	defer teardown_test_environment(temp_dir)

	module_dir := filepath.join({temp_dir, "module"})
	os.make_directory(module_dir, 0o755)
	defer delete(module_dir)

	platform := loader.get_current_platform()
	defer loader.cleanup_platform_info(&platform)

	manifest_path := filepath.join({module_dir, "module.toml"})
	content := "[module]\nname = \"platform-test\"\nversion = \"1.0.0\"\n\n[platforms]\nos = [\"nope-os\"]\n"
	os.write_entire_file(manifest_path, transmute([]u8)content)
	delete(manifest_path)

	result := git.validate_module(module_dir, "")
	testing.expect(t, !result.valid, "incompatible platform should fail validation")
	testing.expect(t, result.error == .Platform_Incompatible, "expected Platform_Incompatible error")
	git.cleanup_validation_result(&result)

	manifest_path = filepath.join({module_dir, "module.toml"})
    content = strings.clone(fmt.tprintf("[module]\nname = \"platform-test\"\nversion = \"1.0.0\"\n\n[platforms]\nos = [\"%s\"]\n\n[load]\nfiles = [\"missing.zsh\"]\n", platform.os))
    os.write_entire_file(manifest_path, transmute([]u8)content)
    delete(content)
	delete(manifest_path)

	result = git.validate_module(module_dir, "")
	testing.expect(t, !result.valid, "missing load files should fail validation")
	testing.expect(t, result.error == .Missing_Files, "expected Missing_Files error")
	testing.expect(t, len(result.missing_files) == 1, "missing files list should contain one entry")
	git.cleanup_validation_result(&result)
}
