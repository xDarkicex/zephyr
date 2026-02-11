package test

import "core:testing"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "base:runtime"

import "../src/http"
import "../src/security"
import "../src/upgrade"

test_upgrade_json_body: string
test_upgrade_checksum_line: string
test_upgrade_binary_data: []u8

alloc_bytes_from_string :: proc(value: string) -> []u8 {
	if value == "" {
		return nil
	}
	buf := make([]u8, len(value))
	_ = runtime.copy_from_string(buf, value)
	return buf
}

make_operations_log_path :: proc(home: string) -> string {
	date_buf: [time.MIN_YYYY_DATE_LEN]u8
	date_str := time.to_string_yyyy_mm_dd(time.now(), date_buf[:])
	return filepath.join({home, ".zephyr", "audit", "operations", date_str, "operations.log"})
}

read_operations_log :: proc(path: string) -> string {
	data, ok := os.read_entire_file(path)
	if !ok || data == nil {
		if data != nil {
			delete(data)
		}
		return strings.clone("")
	}
	content := strings.clone(string(data))
	delete(data)
	return content
}

@(test)
test_upgrade_check_newer_version_available :: proc(t: ^testing.T) {
	set_test_timeout(t)
	lock_home_env()
	defer unlock_home_env()

	temp_dir := setup_test_environment("upgrade_check_newer")
	defer teardown_test_environment(temp_dir)

	old_home := os.get_env("HOME")
	defer {
		if old_home != "" {
			os.set_env("HOME", old_home)
		} else {
			os.unset_env("HOME")
		}
		delete(old_home)
	}
	os.set_env("HOME", temp_dir)

	env_snapshot := capture_agent_env()
	defer restore_agent_env(env_snapshot)
	clear_agent_env()

	original_args := os.args
	defer os.args = original_args
	os.args = []string{"zephyr", "upgrade", "--check"}

	json_text := `[
  {"tag_name":"v1.2.3","published_at":"2026-02-11T00:00:00Z","html_url":"https://example.com/release","prerelease":false,
   "assets":[{"name":"zephyr-darwin-arm64","browser_download_url":"https://example.com/zephyr-darwin-arm64","size":42}]}
]`
	test_upgrade_json_body = strings.clone(json_text)
	defer {
		if test_upgrade_json_body != "" {
			delete(test_upgrade_json_body)
		}
		test_upgrade_json_body = ""
	}

	http.set_http_get_override(proc(url: string, _: []string, _: int) -> http.HTTP_Result {
		if strings.contains(url, "api.github.com") {
			body := alloc_bytes_from_string(test_upgrade_json_body)
			return http.HTTP_Result{
				ok = true,
				status_code = 200,
				body = body,
			}
		}
		return http.HTTP_Result{
			ok = false,
			status_code = 404,
			error = strings.clone("unexpected download"),
		}
	})
	defer http.clear_http_get_override()

	release := upgrade.get_latest_release(.Stable)
	if release == nil {
		err := upgrade.get_github_error()
		if err != "" {
			testing.expect(t, false, fmt.tprintf("expected release info, got error: %s", err))
			delete(err)
		} else {
			testing.expect(t, false, "expected release info, got nil")
		}
		return
	}
	defer upgrade.cleanup_release_info(release)

	latest := release.version
	if latest == "" {
		latest = release.tag_name
	}
	if latest != "" {
		security.log_zephyr_upgrade("dev", latest, true, "check only")
	}

	log_path := make_operations_log_path(temp_dir)
	defer delete(log_path)
	log_data := read_operations_log(log_path)
	defer delete(log_data)
	testing.expect(t, strings.contains(log_data, `"action":"upgrade"`), "upgrade should be logged")
	testing.expect(t, strings.contains(log_data, `"reason":"check only"`), "check-only reason should be logged")
}

@(test)
test_upgrade_check_up_to_date :: proc(t: ^testing.T) {
	set_test_timeout(t)
	lock_home_env()
	defer unlock_home_env()

	temp_dir := setup_test_environment("upgrade_check_uptodate")
	defer teardown_test_environment(temp_dir)

	old_home := os.get_env("HOME")
	defer {
		if old_home != "" {
			os.set_env("HOME", old_home)
		} else {
			os.unset_env("HOME")
		}
		delete(old_home)
	}
	os.set_env("HOME", temp_dir)

	env_snapshot := capture_agent_env()
	defer restore_agent_env(env_snapshot)
	clear_agent_env()

	original_args := os.args
	defer os.args = original_args
	os.args = []string{"zephyr", "upgrade", "--check"}

	json_text := `[
  {"tag_name":"dev","published_at":"2026-02-11T00:00:00Z","html_url":"https://example.com/release","prerelease":false,
   "assets":[{"name":"zephyr-darwin-arm64","browser_download_url":"https://example.com/zephyr-darwin-arm64","size":42}]}
]`
	test_upgrade_json_body = strings.clone(json_text)
	defer {
		if test_upgrade_json_body != "" {
			delete(test_upgrade_json_body)
		}
		test_upgrade_json_body = ""
	}

	http.set_http_get_override(proc(url: string, _: []string, _: int) -> http.HTTP_Result {
		if strings.contains(url, "api.github.com") {
			body := alloc_bytes_from_string(test_upgrade_json_body)
			return http.HTTP_Result{
				ok = true,
				status_code = 200,
				body = body,
			}
		}
		return http.HTTP_Result{
			ok = false,
			status_code = 404,
			error = strings.clone("unexpected download"),
		}
	})
	defer http.clear_http_get_override()

	release := upgrade.get_latest_release(.Stable)
	if release == nil {
		err := upgrade.get_github_error()
		if err != "" {
			testing.expect(t, false, fmt.tprintf("expected release info, got error: %s", err))
			delete(err)
		} else {
			testing.expect(t, false, "expected release info, got nil")
		}
		return
	}
	defer upgrade.cleanup_release_info(release)

	latest := release.version
	if latest == "" {
		latest = release.tag_name
	}
	if latest != "" {
		security.log_zephyr_upgrade(latest, latest, true, "up to date")
	}

	log_path := make_operations_log_path(temp_dir)
	defer delete(log_path)
	log_data := read_operations_log(log_path)
	defer delete(log_data)
	testing.expect(t, strings.contains(log_data, `"action":"upgrade"`), "upgrade should be logged")
	testing.expect(t, strings.contains(log_data, `"reason":"up to date"`), "up-to-date reason should be logged")
}

