package git

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../colors"
import "../debug"
import "../http"
import "../loader"
import "../security"

Tarball_Install_Result :: struct {
	success: bool,
	message: string,
}

cleanup_tarball_install_result :: proc(result: ^Tarball_Install_Result) {
	if result == nil do return
	if result.message != "" {
		delete(result.message)
		result.message = ""
	}
	result.success = false
}

install_from_tarball :: proc(source: Install_Source, options: Manager_Options) -> Tarball_Install_Result {
	result := Tarball_Install_Result{}

	if source.url == "" {
		result.message = strings.clone("empty source URL")
		return result
	}

	temp_dir := create_temp_install_dir("zephyr-signed")
	if temp_dir == "" {
		result.message = strings.clone("failed to create temp directory")
		return result
	}

	tarball_path := ""
	hash_path := ""
	sig_path := ""
	defer {
		if tarball_path != "" { delete(tarball_path) }
		if hash_path != "" { delete(hash_path) }
		if sig_path != "" { delete(sig_path) }
		cleanup_temp(temp_dir)
		delete(temp_dir)
	}

	if source.source_type == .Local_Path {
		local_tar := find_signed_tarball(source.url)
		if local_tar == "" {
			result.message = strings.clone("no signed tarball found in directory")
			return result
		}
		defer delete(local_tar)

		tarball_path = filepath.join({temp_dir, "module.tar.gz"})
		hash_path = strings.concatenate({tarball_path, ".sha256"})
		sig_path = strings.concatenate({tarball_path, ".sig"})

		local_hash := strings.concatenate({local_tar, ".sha256"})
		local_sig := strings.concatenate({local_tar, ".sig"})
		defer delete(local_hash)
		defer delete(local_sig)

		if !copy_file(local_tar, tarball_path) {
			result.message = strings.clone("failed to copy local tarball")
			return result
		}
		if !copy_file(local_hash, hash_path) {
			result.message = strings.clone("failed to copy local hash")
			return result
		}
		if !copy_file(local_sig, sig_path) {
			result.message = strings.clone("failed to copy local signature")
			return result
		}
	} else {
		tarball_url, _ := find_latest_tarball(source.url)
		if tarball_url == "" {
			result.message = strings.clone("no tarball release found")
			return result
		}
		defer delete(tarball_url)

		tarball_path = filepath.join({temp_dir, "module.tar.gz"})
		hash_path = strings.concatenate({tarball_path, ".sha256"})
		sig_path = strings.concatenate({tarball_path, ".sig"})

		if !download_file(tarball_url, tarball_path) {
			result.message = strings.clone("failed to download tarball")
			return result
		}
		if !download_file(strings.concatenate({tarball_url, ".sha256"}), hash_path) {
			result.message = strings.clone("failed to download hash")
			return result
		}
		if !download_file(strings.concatenate({tarball_url, ".sig"}), sig_path) {
			result.message = strings.clone("failed to download signature")
			return result
		}
	}

	sig_result := security.verify_signature(tarball_path, sig_path)
	defer security.cleanup_verification_result(&sig_result)
	if !sig_result.success {
		result.message = strings.clone("signature verification failed")
		return result
	}

	hash_ok, hash_err := security.verify_hash(tarball_path, hash_path)
	if hash_err != "" {
		delete(hash_err)
	}
	if !hash_ok {
		result.message = strings.clone("hash verification failed")
		return result
	}

	extract_dir := filepath.join({temp_dir, "extracted"})
	if extract_dir == "" {
		result.message = strings.clone("failed to create extract directory path")
		return result
	}
	defer delete(extract_dir)

	if !extract_tarball(tarball_path, extract_dir) {
		result.message = strings.clone("failed to extract tarball")
		return result
	}
	module_root, root_err := find_module_root(extract_dir)
	if root_err != "" {
		result.message = root_err
		root_err = ""
		return result
	}
	defer delete(module_root)

	scan_options := security.Scan_Options{
		unsafe_mode = options.unsafe,
		verbose = options.verbose,
		trusted = true,
	}
	scan_result := security.scan_module(module_root, scan_options)
	defer security.cleanup_scan_result(&scan_result)
	if !scan_result.success {
		result.message = strings.clone("security scan failed")
		return result
	}
	if scan_result.critical_count > 0 || scan_result.warning_count > 0 {
		report := security.format_scan_report(&scan_result, "signed module")
		fmt.println(report)
		delete(report)
	}
	if security.should_block_install(&scan_result, options.unsafe) {
		result.message = strings.clone("critical security issues detected. Use --unsafe to override.")
		return result
	}
	if scan_result.warning_count > 0 && !options.unsafe {
		if !security.prompt_user_for_warnings(&scan_result, "signed module") {
			result.message = strings.clone("installation cancelled by user")
			return result
		}
	}
	if options.unsafe && (scan_result.critical_count > 0 || scan_result.warning_count > 0) {
		colors.print_warning("Unsafe mode enabled: security checks bypassed")
	}

	validation := validate_module(module_root, "")
	defer cleanup_validation_result(&validation)
	if validation.warning != "" {
		colors.print_warning("%s", validation.warning)
	}
	if !validation.valid {
		result.message = format_manager_validation_error(&validation, "signed module")
		return result
	}

	module_name := validation.module.name
	if module_name == "" {
		result.message = strings.clone("module name missing in manifest")
		return result
	}

	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)
	move_ok, move_info := move_to_final(module_root, modules_dir, module_name, options.force)
	if !move_ok {
		result.message = move_info
		return result
	}
	delete(move_info)

	result.success = true
	result.message = format_install_success(module_name)
	return result
}

