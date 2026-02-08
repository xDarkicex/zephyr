package security

import "core:fmt"
import "core:os"
import "core:strings"

when #config(ZEPHYR_HAS_MAGIC, false) {
	foreign import magic "system:magic"

	foreign magic {
		magic_open  :: proc(flags: i32) -> rawptr ---
		magic_load  :: proc(cookie: rawptr, filename: cstring) -> i32 ---
		magic_file  :: proc(cookie: rawptr, filename: cstring) -> cstring ---
		magic_close :: proc(cookie: rawptr) ---
		magic_error :: proc(cookie: rawptr) -> cstring ---
	}

	MAGIC_MIME_TYPE :: 0x000010
	MAGIC_ERROR     :: 0x000040

	HAS_LIBMAGIC :: true
} else {
	HAS_LIBMAGIC :: false
}

get_file_type :: proc(file_path: string) -> (file_type: string, has_magic: bool) {
	when HAS_LIBMAGIC {
		cookie := magic_open(MAGIC_MIME_TYPE | MAGIC_ERROR)
		if cookie == nil {
			return "", false
		}
		defer magic_close(cookie)

		if magic_load(cookie, nil) != 0 {
			return "", false
		}

		c_path := strings.clone_to_cstring(file_path)
		defer delete(c_path)

		result := magic_file(cookie, c_path)
		if result == nil {
			return "", false
		}

		return strings.clone(string(result)), true
	}

	data, ok := os.read_entire_file(file_path)
	if !ok {
		return "", false
	}
	defer delete(data)

	if is_binary_data(data) {
		return "application/octet-stream", false
	}

	return "text/plain", false
}

is_suspicious_binary :: proc(file_path: string) -> (suspicious: bool, file_type: string) {
	file_type_str, has_magic := get_file_type(file_path)
	if !has_magic {
		if is_executable_file(file_path) {
			return true, strings.clone("unknown binary type")
		}
		return false, ""
	}
	defer delete(file_type_str)

	suspicious_types := []string{
		"application/x-executable",
		"application/x-sharedlib",
		"application/x-mach-binary",
		"application/x-pie-executable",
		"application/x-object",
	}

	for typ in suspicious_types {
		if strings.contains(file_type_str, typ) {
			return true, strings.clone(file_type_str)
		}
	}

	packers := []string{"UPX", "gzip", "bzip2", "lzma", "XZ"}
	for packer in packers {
		if strings.contains(file_type_str, packer) {
			return true, fmt.tprintf("%s (packed with %s)", file_type_str, packer)
		}
	}

	return false, ""
}

is_executable_file :: proc(file_path: string) -> bool {
	fi, err := os.stat(file_path)
	if err != os.ERROR_NONE {
		return false
	}
	defer os.file_info_delete(fi)

	return (fi.mode & 0o111) != 0
}
