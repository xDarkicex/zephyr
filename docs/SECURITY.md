# Signed Modules Security Model

Zephyr supports **signed first-party modules** distributed as `.tar.gz` release assets.
Signatures are verified using **native OpenSSL** before installation.

## Trust Model

- **Signed modules** are verified against the embedded Zephyr public key.
- **Unsigned modules** are treated as untrusted and fully scanned.
- If signature verification fails, installation is **blocked**.

## Verification Pipeline

1. **Download tarball + `.sig` + `.sha256`**
2. **Verify signature** (OpenSSL Ed25519)
3. **Verify hash** (SHA-256)
4. **Extract tarball** (libarchive)
5. **Scan module** (trusted flag applied)
6. **Validate manifest**
7. **Install to final location**

If any step fails, installation stops and all temp files are removed.

## Commands

- `zephyr show-signing-key` — print the embedded public key and fingerprint.
- `zephyr verify <path>` — verify a signed tarball (`.sig` + `.sha256`) in a module directory.

## Key Rotation

If the signing key is compromised:

1. Generate a new Ed25519 key pair.
2. Publish the new public key in a signed release.
3. Update `src/security/keys.odin` and rotate in the next release.

## Threats Covered

- Tampered release tarballs
- Modified signatures or hashes
- Untrusted modules masquerading as official releases

## Threats Not Covered

- Compromised private key
- Malicious behavior inside officially signed modules
- Runtime shell execution (no sandboxing)

Treat signed modules as **trusted code** and apply operational controls accordingly.

## Audit Logs & SIEM

Zephyr emits JSON Lines audit logs for session activity and operations in `~/.zephyr/audit/`.
See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for schema and SIEM mapping guidance.