download_file :: proc(url: string, dest_path: string) -> bool {
	if url == "" || dest_path == "" {
		return false
	}
	headers := []string{
		"Accept: application/octet-stream",
	}
	resp := http.get(url, headers)
	defer http.cleanup_http_result(&resp)
	if !resp.ok || resp.status_code < 200 || resp.status_code >= 300 {
		if resp.error != "" {
			debug.debug_warn("download failed: %s", resp.error)
		}
		return false
	}
	if resp.body == nil || len(resp.body) == 0 {
		debug.debug_warn("download returned empty body: %s", url)
		return false
	}
	return os.write_entire_file(dest_path, resp.body)
}

find_latest_tarball :: proc(url: string) -> (string, string) {
	owner, repo := parse_github_url(url)
	defer if owner != "" { delete(owner) }
	defer if repo != "" { delete(repo) }
	if owner == "" || repo == "" {
		return "", ""
	}

	api_url := fmt.aprintf("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
	defer delete(api_url)

	headers := []string{
		"Accept: application/vnd.github+json",
	}
	resp := http.get(api_url, headers)
	defer http.cleanup_http_result(&resp)
	if !resp.ok || resp.status_code != 200 {
		return "", ""
	}

	body := string(resp.body)
	tarball_url := extract_release_asset_url(body, ".tar.gz")
	if tarball_url == "" {
		return "", ""
	}

	version := extract_release_tag(body)
	return tarball_url, version
}

extract_release_tag :: proc(body: string) -> string {
	if body == "" {
		return ""
	}
	key := "\"tag_name\""
	idx := strings.index(body, key)
	if idx < 0 {
		return ""
	}
	rest := body[idx+len(key):]
	colon := strings.index(rest, ":")
	if colon < 0 {
		return ""
	}
	rest = rest[colon+1:]
	start := strings.index(rest, "\"")
	if start < 0 {
		return ""
	}
	rest = rest[start+1:]
	end := strings.index(rest, "\"")
	if end < 0 {
		return ""
	}
	return strings.clone(rest[:end])
}

extract_release_asset_url :: proc(body: string, suffix: string) -> string {
	if body == "" || suffix == "" {
		return ""
	}
	search := body
	key := "\"browser_download_url\""

	for {
		idx := strings.index(search, key)
		if idx < 0 {
			return ""
		}
		rest := search[idx+len(key):]
		colon := strings.index(rest, ":")
		if colon < 0 {
			return ""
		}
		rest = rest[colon+1:]
		start := strings.index(rest, "\"")
		if start < 0 {
			return ""
		}
		rest = rest[start+1:]
		end := strings.index(rest, "\"")
		if end < 0 {
			return ""
		}
		url := rest[:end]
		if strings.has_suffix(url, suffix) {
			return strings.clone(url)
		}
		if end+1 >= len(rest) {
			return ""
		}
		search = rest[end+1:]
	}
	return ""
}

find_module_root :: proc(extract_dir: string) -> (string, string) {
	if extract_dir == "" || !os.exists(extract_dir) {
		return "", strings.clone("extraction directory missing")
	}
	manifest_path := filepath.join({extract_dir, "module.toml"})
	defer delete(manifest_path)
	if os.exists(manifest_path) {
		return strings.clone(extract_dir), ""
	}

	handle, open_err := os.open(extract_dir)
	if open_err != os.ERROR_NONE {
		return "", strings.clone("failed to open extract directory")
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		return "", strings.clone("failed to read extract directory")
	}
	defer os.file_info_slice_delete(entries)

	found := ""
	for entry in entries {
		if !entry.is_dir {
			continue
		}
		child := filepath.join({extract_dir, entry.name})
		if child == "" {
			continue
		}
		manifest := filepath.join({child, "module.toml"})
		defer delete(manifest)
		if os.exists(manifest) {
			if found != "" {
				delete(child)
				delete(found)
				return "", strings.clone("multiple module roots found in tarball")
			}
			found = child
		} else {
			delete(child)
		}
	}

	if found == "" {
		return "", strings.clone("module.toml not found in tarball")
	}
	return found, ""
}

copy_file :: proc(src: string, dst: string) -> bool {
	if src == "" || dst == "" {
		return false
	}
	data, ok := os.read_entire_file(src)
	if !ok {
		return false
	}
	defer delete(data)
	return os.write_entire_file(dst, data)
}

extract_tarball :: proc(tarball_path: string, dest_dir: string) -> bool {
	when #config(ZEPHYR_HAS_ARCHIVE, false) {
		return extract_tarball_native(tarball_path, dest_dir)
	} else {
		debug.debug_warn("libarchive not available; cannot extract tarball")
		return false
	}
}
