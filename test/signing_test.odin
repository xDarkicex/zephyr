package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "base:runtime"

import "../src/security"
import "../src/git"
import "../src/http"

TEST_DATA :: "zephyr-signing-test"
TEST_PRIVATE_KEY :: `-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIHwxHcTsxxj2VWtbxiu/2YAIOp7xXfBqOZkRV1ETgbTn
-----END PRIVATE KEY-----`

temp_path :: proc(name: string) -> string {
	base_env := os.get_env("TMPDIR")
	base := ""
	if base_env == "" {
		delete(base_env)
		base = strings.clone("/tmp")
	} else {
		base = strings.clone(base_env)
		delete(base_env)
	}
	defer delete(base)

	path := fmt.aprintf("%s/%s", base, name)
	return path
}

write_temp_file :: proc(path: string, content: string) -> bool {
	if path == "" {
		return false
	}
	return os.write_entire_file(path, transmute([]u8)content)
}

sign_with_openssl :: proc(data_path: string, sig_path: string, key_path: string) -> bool {
	if data_path == "" || sig_path == "" || key_path == "" {
		return false
	}
	escaped_key := shell_escape_single(key_path)
	escaped_data := shell_escape_single(data_path)
	escaped_sig := shell_escape_single(sig_path)
	defer delete(escaped_key)
	defer delete(escaped_data)
	defer delete(escaped_sig)
	cmd := fmt.aprintf("openssl pkeyutl -sign -rawin -inkey '%s' -in '%s' -out '%s'",
		escaped_key, escaped_data, escaped_sig)
	defer delete(cmd)
	return run_shell_command(cmd)
}

@(test)
test_verify_signature_valid :: proc(t: ^testing.T) {
	data_path := temp_path("zephyr_signing_data.txt")
	defer delete(data_path)
	defer os.remove(data_path)
	sig_path := temp_path("zephyr_signing_sig.bin")
	defer delete(sig_path)
	defer os.remove(sig_path)
	key_path := temp_path("zephyr_signing_key.pem")
	defer delete(key_path)
	defer os.remove(key_path)

	data := TEST_DATA
	ok := os.write_entire_file(data_path, transmute([]u8)data)
	testing.expect(t, ok, "failed to write test data")
	ok = write_temp_file(key_path, TEST_PRIVATE_KEY)
	testing.expect(t, ok, "failed to write test key")
	testing.expect(t, sign_with_openssl(data_path, sig_path, key_path), "failed to sign data with openssl")

	result := security.verify_signature(data_path, sig_path)
	defer security.cleanup_verification_result(&result)
	testing.expect(t, result.success, "expected valid signature to verify")
}

@(test)
test_verify_signature_invalid :: proc(t: ^testing.T) {
	data_path := temp_path("zephyr_signing_data_bad.txt")
	defer delete(data_path)
	defer os.remove(data_path)
	sig_path := temp_path("zephyr_signing_sig_bad.bin")
	defer delete(sig_path)
	defer os.remove(sig_path)
	key_path := temp_path("zephyr_signing_key_bad.pem")
	defer delete(key_path)
	defer os.remove(key_path)

	data_bad := strings.concatenate({TEST_DATA, "x"})
	defer delete(data_bad)
	ok := os.write_entire_file(data_path, transmute([]u8)data_bad)
	testing.expect(t, ok, "failed to write test data")
	ok = write_temp_file(key_path, TEST_PRIVATE_KEY)
	testing.expect(t, ok, "failed to write test key")
	testing.expect(t, sign_with_openssl(data_path, sig_path, key_path), "failed to sign data with openssl")

	// Tamper with signature to force failure.
	if os.exists(sig_path) {
		sig_bytes, read_ok := os.read_entire_file(sig_path)
		if read_ok && len(sig_bytes) > 0 {
			sig_bytes[0] = sig_bytes[0] ~ 0xff
			_ = os.write_entire_file(sig_path, sig_bytes)
		}
		if sig_bytes != nil {
			delete(sig_bytes)
		}
	}

	result := security.verify_signature(data_path, sig_path)
	defer security.cleanup_verification_result(&result)
	testing.expect(t, !result.success, "expected invalid signature to fail")
}