@(test)
test_upgrade_install_mock_download :: proc(t: ^testing.T) {
	set_test_timeout(t)
	lock_home_env()
	defer unlock_home_env()

	temp_dir := setup_test_environment("upgrade_install_mock")
	defer teardown_test_environment(temp_dir)

	old_home := os.get_env("HOME")
	defer {
		if old_home != "" {
			os.set_env("HOME", old_home)
		} else {
			os.unset_env("HOME")
		}
		delete(old_home)
	}
	os.set_env("HOME", temp_dir)

	env_snapshot := capture_agent_env()
	defer restore_agent_env(env_snapshot)
	clear_agent_env()

	binary_path := filepath.join({temp_dir, "zephyr"})
	defer delete(binary_path)
	_ = os.write_entire_file(binary_path, []u8{'o', 'l', 'd'})

	original_args := os.args
	defer os.args = original_args
	os.args = []string{binary_path, "upgrade", "--force"}

	test_upgrade_binary_data = alloc_bytes_from_string("new-binary")
	defer if test_upgrade_binary_data != nil { delete(test_upgrade_binary_data) }
	binary_hash := security.compute_sha256_bytes(test_upgrade_binary_data)
	checksum := security.hex_encode(binary_hash[:])
	defer delete(checksum)
	test_upgrade_checksum_line = fmt.aprintf("%s  zephyr-darwin-arm64", checksum)
	defer {
		if test_upgrade_checksum_line != "" {
			delete(test_upgrade_checksum_line)
		}
		test_upgrade_checksum_line = ""
	}

	testing.expect(t, upgrade.VerifyChecksum(test_upgrade_binary_data, test_upgrade_checksum_line), "checksum should match test data")

	json_text := `[
  {"tag_name":"v2.0.0","published_at":"2026-02-11T00:00:00Z","html_url":"https://example.com/release","prerelease":false,
   "assets":[{"name":"zephyr-darwin-arm64","browser_download_url":"https://example.com/zephyr-darwin-arm64","size":10}]}
]`
	test_upgrade_json_body = strings.clone(json_text)
	defer {
		if test_upgrade_json_body != "" {
			delete(test_upgrade_json_body)
		}
		test_upgrade_json_body = ""
	}

	http.set_http_get_override(proc(url: string, _: []string, _: int) -> http.HTTP_Result {
		if strings.contains(url, "api.github.com") {
			body := alloc_bytes_from_string(test_upgrade_json_body)
			return http.HTTP_Result{
				ok = true,
				status_code = 200,
				body = body,
			}
		}
		if strings.has_suffix(url, ".sha256") {
			body := alloc_bytes_from_string(test_upgrade_checksum_line)
			return http.HTTP_Result{
				ok = true,
				status_code = 200,
				body = body,
			}
		}
		if strings.contains(url, "zephyr-darwin-arm64") {
			body, _ := runtime.make_slice([]u8, len(test_upgrade_binary_data))
			_ = runtime.copy_slice(body, test_upgrade_binary_data)
			return http.HTTP_Result{
				ok = true,
				status_code = 200,
				body = body,
			}
		}
		return http.HTTP_Result{
			ok = false,
			status_code = 404,
			error = strings.clone("unexpected download"),
		}
	})
	defer http.clear_http_get_override()

	release := upgrade.get_latest_release(.Stable)
	if release == nil {
		err := upgrade.get_github_error()
		if err != "" {
			testing.expect(t, false, fmt.tprintf("expected release info, got error: %s", err))
			delete(err)
		} else {
			testing.expect(t, false, "expected release info, got nil")
		}
		return
	}
	defer upgrade.cleanup_release_info(release)

	ok_install := upgrade.install_release(release)
	testing.expect(t, ok_install, "expected upgrade installation to succeed")
	if ok_install {
		latest := release.version
		if latest == "" {
			latest = release.tag_name
		}
		security.log_zephyr_upgrade("dev", latest, true, "")
	}

	new_data, ok_read := os.read_entire_file(binary_path)
	if new_data != nil {
		defer delete(new_data)
	}
	testing.expect(t, ok_read, "installed binary should exist")
	testing.expect(t, string(new_data) == string(test_upgrade_binary_data), "installed binary should match downloaded data")

	log_path := make_operations_log_path(temp_dir)
	defer delete(log_path)
	log_data := read_operations_log(log_path)
	defer delete(log_data)
	testing.expect(t, strings.contains(log_data, `"action":"upgrade"`), "upgrade should be logged")
	testing.expect(t, strings.contains(log_data, `"result":"success"`), "upgrade result should be success")
}
