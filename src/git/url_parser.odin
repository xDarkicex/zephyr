package git

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// URL parsing and normalization helpers for git-based module installs.
// Ownership: any returned strings or error messages are owned by the caller.

// URL_Parse_Result reports a parsed module name and any error message.
URL_Parse_Result :: struct {
	module_name: string,
	valid:       bool,
	error:       string,
}

// Install_Source_Type categorizes the detected install input.
Install_Source_Type :: enum {
	Git_URL,
	GitHub_Shorthand,
	Local_Path,
	Invalid,
}

// Install_Source holds a normalized URL/path and derived module name.
Install_Source :: struct {
	url:         string,
	module_name: string,
	source_type: Install_Source_Type,
	valid:       bool,
	error:       string,
}

// cleanup_url_parse_result frees owned strings in a URL_Parse_Result.
cleanup_url_parse_result :: proc(result: ^URL_Parse_Result) {
	if result == nil do return
	if result.module_name != "" {
		delete(result.module_name)
		result.module_name = ""
	}
	if result.error != "" {
		delete(result.error)
		result.error = ""
	}
}

// cleanup_install_source frees owned strings in an Install_Source.
cleanup_install_source :: proc(source: ^Install_Source) {
	if source == nil do return
	if source.url != "" {
		delete(source.url)
		source.url = ""
	}
	if source.module_name != "" {
		delete(source.module_name)
		source.module_name = ""
	}
	if source.error != "" {
		delete(source.error)
		source.error = ""
	}
}

// is_valid_git_url performs a lightweight protocol and shape check.
is_valid_git_url :: proc(url: string) -> bool {
	if url == "" do return false

	if strings.has_prefix(url, "https://") {
		return strings.contains(url, "/")
	}
	if strings.has_prefix(url, "git://") {
		return strings.contains(url, "/")
	}
	if strings.has_prefix(url, "git@") {
		return strings.contains(url, ":")
	}
	return false
}

// parse_install_source normalizes input into a URL or local path.
parse_install_source :: proc(input: string, allow_local: bool = false) -> Install_Source {
	source := Install_Source{}

	if is_valid_git_url(input) {
		source.url = strings.clone(input)
		source.source_type = .Git_URL
		source.valid = true
		return source
	}

	if is_github_shorthand(input) {
		source.url = expand_github_shorthand(input)
		source.source_type = .GitHub_Shorthand
		source.valid = true
		return source
	}

	if allow_local {
		local_path := normalize_local_path(input)
		if local_path != "" {
			source.url = local_path
			source.source_type = .Local_Path
			source.valid = true
			return source
		}
	}

	source.source_type = .Invalid
	source.valid = false
	source.error = strings.clone("invalid install source")
	return source
}

// parse_module_name_from_url extracts and validates a module name from a git URL.
parse_module_name_from_url :: proc(url: string) -> URL_Parse_Result {
	result := URL_Parse_Result{}
	if url == "" {
		result.error = strings.clone("empty URL")
		return result
	}

	if !is_valid_git_url(url) {
		result.error = strings.clone("invalid git URL")
		return result
	}

	repo_name := extract_repo_name(url)
	if repo_name == "" {
		result.error = strings.clone("unable to extract repo name")
		return result
	}

	name := strip_prefixes(repo_name)
	if name == "" {
		result.error = strings.clone("module name is empty after stripping")
		return result
	}

	valid, err := validate_module_name(name)
	if !valid {
		result.error = err
		return result
	}

	result.module_name = strings.clone(name)
	result.valid = true
	return result
}

// validate_module_name enforces naming rules and returns an owned error message.
validate_module_name :: proc(name: string) -> (bool, string) {
	if name == "" {
		return false, strings.clone("module name cannot be empty")
	}
	if len(name) > 50 {
		return false, strings.clone("module name too long (max 50 characters)")
	}

	lower := strings.to_lower(name)
	defer delete(lower)
	if lower != name {
		return false, strings.clone("module name must be lowercase")
	}

	first := lower[0]
	if !is_alphanumeric(first) {
		return false, format_error_char("module name must start with letter or number, not", first)
	}

	for i in 1..<len(lower) {
		c := lower[i]
		if !is_alphanumeric(c) && c != '-' && c != '_' {
			return false, format_error_char("invalid character", c)
		}
	}

	if is_reserved_name(lower) {
		return false, format_error_string("reserved module name", lower)
	}

	return true, ""
}

// is_github_shorthand detects the user/repo shorthand format.
is_github_shorthand :: proc(input: string) -> bool {
	if strings.contains(input, "://") do return false
	if strings.has_prefix(input, "git@") do return false
	return strings.count(input, "/") == 1
}

// normalize_local_path resolves local paths and returns a clean, owned path.
normalize_local_path :: proc(input: string) -> string {
	if input == "" do return ""

	path := input
	if strings.has_prefix(input, "file://") {
		path = input[len("file://"):]
	}

	if !os.exists(path) {
		return ""
	}
	info, stat_err := os.stat(path)
	if stat_err != os.ERROR_NONE || !info.is_dir {
		return ""
	}

	if strings.has_prefix(input, "file://") {
		return strings.clone(path)
	}

	return strings.clone(filepath.clean(path))
}

// expand_github_shorthand converts user/repo into a GitHub HTTPS URL.
expand_github_shorthand :: proc(input: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "https://github.com/%s", input)
	return strings.clone(strings.to_string(builder))
}

// extract_repo_name returns the last path segment without a .git suffix.
extract_repo_name :: proc(url: string) -> string {
	cleaned := strings.trim_suffix(url, ".git")

	segment := ""
	if strings.has_prefix(cleaned, "git@") {
		idx := strings.last_index_byte(cleaned, ':')
		if idx >= 0 && idx+1 < len(cleaned) {
			segment = cleaned[idx+1:]
		}
	} else {
		idx := strings.last_index_byte(cleaned, '/')
		if idx >= 0 && idx+1 < len(cleaned) {
			segment = cleaned[idx+1:]
		}
	}

	if strings.contains(segment, "/") {
		idx := strings.last_index_byte(segment, '/')
		if idx >= 0 && idx+1 < len(segment) {
			segment = segment[idx+1:]
		}
	}

	return segment
}

// strip_prefixes removes zephyr module naming prefixes (first match wins).
strip_prefixes :: proc(name: string) -> string {
	if strings.has_prefix(name, "zephyr-module-") {
		return strings.trim_prefix(name, "zephyr-module-")
	}
	if strings.has_prefix(name, "zephyr-") {
		return strings.trim_prefix(name, "zephyr-")
	}
	return name
}

is_alphanumeric :: proc(c: byte) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
}

is_reserved_name :: proc(name: string) -> bool {
	reserved := []string{"core", "stdlib", "system", "kernel"}
	for r in reserved {
		if name == r {
			return true
		}
	}
	return false
}

format_error_char :: proc(prefix: string, c: byte) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "%s '%c'", prefix, c)
	return strings.clone(strings.to_string(builder))
}

format_error_string :: proc(prefix: string, value: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "%s '%s'", prefix, value)
	return strings.clone(strings.to_string(builder))
}
