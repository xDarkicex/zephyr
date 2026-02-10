package security

import "core:c"
import "core:os"
import "core:strings"

when ODIN_OS == .Darwin || ODIN_OS == .Linux {
	when #config(ZEPHYR_HAS_OPENSSL, false) {
		foreign import ssl "system:ssl"
		foreign import crypto "system:crypto"

		foreign ssl {
			// BIO
			BIO_new_mem_buf :: proc(data: rawptr, len: int) -> ^BIO ---
			BIO_free        :: proc(bio: ^BIO) -> int ---
		}

		foreign crypto {
			PEM_read_bio_PUBKEY :: proc(bp: ^BIO, x: ^^EVP_PKEY, cb: rawptr, u: rawptr) -> ^EVP_PKEY ---
			EVP_PKEY_free       :: proc(pkey: ^EVP_PKEY) ---
			EVP_MD_CTX_new      :: proc() -> ^EVP_MD_CTX ---
			EVP_MD_CTX_free     :: proc(ctx: ^EVP_MD_CTX) ---
			EVP_DigestVerifyInit   :: proc(ctx: ^EVP_MD_CTX, pctx: ^^EVP_PKEY_CTX, typ: ^EVP_MD, e: ^ENGINE, pkey: ^EVP_PKEY) -> int ---
			EVP_DigestVerify        :: proc(ctx: ^EVP_MD_CTX, sig: rawptr, siglen: int, tbs: rawptr, tbslen: int) -> int ---
			EVP_sha256             :: proc() -> ^EVP_MD ---
		}

		BIO :: struct { _: u8 }
		EVP_PKEY :: struct { _: u8 }
		EVP_MD :: struct { _: u8 }
		EVP_MD_CTX :: struct { _: u8 }
		EVP_PKEY_CTX :: struct { _: u8 }
		ENGINE :: struct { _: u8 }

		verify_signature_native :: proc(file_path: string, sig_path: string) -> Verification_Result {
			result := Verification_Result{success = false, method = .Native_OpenSSL}

			data, ok := os.read_entire_file(file_path)
			if !ok {
				result.error_message = strings.clone("failed to read file for signature verification")
				return result
			}
			defer delete(data)

			sig, sig_ok := os.read_entire_file(sig_path)
			if !sig_ok {
				result.error_message = strings.clone("failed to read signature file")
				return result
			}
			defer delete(sig)

			key := ZEPHYR_SIGNING_KEY
			key_bytes := transmute([]byte)key
			if len(key_bytes) == 0 {
				result.error_message = strings.clone("embedded signing key is empty")
				return result
			}

			bio := BIO_new_mem_buf(rawptr(&key_bytes[0]), len(key_bytes))
			if bio == nil {
				result.error_message = strings.clone("failed to create OpenSSL BIO")
				return result
			}
			defer BIO_free(bio)

			pkey := PEM_read_bio_PUBKEY(bio, nil, nil, nil)
			if pkey == nil {
				result.error_message = strings.clone("failed to parse public key")
				return result
			}
			defer EVP_PKEY_free(pkey)

			attempt_verify := proc(md: ^EVP_MD, payload: []u8, signature: []u8, key: ^EVP_PKEY) -> bool {
				ctx := EVP_MD_CTX_new()
				if ctx == nil {
					return false
				}
				defer EVP_MD_CTX_free(ctx)

				if EVP_DigestVerifyInit(ctx, nil, md, nil, key) != 1 {
					return false
				}

				if len(signature) == 0 {
					return false
				}
				if len(payload) == 0 {
					return false
				}

				return EVP_DigestVerify(ctx, rawptr(&signature[0]), len(signature), rawptr(&payload[0]), len(payload)) == 1
			}

			verified := attempt_verify(EVP_sha256(), data, sig, pkey)
			if !verified {
				verified = attempt_verify(nil, data, sig, pkey)
			}

			if !verified {
				result.error_message = strings.clone("signature verification failed")
				return result
			}

			result.success = true
			return result
		}
	} else {
		#panic("OpenSSL is required. Install OpenSSL and build with -define:ZEPHYR_HAS_OPENSSL=true.")
	}
} else {
	#panic("OpenSSL verification is only supported on macOS and Linux.")
}
