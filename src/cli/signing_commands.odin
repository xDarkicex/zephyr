package cli

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../colors"
import "../security"

show_signing_key_command :: proc() {
	fmt.println("")
	fmt.println(colors.bold("Zephyr Official Signing Key"))
	fmt.println("")
	key := security.get_signing_key()
	fmt.println(key)
	delete(key)
	fmt.println("")
	fmt.println(colors.bold("Fingerprint:"))
	fingerprint := security.get_key_fingerprint()
	fmt.println(fingerprint)
	delete(fingerprint)
	fmt.println("")
	fmt.println("Verify this key matches the official key published at:")
	fmt.println("  https://github.com/zephyr-systems/zephyr")
	fmt.println("")
}

verify_module_command :: proc(module_path: string) {
	if module_path == "" {
		colors.print_error("Module path required")
		fmt.eprintln("Usage: zephyr verify <path>")
		os.exit(1)
	}

	tarball_path := find_tarball_in_module(module_path)
	if tarball_path == "" {
		fmt.println(fmt.tprintf("%s Module is not signed (no tarball found)", colors.warning_symbol()))
		return
	}
	defer delete(tarball_path)

	sig_path := strings.concatenate({tarball_path, ".sig"})
	hash_path := strings.concatenate({tarball_path, ".sha256"})
	if !os.exists(sig_path) {
		fmt.println(fmt.tprintf("%s No signature file found", colors.error_symbol()))
		delete(sig_path)
		delete(hash_path)
		return
	}
	if !os.exists(hash_path) {
		fmt.println(fmt.tprintf("%s No hash file found", colors.error_symbol()))
		delete(sig_path)
		delete(hash_path)
		return
	}

	result := security.verify_signature(tarball_path, sig_path)
	defer security.cleanup_verification_result(&result)
	if result.success {
		fmt.println(fmt.tprintf("%s Signature verified", colors.success_symbol()))
		fmt.println(fmt.tprintf("  Method: %v", result.method))
	} else {
		fmt.println(fmt.tprintf("%s Signature verification failed", colors.error_symbol()))
		fmt.println(fmt.tprintf("  Error: %s", result.error_message))
	}

	hash_ok, hash_err := security.verify_hash(tarball_path, hash_path)
	if hash_err != "" {
		defer delete(hash_err)
	}
	if hash_ok {
		fmt.println(fmt.tprintf("%s Hash verified", colors.success_symbol()))
	} else {
		fmt.println(fmt.tprintf("%s Hash verification failed", colors.error_symbol()))
		if hash_err != "" {
			fmt.println(fmt.tprintf("  Error: %s", hash_err))
		}
	}

	delete(sig_path)
	delete(hash_path)
}

find_tarball_in_module :: proc(module_path: string) -> string {
	if module_path == "" {
		return ""
	}

	if os.exists(module_path) && !is_directory(module_path) {
		if strings.has_suffix(module_path, ".tar.gz") {
			return strings.clone(module_path)
		}
		return ""
	}

	dir_path := module_path
	if !os.exists(dir_path) {
		return ""
	}

	handle, err := os.open(dir_path)
	if err != os.ERROR_NONE {
		return ""
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		return ""
	}
	defer os.file_info_slice_delete(entries)

	candidate: string
	for entry in entries {
		if entry.is_dir {
			continue
		}
		name := entry.name
		if strings.has_suffix(name, ".tar.gz") {
			full_path := filepath.join({dir_path, name})
			if full_path != "" {
				if candidate != "" {
					delete(candidate)
				}
				candidate = full_path
				break
			}
		}
	}

	return candidate
}

is_directory :: proc(path: string) -> bool {
	info, err := os.stat(path)
	if err != os.ERROR_NONE {
		return false
	}
	return info.is_dir
}
