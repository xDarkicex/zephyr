package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:testing"

import "../src/security"
import "../src/git"

TEST_SIGNATURE_HEX :: "e880de93e24082f5a31c8f90a8a27f855b35cb1757797b2bbc08c82b11e2a23dcd7455adb8a773adba76c710281e92b814ca13ef496d5c771e9818d75359d309"
TEST_DATA :: "zephyr-signing-test"

hex_value :: proc(c: byte) -> int {
	switch c {
	case '0'..='9': return int(c - '0')
	case 'a'..='f': return int(c - 'a') + 10
	case 'A'..='F': return int(c - 'A') + 10
	}
	return -1
}

decode_hex :: proc(hex: string) -> ([]byte, bool) {
	if len(hex)%2 != 0 do return nil, false
	out := make([]byte, len(hex)/2)
	for i := 0; i < len(out); i += 1 {
		hi := hex_value(hex[i*2])
		lo := hex_value(hex[i*2+1])
		if hi < 0 || lo < 0 {
			delete(out)
			return nil, false
		}
		out[i] = byte((hi << 4) | lo)
	}
	return out, true
}

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

@(test)
test_verify_signature_valid :: proc(t: ^testing.T) {
	data_path := temp_path("zephyr_signing_data.txt")
	defer delete(data_path)
	defer os.remove(data_path)
	sig_path := temp_path("zephyr_signing_sig.bin")
	defer delete(sig_path)
	defer os.remove(sig_path)

	data := TEST_DATA
	ok := os.write_entire_file(data_path, transmute([]u8)data)
	testing.expect(t, ok, "failed to write test data")

	sig_bytes, sig_ok := decode_hex(TEST_SIGNATURE_HEX)
	testing.expect(t, sig_ok, "failed to decode signature hex")
	defer delete(sig_bytes)

	ok = os.write_entire_file(sig_path, sig_bytes)
	testing.expect(t, ok, "failed to write signature file")

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

	data_bad := strings.concatenate({TEST_DATA, "x"})
	defer delete(data_bad)
	ok := os.write_entire_file(data_path, transmute([]u8)data_bad)
	testing.expect(t, ok, "failed to write test data")

	sig_bytes, sig_ok := decode_hex(TEST_SIGNATURE_HEX)
	testing.expect(t, sig_ok, "failed to decode signature hex")
	if len(sig_bytes) > 0 {
		sig_bytes[0] = sig_bytes[0] ~ 0xff
	}
	defer delete(sig_bytes)

	ok = os.write_entire_file(sig_path, sig_bytes)
	testing.expect(t, ok, "failed to write signature file")

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

	ok = os.write_entire_file(hash_path, transmute([]u8)"")
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
