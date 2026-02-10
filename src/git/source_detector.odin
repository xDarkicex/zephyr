package git

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "../debug"
import "../http"
import "../security"

// find_signed_tarball scans a local directory for a tarball with matching .sig and .sha256 files.
// Returns the tarball path or "" if none found.
find_signed_tarball :: proc(dir_path: string) -> string {
	if dir_path == "" || !os.exists(dir_path) {
		return ""
	}

	handle, open_err := os.open(dir_path)
	if open_err != os.ERROR_NONE {
		return ""
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		return ""
	}
	defer os.file_info_slice_delete(entries)

	best_path := ""
	best_time := time.Time{}

	for entry in entries {
		if entry.is_dir {
			continue
		}
		if !strings.has_suffix(entry.name, ".tar.gz") {
			continue
		}

		tar_path := filepath.join({dir_path, entry.name})
		if tar_path == "" {
			continue
		}
		defer delete(tar_path)

		sig_path := strings.concatenate({tar_path, ".sig"})
		defer delete(sig_path)
		hash_path := strings.concatenate({tar_path, ".sha256"})
		defer delete(hash_path)

		if !os.exists(sig_path) || !os.exists(hash_path) {
			continue
		}

		info, stat_err := os.stat(tar_path)
		if stat_err != os.ERROR_NONE {
			continue
		}

		if best_path == "" || time.diff(best_time, info.modification_time) < 0 {
			if best_path != "" {
				delete(best_path)
			}
			best_path = strings.clone(tar_path)
			best_time = info.modification_time
		}
	}

	return best_path
}

// detect_module_source_from_dir determines whether a local directory contains a signed tarball.
detect_module_source_from_dir :: proc(dir_path: string) -> security.Module_Source_Type {
	tarball := find_signed_tarball(dir_path)
	if tarball != "" {
		delete(tarball)
		return .Signed_Tarball
	}
	return .Git_Repo
}

// detect_module_source determines source type based on install input.
// For local paths, inspect the directory. For URLs, use lightweight heuristics.
detect_module_source :: proc(source: Install_Source) -> security.Module_Source_Type {
	switch source.source_type {
	case .Local_Path:
		return detect_module_source_from_dir(source.url)
	case .Git_URL, .GitHub_Shorthand:
		if strings.has_suffix(source.url, ".tar.gz") {
			debug.debug_info("Detected tarball URL: %s", source.url)
			return .Signed_Tarball
		}
		if is_github_url(source.url) && has_github_release_tarball(source.url) {
			return .Signed_Tarball
		}
		return .Git_Repo
	case .Invalid:
		return .Git_Repo
	}
	return .Git_Repo
}

is_github_url :: proc(url: string) -> bool {
	if url == "" do return false
	if strings.has_prefix(url, "https://github.com/") do return true
	if strings.has_prefix(url, "git@github.com:") do return true
	return false
}

parse_github_url :: proc(url: string) -> (owner: string, repo: string) {
	if url == "" {
		return "", ""
	}

	if strings.contains(url, "github.com/") {
		parts := strings.split(url, "github.com/")
		defer delete(parts)
		if len(parts) < 2 {
			return "", ""
		}
		path := parts[1]
		path_parts := strings.split(path, "/")
		defer delete(path_parts)
		if len(path_parts) < 2 {
			return "", ""
		}
		owner = strings.clone(path_parts[0])
		repo_name := strings.trim_suffix(path_parts[1], ".git")
		repo = strings.clone(repo_name)
		return owner, repo
	}

	if strings.has_prefix(url, "git@") && strings.contains(url, ":") {
		parts := strings.split(url, ":")
		defer delete(parts)
		if len(parts) < 2 {
			return "", ""
		}
		path := parts[1]
		path_parts := strings.split(path, "/")
		defer delete(path_parts)
		if len(path_parts) < 2 {
			return "", ""
		}
		owner = strings.clone(path_parts[0])
		repo_name := strings.trim_suffix(path_parts[1], ".git")
		repo = strings.clone(repo_name)
		return owner, repo
	}

	return "", ""
}

has_github_release_tarball :: proc(url: string) -> bool {
	owner, repo := parse_github_url(url)
	defer if owner != "" { delete(owner) }
	defer if repo != "" { delete(repo) }
	if owner == "" || repo == "" {
		return false
	}

	api_url := fmt.aprintf("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
	defer delete(api_url)

	headers := []string{
		"Accept: application/vnd.github+json",
	}

	result := http.get(api_url, headers)
	defer http.cleanup_http_result(&result)
	if !result.ok {
		debug.debug_warn("GitHub release check failed: %s", result.error)
		return false
	}
	if result.status_code != 200 {
		debug.debug_warn("GitHub release check returned status %d", result.status_code)
		return false
	}

	body := string(result.body)
	if strings.contains(body, ".tar.gz") {
		return true
	}
	return false
}
