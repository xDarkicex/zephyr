#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <module-vX.Y.Z.tar.gz>" >&2
  exit 1
fi

TARBALL="$1"

if [[ ! -f "$TARBALL" ]]; then
  echo "Error: tarball not found: $TARBALL" >&2
  exit 1
fi

if [[ -z "${ZEPHYR_SIGNING_KEY:-}" ]]; then
  echo "Error: ZEPHYR_SIGNING_KEY must point to your private key PEM" >&2
  exit 1
fi

if [[ ! -f "$ZEPHYR_SIGNING_KEY" ]]; then
  echo "Error: signing key not found: $ZEPHYR_SIGNING_KEY" >&2
  exit 1
fi

HASH_FILE="${TARBALL}.sha256"
SIG_FILE="${TARBALL}.sig"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$TARBALL" > "$HASH_FILE"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$TARBALL" > "$HASH_FILE"
else
  echo "Error: shasum or sha256sum required to generate hash" >&2
  exit 1
fi

openssl pkeyutl -sign -rawin -inkey "$ZEPHYR_SIGNING_KEY" -in "$TARBALL" -out "$SIG_FILE"

echo "Signed: $TARBALL"
echo "Hash:   $HASH_FILE"
echo "Sig:    $SIG_FILE"