@(test)
test_verify_hash_valid :: proc(t: ^testing.T) {
	data_path := temp_path("zephyr_hash_data.txt")
	defer delete(data_path)
	defer os.remove(data_path)
	hash_path := temp_path("zephyr_hash_data.txt.sha256")
	defer delete(hash_path)
	defer os.remove(hash_path)

	payload := "zephyr-hash-test"
	ok := os.write_entire_file(data_path, transmute([]u8)payload)
	testing.expect(t, ok, "failed to write test data")

	hash := security.compute_sha256_bytes(transmute([]u8)payload)
	hash_hex := security.hex_encode(hash[:])
	defer delete(hash_hex)

	hash_line := fmt.aprintf("%s  %s", hash_hex, filepath.base(data_path))
	defer delete(hash_line)
	ok = os.write_entire_file(hash_path, transmute([]u8)hash_line)
	testing.expect(t, ok, "failed to write hash file")

	valid, err := security.verify_hash(data_path, hash_path)
	if err != "" {
		defer delete(err)
	}
	testing.expect(t, valid, "expected valid hash to verify")
}

@(test)
test_verify_hash_invalid :: proc(t: ^testing.T) {
	data_path := temp_path("zephyr_hash_data_bad.txt")
	defer delete(data_path)
	defer os.remove(data_path)
	hash_path := temp_path("zephyr_hash_data_bad.txt.sha256")
	defer delete(hash_path)
	defer os.remove(hash_path)

	payload := "zephyr-hash-bad"
	ok := os.write_entire_file(data_path, transmute([]u8)payload)
	testing.expect(t, ok, "failed to write test data")

	hash_line := fmt.aprintf("%s  %s", "deadbeef", filepath.base(data_path))
	defer delete(hash_line)
	ok = os.write_entire_file(hash_path, transmute([]u8)hash_line)
	testing.expect(t, ok, "failed to write hash file")

	valid, err := security.verify_hash(data_path, hash_path)
	if err != "" {
		defer delete(err)
	}
	testing.expect(t, !valid, "expected invalid hash to fail")
}

@(test)
test_verify_hash_invalid_format :: proc(t: ^testing.T) {
	data_path := temp_path("zephyr_hash_data_empty.txt")
	defer delete(data_path)
	defer os.remove(data_path)
	hash_path := temp_path("zephyr_hash_data_empty.txt.sha256")
	defer delete(hash_path)
	defer os.remove(hash_path)

	payload := "zephyr-hash-empty"
	ok := os.write_entire_file(data_path, transmute([]u8)payload)
	testing.expect(t, ok, "failed to write test data")

	ok = os.write_entire_file(hash_path, make([]u8, 0))
	testing.expect(t, ok, "failed to write empty hash file")

	valid, err := security.verify_hash(data_path, hash_path)
	if err != "" {
		defer delete(err)
	}
	testing.expect(t, !valid, "expected invalid hash format to fail")
}

@(test)
test_constant_time_compare :: proc(t: ^testing.T) {
	testing.expect(t, security.constant_time_compare("abc", "abc"), "expected equal strings to compare true")
	testing.expect(t, !security.constant_time_compare("abc", "abd"), "expected mismatch to compare false")
	testing.expect(t, !security.constant_time_compare("abc", "ab"), "expected different lengths to compare false")
}

@(test)
test_hex_encode :: proc(t: ^testing.T) {
	data := []byte{0x00, 0x0f, 0xaa, 0xff}
	expected := "000faaff"
	actual := security.hex_encode(data)
	defer delete(actual)
	testing.expect(t, actual == expected, "expected hex encoding to match")
}

