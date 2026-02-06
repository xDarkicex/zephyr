package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../src/cli"
import "../src/git"

// **Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.6, 9.7**
@(test)
test_cli_git_commands_end_to_end :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	if !git.libgit2_enabled() {
		return
	}

	temp_dir := setup_test_environment("cli_git_commands")
	defer teardown_test_environment(temp_dir)

	modules_dir := filepath.join({temp_dir, "modules"})
	os.make_directory(modules_dir, 0o755)
	defer delete(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	defer restore_modules_env(original_env)
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	bare_dir, module_name := create_bare_repo(t, temp_dir, "zephyr-cli-module", "cli-module", "1.0.0")
	defer {
		if bare_dir != "" { delete(bare_dir) }
		if module_name != "" { delete(module_name) }
	}

	original_args := os.args
	defer os.args = original_args

	os.args = []string{"zephyr", "install", "--local", bare_dir}
	cli.install_command()

	installed_path := filepath.join({modules_dir, "cli-module"})
	testing.expect(t, os.exists(installed_path), "module should be installed")

	update_work := filepath.join({temp_dir, "cli-update-work"})
	testing.expect(t, run_git_cmd(fmt.tprintf("git clone %q %q", bare_dir, update_work)), "clone for update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.email \"test@example.com\"", update_work)), "git config email")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q config user.name \"Test User\"", update_work)), "git config name")

	manifest_path := filepath.join({update_work, "module.toml"})
	updated := "[module]\nname = \"cli-module\"\nversion = \"1.0.1\"\n\n[load]\nfiles = [\"init.zsh\"]\n"
	os.write_entire_file(manifest_path, transmute([]u8)updated)
	delete(manifest_path)

	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q add .", update_work)), "git add update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q commit -m \"update\"", update_work)), "git commit update")
	testing.expect(t, run_git_cmd(fmt.tprintf("git -C %q push", update_work)), "git push update")
	cleanup_test_directory(update_work)
	delete(update_work)

	os.args = []string{"zephyr", "update", "cli-module"}
	cli.update_command()

	manifest_path = filepath.join({installed_path, "module.toml"})
	data, ok := os.read_entire_file(manifest_path)
	testing.expect(t, ok, "read installed manifest after update")
	if ok {
		contents := string(data)
		defer delete(data)
		testing.expect(t, strings.contains(contents, "version = \"1.0.1\""), "update should pull new version")
	}
	delete(manifest_path)

	os.args = []string{"zephyr", "uninstall", "--confirm", "cli-module"}
	cli.uninstall_command()
	testing.expect(t, !os.exists(installed_path), "module should be removed")

	if os.exists(installed_path) {
		cleanup_test_directory(installed_path)
	}
	delete(installed_path)
}
