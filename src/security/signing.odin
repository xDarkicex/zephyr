package security

import "core:crypto/sha2"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../debug"

// Module source type.
Module_Source_Type :: enum {
	Git_Repo,
	Signed_Tarball,
}

// Verification method used.
Verification_Method :: enum {
	Native_OpenSSL,
}

// Verification result for signatures/hashes.
Verification_Result :: struct {
	success:       bool,
	method:        Verification_Method,
	error_message: string,
}

make_verification_error :: proc(method: Verification_Method, message: string) -> Verification_Result {
	return Verification_Result{
		success = false,
		method = method,
		error_message = strings.clone(message),
	}
}

cleanup_verification_result :: proc(result: ^Verification_Result) {
	if result == nil do return
	if result.error_message != "" {
		delete(result.error_message)
		result.error_message = ""
	}
}

// Signature file info for tarball-based installs.
Signature_Info :: struct {
	tarball_path:   string,
	signature_path: string,
	hash_path:      string,
	signature_type: Signature_Type,
}

Signature_Type :: enum {
	OpenSSL,
}

remove_directory_recursive :: proc(dir_path: string) {
	if !os.exists(dir_path) do return

	handle, open_err := os.open(dir_path)
	if open_err != os.ERROR_NONE {
		return
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1)
	if read_err != os.ERROR_NONE {
		return
	}
	defer os.file_info_slice_delete(entries)

	for entry in entries {
		full_path := filepath.join({dir_path, entry.name})
		defer delete(full_path)

		if entry.is_dir {
			remove_directory_recursive(full_path)
		} else {
			os.remove(full_path)
		}
	}

	os.remove(dir_path)
}

verify_signature :: proc(file_path: string, sig_path: string) -> Verification_Result {
	result := verify_signature_native(file_path, sig_path)
	if result.success {
		debug.debug_info("signature verified using native OpenSSL")
	}
	return result
}

constant_time_compare :: proc(a: string, b: string) -> bool {
	if len(a) != len(b) do return false
	diff: byte = 0
	for i := 0; i < len(a); i += 1 {
		diff |= (a[i] ~ b[i])
	}
	return diff == 0
}

hex_encode :: proc(data: []byte) -> string {
	digits := "0123456789abcdef"
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for i := 0; i < len(data); i += 1 {
		b := data[i]
		high := (b >> 4) & 0x0f
		low := b & 0x0f
		fmt.sbprintf(&builder, "%c%c", digits[high], digits[low])
	}
	return strings.clone(strings.to_string(builder))
}

compute_sha256_bytes :: proc(data: []byte) -> [sha2.DIGEST_SIZE_256]byte {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	hash: [sha2.DIGEST_SIZE_256]byte
	sha2.final(&ctx, hash[:])
	return hash
}

verify_hash :: proc(file_path: string, hash_path: string) -> (bool, string) {
	data, ok := os.read_entire_file(file_path)
	if !ok {
		return false, strings.clone("failed to read file for hash verification")
	}
	defer delete(data)

	hash_data, hash_ok := os.read_entire_file(hash_path)
	if !hash_ok {
		return false, strings.clone("failed to read hash file")
	}
	defer delete(hash_data)

	line := strings.trim_space(string(hash_data))
	if line == "" {
		return false, strings.clone("hash file is empty")
	}

	fields, err := strings.fields(line)
	if err != .None || len(fields) == 0 {
		if fields != nil {
			delete(fields)
		}
		return false, strings.clone("invalid hash file format")
	}
	expected := strings.to_lower(fields[0])
	delete(fields)
	defer delete(expected)

	hash := compute_sha256_bytes(data)
	computed := hex_encode(hash[:])
	defer delete(computed)

	if !constant_time_compare(expected, computed) {
		return false, strings.clone("hash verification failed")
	}

	return true, ""
}
