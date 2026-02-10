package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "../src/security"

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
