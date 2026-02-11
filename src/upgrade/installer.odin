package upgrade

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../colors"
import "../http"
import "../loader"
import "../security"

install_release :: proc(release: ^Release_Info) -> bool {
	if release == nil {
		colors.print_error("No release selected")
		return false
	}

	platform := detect_platform()
	defer delete(platform)
	if platform == "" {
		colors.print_error("Failed to detect platform")
		return false
	}

	asset := find_asset_for_platform(release, platform)
	if asset == nil {
		colors.print_error("No binary available for platform: %s", platform)
		return false
	}

	colors.print_info("Downloading %s", asset.name)
	binary_data := download_with_progress(asset.download_url, asset.size)
	if binary_data == nil || len(binary_data) == 0 {
		colors.print_error("Failed to download release binary")
		if binary_data != nil {
			delete(binary_data)
		}
		return false
	}
	defer delete(binary_data)

	checksum_url := strings.concatenate({asset.download_url, ".sha256"})
	defer delete(checksum_url)
	expected_checksum := download_checksum(checksum_url)
	if expected_checksum == "" {
		colors.print_error("Failed to download checksum")
		return false
	}
	defer delete(expected_checksum)

	fmt.print("Verifying checksum... ")
	if !verify_checksum(binary_data, expected_checksum) {
		fmt.println("FAILED")
		colors.print_error("Checksum verification failed")
		return false
	}
	fmt.println("OK")

	fmt.println("Installing update...")
	if !install_binary(binary_data) {
		colors.print_error("Failed to install new binary")
		return false
	}

	if !verify_installation() {
		colors.print_error("Installation verification failed")
		return false
	}

	fmt.println("Installation complete.")
	return true
}

detect_platform :: proc() -> string {
	platform := loader.get_current_platform()
	defer loader.cleanup_platform_info(&platform)
	if platform.os == "" || platform.arch == "" {
		return strings.clone("")
	}
	return strings.clone(fmt.tprintf("%s-%s", platform.os, platform.arch))
}

find_asset_for_platform :: proc(release: ^Release_Info, platform: string) -> ^Release_Asset {
	if release == nil || platform == "" || release.assets == nil {
		return nil
	}
	asset_name := fmt.tprintf("zephyr-%s", platform)
	defer delete(asset_name)

	for i in 0..<len(release.assets) {
		asset := &release.assets[i]
		if asset.name == asset_name {
			return asset
		}
		if strings.has_prefix(asset.name, asset_name) {
			return asset
		}
		if strings.contains(asset.name, platform) && strings.contains(asset.name, "zephyr") {
			return asset
		}
	}
	return nil
}

download_with_progress :: proc(url: string, expected_size: int) -> []u8 {
	if url == "" {
		return nil
	}
	headers := []string{
		"Accept: application/octet-stream",
	}
	if expected_size > 0 {
		colors.print_info("Download size: %d bytes", expected_size)
	}
	response := http.get(url, headers, 30)
	defer http.cleanup_http_result(&response)
	if !response.ok || response.status_code < 200 || response.status_code >= 300 {
		if response.error != "" {
			colors.print_error("Download failed: %s", response.error)
		}
		return nil
	}
	if response.body == nil || len(response.body) == 0 {
		colors.print_error("Download returned empty body")
		return nil
	}
	if expected_size > 0 && len(response.body) != expected_size {
		colors.print_warning("Downloaded size mismatch: expected %d, got %d", expected_size, len(response.body))
	}
	print_download_summary(len(response.body), expected_size)
	return response.body
}

print_download_summary :: proc(downloaded: int, expected: int) {
	if downloaded <= 0 {
		return
	}
	if expected <= 0 {
		fmt.printf("Download complete (%d bytes).\n", downloaded)
		return
	}

	percent := int(float64(downloaded) / float64(expected) * 100.0)
	if percent > 100 {
		percent = 100
	}
	bar_width := 20
	filled := percent * bar_width / 100
	bar := make([]u8, bar_width)
	for i := 0; i < bar_width; i += 1 {
		if i < filled {
			bar[i] = '#'
		} else {
			bar[i] = '-'
		}
	}
	fmt.printf("Download complete [%s] %d%% (%d/%d bytes)\n", string(bar[:]), percent, downloaded, expected)
	delete(bar)
}

download_checksum :: proc(url: string) -> string {
	if url == "" {
		return strings.clone("")
	}
	headers := []string{
		"Accept: text/plain",
	}
	resp := http.get(url, headers, 10)
	defer http.cleanup_http_result(&resp)
	if !resp.ok || resp.status_code < 200 || resp.status_code >= 300 {
		return strings.clone("")
	}
	if resp.body == nil || len(resp.body) == 0 {
		return strings.clone("")
	}
	return strings.clone(strings.trim_space(string(resp.body)))
}

verify_checksum :: proc(data: []u8, expected_line: string) -> bool {
	if data == nil || len(data) == 0 || expected_line == "" {
		return false
	}
	fields, err := strings.fields(expected_line)
	if err != .None || len(fields) == 0 {
		if fields != nil {
			delete(fields)
		}
		return false
	}
	expected := strings.to_lower(fields[0])
	delete(fields)
	defer delete(expected)

	hash := security.compute_sha256_bytes(data)
	computed := security.hex_encode(hash[:])
	defer delete(computed)

	return security.constant_time_compare(expected, computed)
}

install_binary :: proc(data: []u8) -> bool {
	current_path := resolve_current_binary()
	defer if current_path != "" { delete(current_path) }
	if current_path == "" {
		return false
	}

	temp_path := strings.concatenate({current_path, ".tmp"})
	backup_path := strings.concatenate({current_path, ".bak"})
	defer delete(temp_path)
	defer delete(backup_path)

	if !os.write_entire_file(temp_path, data) {
		return false
	}

	mode := os.Permissions_Default_File + os.Permissions_Execute_All
	if info, err := os.stat(current_path); err == os.ERROR_NONE {
		mode = info.mode & os.Permissions_All
	}
	_ = os.chmod(temp_path, mode)

	if os.exists(backup_path) {
		_ = os.remove(backup_path)
	}

	if os.exists(current_path) {
		if err := os.rename(current_path, backup_path); err != os.ERROR_NONE {
			_ = os.remove(temp_path)
			return false
		}
	}

	if err := os.rename(temp_path, current_path); err != os.ERROR_NONE {
		if os.exists(backup_path) {
			_ = os.rename(backup_path, current_path)
		}
		_ = os.remove(temp_path)
		return false
	}

	if os.exists(backup_path) {
		_ = os.remove(backup_path)
	}
	return true
}

verify_installation :: proc() -> bool {
	current_path := resolve_current_binary()
	defer if current_path != "" { delete(current_path) }
	if current_path == "" {
		return false
	}
	info, err := os.stat(current_path)
	if err != os.ERROR_NONE {
		return false
	}
	return info.size > 0
}

resolve_current_binary :: proc() -> string {
	if len(os.args) == 0 {
		return strings.clone("")
	}
	arg0 := os.args[0]
	if arg0 == "" {
		return strings.clone("")
	}
	if filepath.is_abs(arg0) {
		return strings.clone(arg0)
	}
	cwd := os.get_current_directory()
	defer if cwd != "" { delete(cwd) }
	if cwd != "" {
		return strings.clone(filepath.join({cwd, arg0}))
	}
	return strings.clone(arg0)
}
