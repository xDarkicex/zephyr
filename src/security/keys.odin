package security

import "core:crypto/sha2"
import "core:fmt"
import "core:strings"

// Official Zephyr signing key (public).
// NOTE: Placeholder until Task 13 generates the real key.
// Test builds can override this with -define:ZEPHYR_TEST_SIGNING_KEY=true
when #config(ZEPHYR_TEST_SIGNING_KEY, false) {
	ZEPHYR_SIGNING_KEY :: `-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA5cIomVSD7t0Rk6HiblBZ8jQl8bSRpsh9E98vcp9Vmfs=
-----END PUBLIC KEY-----`
} else {
	ZEPHYR_SIGNING_KEY :: `-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA9Kmh8sJzPLZY4F0TtkEsX4i3BhoUkmHx63KqTEcRCao=
-----END PUBLIC KEY-----`
}

get_signing_key :: proc() -> string {
	return strings.clone(ZEPHYR_SIGNING_KEY)
}

get_key_fingerprint :: proc() -> string {
	key := ZEPHYR_SIGNING_KEY
	hash := compute_sha256(transmute([]byte)key)
	return format_fingerprint(hash[:])
}

compute_sha256 :: proc(data: []byte) -> [sha2.DIGEST_SIZE_256]byte {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	hash: [sha2.DIGEST_SIZE_256]byte
	sha2.final(&ctx, hash[:])
	return hash
}

format_fingerprint :: proc(hash: []byte) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for i := 0; i < len(hash); i += 1 {
		if i > 0 {
			fmt.sbprintf(&builder, ":")
		}
		fmt.sbprintf(&builder, "%02X", hash[i])
	}

	return strings.clone(strings.to_string(builder))
}
