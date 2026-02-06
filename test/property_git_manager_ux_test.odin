package test

import "core:strings"
import "core:testing"
import "core:fmt"
import "core:os"
import "core:path/filepath"

import "../src/git"
import "../src/errors"

// **Property 32: Operation progress indicators**
// **Validates: Requirements 8.1, 8.3, 8.4**
@(test)
test_property_git_operation_progress_indicators :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	install_msg := git.format_install_success("demo-module")
	update_msg := git.format_update_success("demo-module")
	uninstall_msg := git.format_uninstall_success("demo-module")

	install_norm := normalize_output_git_ux(install_msg)
	update_norm := normalize_output_git_ux(update_msg)
	uninstall_norm := normalize_output_git_ux(uninstall_msg)

	testing.expect(t, strings.contains(install_norm, "Installation complete"), "install output should include completion")
	testing.expect(t, strings.contains(install_norm, "Next steps"), "install output should include next steps")
	testing.expect(t, strings.contains(update_norm, "Update complete"), "update output should include completion")
	testing.expect(t, strings.contains(uninstall_norm, "Uninstall complete"), "uninstall output should include completion")

	delete(install_msg)
	delete(update_msg)
	delete(uninstall_msg)
	delete(install_norm)
	delete(update_norm)
	delete(uninstall_norm)
}

// **Property 33: Verbose mode detail**
// **Validates: Requirements 8.5**
@(test)
test_property_git_verbose_mode_detail :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	temp_dir := setup_test_environment("git_uninstall_verbose")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	module_path := create_test_module_dir(modules_dir, "verbose-module")
	defer {
		if module_path != "" {
			cleanup_test_directory(module_path)
			delete(module_path)
		}
	}

	ok, msg := git.uninstall_module("verbose-module", git.Manager_Options{verbose = true})
	testing.expect(t, ok, fmt.tprintf("uninstall should succeed with verbose: %s", msg))
	if msg != "" {
		delete(msg)
	}
}

// **Property 34: Batch operation summary**
// **Validates: Requirements 8.6**
@(test)
test_property_git_batch_operation_summary :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	items := make([dynamic]string)
	append(&items, strings.clone("✓ demo-module"))
	append(&items, strings.clone("✗ bad-module: fetch failed"))

	summary := errors.format_summary("UPDATE SUMMARY", items[:], 1, 1)
	normalized := normalize_output_git_ux(summary)

	testing.expect(t, strings.contains(normalized, "UPDATE SUMMARY"), "summary should include title")
	testing.expect(t, strings.contains(normalized, "Total:"), "summary should include total")
	testing.expect(t, strings.contains(normalized, "Success:"), "summary should include success count")
	testing.expect(t, strings.contains(normalized, "Errors:"), "summary should include error count")

	git.cleanup_manager_results(items[:])
	delete(summary)
	delete(normalized)
}

normalize_output_git_ux :: proc(input: string) -> string {
	if input == "" {
		return strings.clone("")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	i := 0
	for i < len(input) {
		c := input[i]

		if c == 0 {
			i += 1
			continue
		}

		if c == 0x1b { // ESC
			i += 1
			if i < len(input) && input[i] == '[' {
				i += 1
				for i < len(input) && input[i] != 'm' {
					i += 1
				}
				if i < len(input) {
					i += 1
				}
				continue
			}
		}

		if c < 0x20 {
			i += 1
			continue
		}

		fmt.sbprintf(&builder, "%c", c)
		i += 1
	}

	return strings.clone(strings.to_string(builder))
}
