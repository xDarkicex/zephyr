package git

import "core:c"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../debug"

when #config(ZEPHYR_HAS_ARCHIVE, false) {
	foreign import archive "system:archive"

	foreign archive {
		archive_read_new                 :: proc() -> rawptr ---
		archive_read_support_format_tar  :: proc(a: rawptr) -> c.int ---
		archive_read_support_filter_gzip :: proc(a: rawptr) -> c.int ---
		archive_read_open_filename       :: proc(a: rawptr, path: cstring, block_size: c.size_t) -> c.int ---
		archive_read_next_header         :: proc(a: rawptr, entry: ^^archive_entry) -> c.int ---
		archive_read_close               :: proc(a: rawptr) -> c.int ---
		archive_read_free                :: proc(a: rawptr) -> c.int ---
		archive_read_extract2            :: proc(a: rawptr, entry: ^archive_entry, dest: rawptr) -> c.int ---
		archive_write_disk_new           :: proc() -> rawptr ---
		archive_write_disk_set_options   :: proc(a: rawptr, flags: c.int) -> c.int ---
		archive_write_disk_set_standard_lookup :: proc(a: rawptr) -> c.int ---
		archive_write_close              :: proc(a: rawptr) -> c.int ---
		archive_write_free               :: proc(a: rawptr) -> c.int ---
		archive_error_string             :: proc(a: rawptr) -> cstring ---
		archive_entry_pathname           :: proc(entry: ^archive_entry) -> cstring ---
		archive_entry_set_pathname       :: proc(entry: ^archive_entry, path: cstring) ---
	}

	archive_entry :: struct {}

	ARCHIVE_OK    :: 0
	ARCHIVE_EOF   :: 1
	ARCHIVE_WARN  :: -20

	ARCHIVE_EXTRACT_OWNER              :: 0x0001
	ARCHIVE_EXTRACT_PERM               :: 0x0002
	ARCHIVE_EXTRACT_TIME               :: 0x0004
	ARCHIVE_EXTRACT_SECURE_SYMLINKS    :: 0x0100
	ARCHIVE_EXTRACT_SECURE_NODOTDOT    :: 0x0200
	ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS :: 0x0400

	extract_tarball_native :: proc(tarball_path: string, dest_dir: string) -> bool {
		if tarball_path == "" || dest_dir == "" {
			return false
		}

		if !os.exists(dest_dir) {
			os.make_directory(dest_dir, 0o755)
		}

		reader := archive_read_new()
		if reader == nil {
			debug.debug_warn("libarchive: failed to create reader")
			return false
		}
		defer archive_read_free(reader)

		_ = archive_read_support_filter_gzip(reader)
		_ = archive_read_support_format_tar(reader)

		path_c := strings.clone_to_cstring(tarball_path)
		defer delete(path_c)
		if archive_read_open_filename(reader, path_c, 10240) != ARCHIVE_OK {
			debug.debug_warn("libarchive: failed to open tarball: %s", tarball_path)
			return false
		}
		defer archive_read_close(reader)

		writer := archive_write_disk_new()
		if writer == nil {
			debug.debug_warn("libarchive: failed to create disk writer")
			return false
		}
		defer archive_write_free(writer)
		_ = archive_write_disk_set_standard_lookup(writer)
		flags: c.int = ARCHIVE_EXTRACT_PERM |
			ARCHIVE_EXTRACT_TIME |
			ARCHIVE_EXTRACT_SECURE_NODOTDOT |
			ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS
		when ODIN_OS != .Darwin {
			flags |= ARCHIVE_EXTRACT_OWNER
		}
		_ = archive_write_disk_set_options(writer, flags)

		for {
			entry: ^archive_entry
			status := archive_read_next_header(reader, &entry)
			if status == ARCHIVE_EOF {
				break
			}
			if status < ARCHIVE_WARN {
				err := archive_error_string(reader)
				if err != nil {
					debug.debug_warn("libarchive read error: %s", string(err))
				}
				return false
			}

			orig_path_c := archive_entry_pathname(entry)
			if orig_path_c == nil {
				continue
			}
			orig_path := string(orig_path_c)
			if !is_safe_relative_path(orig_path) {
				debug.debug_warn("libarchive: unsafe path in tarball: %s", orig_path)
				return false
			}

			full_path := filepath.join({dest_dir, orig_path})
			if full_path == "" {
				return false
			}
			defer delete(full_path)

			full_path_c := strings.clone_to_cstring(full_path)
			archive_entry_set_pathname(entry, full_path_c)

			if archive_read_extract2(reader, entry, writer) != ARCHIVE_OK {
				err := archive_error_string(reader)
				if err != nil {
					debug.debug_warn("libarchive extract error: %s", string(err))
				}
				delete(full_path_c)
				return false
			}
			delete(full_path_c)
		}

		return true
	}
} else {
	extract_tarball_native :: proc(tarball_path: string, dest_dir: string) -> bool {
		_ = tarball_path
		_ = dest_dir
		return false
	}
}

is_safe_relative_path :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	if strings.has_prefix(path, "/") {
		return false
	}
	if strings.contains(path, "..") {
		return false
	}
	return true
}