@(test)
test_parse_github_url :: proc(t: ^testing.T) {
	owner, repo := git.parse_github_url("https://github.com/zephyr-systems/zephyr.git")
	defer delete(owner)
	defer delete(repo)
	testing.expect(t, owner == "zephyr-systems", "expected owner parsed from https url")
	testing.expect(t, repo == "zephyr", "expected repo parsed from https url")

	owner2, repo2 := git.parse_github_url("git@github.com:zephyr-systems/zephyr.git")
	defer delete(owner2)
	defer delete(repo2)
	testing.expect(t, owner2 == "zephyr-systems", "expected owner parsed from ssh url")
	testing.expect(t, repo2 == "zephyr", "expected repo parsed from ssh url")
}

@(test)
test_detect_module_source_github_release :: proc(t: ^testing.T) {
	http.set_http_get_override(proc(url: string, headers: []string, timeout_seconds: int) -> http.HTTP_Result {
		result := http.HTTP_Result{ok = true, status_code = 200}
		body := `{"tag_name":"v1.0.0","assets":[{"browser_download_url":"https://github.com/zephyr-systems/zephyr/releases/download/v1.0.0/zephyr-module.tar.gz"}]}`
		result.body = make([]u8, len(body))
		copy(result.body[:], transmute([]u8)body)
		return result
	})
	defer http.clear_http_get_override()

	source := git.Install_Source{
		source_type = .Git_URL,
		url = strings.clone("https://github.com/zephyr-systems/zephyr"),
		valid = true,
	}
	defer git.cleanup_install_source(&source)

	source_type := git.detect_module_source(source)
	testing.expect(t, source_type == .Signed_Tarball, "expected signed tarball detection for release assets")
}

write_module_files :: proc(module_dir: string, module_name: string, init_contents: string) -> bool {
	if module_dir == "" || module_name == "" {
		return false
	}
	if !os.exists(module_dir) {
		os.make_directory(module_dir, 0o755)
	}
	if !os.exists(module_dir) {
		return false
	}

	manifest_path := filepath.join({module_dir, "module.toml"})
	defer delete(manifest_path)
	init_path := filepath.join({module_dir, "init.zsh"})
	defer delete(init_path)

	manifest := fmt.tprintf("[module]\nname = \"%s\"\nversion = \"1.0.0\"\n\n[load]\nfiles = [\"init.zsh\"]\n", module_name)
	defer delete(manifest)

	if !os.write_entire_file(manifest_path, transmute([]u8)manifest) {
		return false
	}
	if !os.write_entire_file(init_path, transmute([]u8)init_contents) {
		return false
	}
	return true
}

create_tarball := proc(base_dir: string, module_name: string, tar_name: string) -> string {
	tarball_path := filepath.join({base_dir, tar_name})
	if tarball_path == "" {
		return ""
	}
	escaped_tar := shell_escape_single(tarball_path)
	escaped_base := shell_escape_single(base_dir)
	escaped_mod := shell_escape_single(module_name)
	defer delete(escaped_tar)
	defer delete(escaped_base)
	defer delete(escaped_mod)

	cmd := fmt.aprintf("tar -czf '%s' -C '%s' '%s'", escaped_tar, escaped_base, escaped_mod)
	defer delete(cmd)
	if !run_shell_command(cmd) {
		delete(tarball_path)
		return ""
	}
	return tarball_path
}

write_hash_file :: proc(tarball_path: string) -> (bool, string) {
	if tarball_path == "" {
		return false, ""
	}
	data, ok := os.read_entire_file(tarball_path)
	if !ok {
		return false, ""
	}
	defer delete(data)

	hash := security.compute_sha256_bytes(data)
	hash_hex := security.hex_encode(hash[:])
	defer delete(hash_hex)
	hash_path := strings.concatenate({tarball_path, ".sha256"})
	line := fmt.aprintf("%s  %s", hash_hex, filepath.base(tarball_path))
	defer delete(line)
	ok = os.write_entire_file(hash_path, transmute([]u8)line)
	return ok, hash_path
}

create_signed_fixture :: proc(t: ^testing.T, module_name: string, init_contents: string) -> (string, string) {
	name := fmt.tprintf("signed_%s", module_name)
	defer delete(name)
	base_dir := setup_test_environment(name)
	module_dir := filepath.join({base_dir, module_name})
	defer delete(module_dir)
	testing.expect(t, write_module_files(module_dir, module_name, init_contents), "failed to write module files")

	tar_name := fmt.tprintf("%s-v1.0.0.tar.gz", module_name)
	defer delete(tar_name)
	tarball := create_tarball(base_dir, module_name, tar_name)
	testing.expect(t, tarball != "", "failed to create tarball")

	key_path := filepath.join({base_dir, "test_key.pem"})
	testing.expect(t, write_temp_file(key_path, TEST_PRIVATE_KEY), "failed to write test private key")

	sig_path := strings.concatenate({tarball, ".sig"})
	defer delete(sig_path)
	testing.expect(t, sign_with_openssl(tarball, sig_path, key_path), "failed to sign tarball")

	ok, hash_path := write_hash_file(tarball)
	testing.expect(t, ok, "failed to write hash file")

	delete(key_path)
	delete(hash_path)
	return base_dir, tarball
}

@(test)
test_signed_install_success :: proc(t: ^testing.T) {
	modules_dir := setup_test_environment("signed_modules_dir")
	defer teardown_test_environment(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	if original_env != "" {
		defer os.set_env("ZSH_MODULES_DIR", original_env)
	} else {
		defer os.unset_env("ZSH_MODULES_DIR")
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	source_dir, tarball := create_signed_fixture(t, "signed-module", "echo 'safe'")
	defer {
		delete(tarball)
		teardown_test_environment(source_dir)
	}

	opts := git.Manager_Options{allow_local = true}
	success, msg := git.install_module(source_dir, opts)
	if msg != "" {
		delete(msg)
	}
	testing.expect(t, success, "expected signed install to succeed")

	installed := filepath.join({modules_dir, "signed-module", "init.zsh"})
	defer delete(installed)
	testing.expect(t, os.exists(installed), "expected module to be installed")
}

@(test)
test_signed_install_tampered_tarball :: proc(t: ^testing.T) {
	modules_dir := setup_test_environment("signed_modules_dir_bad")
	defer teardown_test_environment(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	if original_env != "" {
		defer os.set_env("ZSH_MODULES_DIR", original_env)
	} else {
		defer os.unset_env("ZSH_MODULES_DIR")
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	source_dir, tarball := create_signed_fixture(t, "signed-module-bad", "echo 'safe'")
	defer {
		delete(tarball)
		teardown_test_environment(source_dir)
	}

	// Tamper with tarball after signing.
	if os.exists(tarball) {
		data, ok := os.read_entire_file(tarball)
		if ok {
			tampered := make([]u8, len(data)+5)
			copy(tampered[:len(data)], data)
			_ = runtime.copy_from_string(tampered[len(data):], "evil")
			_ = os.write_entire_file(tarball, tampered)
			delete(tampered)
		}
		if data != nil {
			delete(data)
		}
	}

	opts := git.Manager_Options{allow_local = true}
	success, msg := git.install_module(source_dir, opts)
	if msg != "" {
		delete(msg)
	}
	testing.expect(t, !success, "expected tampered signed install to fail")
}

@(test)
test_signed_install_allows_critical :: proc(t: ^testing.T) {
	modules_dir := setup_test_environment("signed_modules_dir_critical")
	defer teardown_test_environment(modules_dir)

	original_env := os.get_env("ZSH_MODULES_DIR")
	if original_env != "" {
		defer os.set_env("ZSH_MODULES_DIR", original_env)
	} else {
		defer os.unset_env("ZSH_MODULES_DIR")
	}
	os.set_env("ZSH_MODULES_DIR", modules_dir)

	source_dir, tarball := create_signed_fixture(t, "signed-module-critical", "rm -rf /")
	defer {
		delete(tarball)
		teardown_test_environment(source_dir)
	}

	opts := git.Manager_Options{allow_local = true}
	success, msg := git.install_module(source_dir, opts)
	if msg != "" {
		delete(msg)
	}
	testing.expect(t, success, "expected trusted signed module to install despite critical pattern")
}
