#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="zephyr"
BUILD_FLAGS=(-o:speed)
LINKER_FLAGS=""

# Build metadata (embedded at compile time)
VERSION="${VERSION:-dev}"
if [ -z "${GIT_COMMIT:-}" ]; then
    if command -v git &> /dev/null; then
        GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    else
        GIT_COMMIT="unknown"
    fi
fi
BUILD_TIME="${BUILD_TIME:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
BUILD_FLAGS+=("-define:VERSION=${VERSION}")
BUILD_FLAGS+=("-define:GIT_COMMIT=${GIT_COMMIT}")
BUILD_FLAGS+=("-define:BUILD_TIME=${BUILD_TIME}")

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
esac

echo "Building $BINARY_NAME for $OS/$ARCH..."

# Validate supported platforms
case "$OS" in
    darwin|linux)
        echo "✓ Supported platform: $OS"
        ;;
    *)
        echo "Warning: Untested platform: $OS"
        echo "Supported platforms: macOS (darwin), Linux"
        ;;
esac

# Check if Odin compiler is available
if ! command -v odin &> /dev/null; then
    echo "Error: Odin compiler not found. Please install Odin first."
    echo "Visit: https://odin-lang.org/docs/install/"
    exit 1
fi

# Detect libgit2 via pkg-config (or use LIBGIT2_LIBS override).
# Note: Odin's `foreign import "system:git2"` already links -lgit2.
# We only need library search paths here to avoid duplicate -lgit2 warnings.
if [ -n "${LIBGIT2_LIBS:-}" ]; then
    # Strip any explicit -lgit2 to avoid duplicate linking.
    LIBGIT2_LIBS_CLEAN=$(echo "${LIBGIT2_LIBS}" | tr ' ' '\n' | grep -v '^-lgit2$' | tr '\n' ' ')
    LINKER_FLAGS="${LINKER_FLAGS} ${LIBGIT2_LIBS_CLEAN}"
    echo "✓ libgit2 flags from LIBGIT2_LIBS: ${LIBGIT2_LIBS_CLEAN}"
elif command -v pkg-config &> /dev/null; then
    # Use only search paths to avoid duplicate -lgit2.
    LIBGIT2_LIBS=$(pkg-config --libs-only-L libgit2 2>/dev/null || true)
    if [ -n "${LIBGIT2_LIBS:-}" ]; then
        LINKER_FLAGS="${LINKER_FLAGS} ${LIBGIT2_LIBS}"
        echo "✓ libgit2 detected: ${LIBGIT2_LIBS}"
    else
        echo "ℹ libgit2 not detected; install libgit2 or set LIBGIT2_LIBS"
    fi
else
    echo "ℹ pkg-config not available; libgit2 auto-detect skipped"
    echo "  Install pkg-config or set LIBGIT2_LIBS if libgit2 is not on the default linker path"
fi

# Detect libmagic via pkg-config (or use LIBMAGIC_LIBS override)
# Note: Odin's `foreign import "system:magic"` already links -lmagic.
# We only need library search paths to avoid duplicate library warnings.
if [ -n "${LIBMAGIC_LIBS:-}" ]; then
    LIBMAGIC_LIBS_CLEAN=$(echo "${LIBMAGIC_LIBS}" | tr ' ' '\n' | grep -v '^-lmagic$' | tr '\n' ' ')
    LINKER_FLAGS="${LINKER_FLAGS} ${LIBMAGIC_LIBS_CLEAN}"
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_MAGIC=true")
    echo "✓ libmagic flags from LIBMAGIC_LIBS: ${LIBMAGIC_LIBS_CLEAN}"
elif command -v pkg-config &> /dev/null; then
    LIBMAGIC_LIBS=$(pkg-config --libs-only-L --libs-only-other libmagic 2>/dev/null || true)
    if [ -n "${LIBMAGIC_LIBS:-}" ] || pkg-config --exists libmagic 2>/dev/null; then
        LINKER_FLAGS="${LINKER_FLAGS} ${LIBMAGIC_LIBS}"
        BUILD_FLAGS+=("-define:ZEPHYR_HAS_MAGIC=true")
        echo "✓ libmagic detected: ${LIBMAGIC_LIBS}"
    else
        BUILD_FLAGS+=("-define:ZEPHYR_HAS_MAGIC=false")
        echo "ℹ libmagic not detected; install libmagic or set LIBMAGIC_LIBS"
    fi
else
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_MAGIC=false")
    echo "ℹ pkg-config not available; libmagic auto-detect skipped"
    echo "  Install pkg-config or set LIBMAGIC_LIBS if libmagic is not on the default linker path"
fi

# Detect OpenSSL via pkg-config (or use OPENSSL_LIBS override). OpenSSL is required.
# Note: Odin's `foreign import "system:ssl"` already links -lssl/-lcrypto.
# We only need library search paths to avoid duplicate library warnings.
if [ -n "${OPENSSL_LIBS:-}" ]; then
    OPENSSL_LIBS_CLEAN=$(echo "${OPENSSL_LIBS}" | tr ' ' '\n' | grep -v '^-lssl$' | grep -v '^-lcrypto$' | tr '\n' ' ')
    LINKER_FLAGS="${LINKER_FLAGS} ${OPENSSL_LIBS_CLEAN}"
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_OPENSSL=true")
    echo "✓ OpenSSL flags from OPENSSL_LIBS: ${OPENSSL_LIBS_CLEAN}"
elif command -v pkg-config &> /dev/null; then
    OPENSSL_LIBS=$(pkg-config --libs-only-L --libs-only-other openssl 2>/dev/null || true)
    if [ -n "${OPENSSL_LIBS:-}" ] || pkg-config --exists openssl 2>/dev/null; then
        LINKER_FLAGS="${LINKER_FLAGS} ${OPENSSL_LIBS}"
        BUILD_FLAGS+=("-define:ZEPHYR_HAS_OPENSSL=true")
        echo "✓ OpenSSL detected: ${OPENSSL_LIBS}"
    else
        echo "Error: OpenSSL not detected. Install OpenSSL or set OPENSSL_LIBS."
        echo "  macOS: brew install openssl"
        echo "  Linux: apt install libssl-dev"
        exit 1
    fi
else
    echo "Error: pkg-config not available. OpenSSL is required."
    echo "  Install pkg-config and OpenSSL, or set OPENSSL_LIBS."
    exit 1
fi

# Detect libcurl via pkg-config (or use LIBCURL_LIBS override). libcurl is required.
# Note: Odin's `foreign import "system:curl"` already links -lcurl.
# We only need library search paths to avoid duplicate library warnings.
if [ -n "${LIBCURL_LIBS:-}" ]; then
    LIBCURL_LIBS_CLEAN=$(echo "${LIBCURL_LIBS}" | tr ' ' '\n' | grep -v '^-lcurl$' | tr '\n' ' ')
    LINKER_FLAGS="${LINKER_FLAGS} ${LIBCURL_LIBS_CLEAN}"
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_CURL=true")
    echo "✓ libcurl flags from LIBCURL_LIBS: ${LIBCURL_LIBS_CLEAN}"
elif command -v pkg-config &> /dev/null; then
    LIBCURL_LIBS=$(pkg-config --libs-only-L --libs-only-other libcurl 2>/dev/null || true)
    if [ -n "${LIBCURL_LIBS:-}" ] || pkg-config --exists libcurl 2>/dev/null; then
        LINKER_FLAGS="${LINKER_FLAGS} ${LIBCURL_LIBS}"
        BUILD_FLAGS+=("-define:ZEPHYR_HAS_CURL=true")
        echo "✓ libcurl detected: ${LIBCURL_LIBS}"
    else
        echo "Error: libcurl not detected. Install libcurl or set LIBCURL_LIBS."
        echo "  macOS: brew install curl"
        echo "  Linux: apt install libcurl4-openssl-dev"
        exit 1
    fi
else
    echo "Error: pkg-config not available. libcurl is required."
    echo "  Install pkg-config and libcurl, or set LIBCURL_LIBS."
    exit 1
fi

# Detect libarchive via pkg-config (or use LIBARCHIVE_LIBS override). Optional.
if [ -n "${LIBARCHIVE_LIBS:-}" ]; then
    LINKER_FLAGS="${LINKER_FLAGS} ${LIBARCHIVE_LIBS}"
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_ARCHIVE=true")
    echo "✓ libarchive flags from LIBARCHIVE_LIBS: ${LIBARCHIVE_LIBS}"
elif command -v pkg-config &> /dev/null; then
    LIBARCHIVE_LIBS=$(pkg-config --libs-only-L --libs-only-other libarchive 2>/dev/null || true)
    if pkg-config --exists libarchive 2>/dev/null; then
        LINKER_FLAGS="${LINKER_FLAGS} ${LIBARCHIVE_LIBS}"
        BUILD_FLAGS+=("-define:ZEPHYR_HAS_ARCHIVE=true")
        echo "✓ libarchive detected: ${LIBARCHIVE_LIBS}"
    else
        for keg_path in "/opt/homebrew/opt/libarchive" "/usr/local/opt/libarchive"; do
            if [ -f "${keg_path}/lib/libarchive.dylib" ] || [ -f "${keg_path}/lib/libarchive.so" ]; then
                LINKER_FLAGS="${LINKER_FLAGS} -L${keg_path}/lib"
                BUILD_FLAGS+=("-define:ZEPHYR_HAS_ARCHIVE=true")
                echo "✓ libarchive detected (keg-only): -L${keg_path}/lib"
                break
            fi
        done
        if [ -z "${LINKER_FLAGS##*libarchive*}" ] || [ -z "${LINKER_FLAGS##*-L*libarchive*}" ]; then
            :
        elif ! echo "$LINKER_FLAGS" | grep -q "libarchive"; then
            BUILD_FLAGS+=("-define:ZEPHYR_HAS_ARCHIVE=false")
            echo "ℹ libarchive not detected; tarball extraction disabled"
        fi
    fi
else
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_ARCHIVE=false")
    echo "ℹ pkg-config not available; libarchive auto-detect skipped"
fi

if [ -n "${LINKER_FLAGS// }" ]; then
    # De-duplicate linker flags to avoid ld warnings (e.g., duplicate -lgit2).
    declare -A _seen_flags=()
    _deduped_flags=()
    for _flag in ${LINKER_FLAGS}; do
        if [ -z "${_seen_flags[${_flag}]:-}" ]; then
            _seen_flags["${_flag}"]=1
            _deduped_flags+=("${_flag}")
        fi
    done
    LINKER_FLAGS="${_deduped_flags[*]}"
    BUILD_FLAGS+=("-extra-linker-flags:${LINKER_FLAGS}")
fi

# Verify source directory exists
if [ ! -d "src" ]; then
    echo "Error: src directory not found. Please run from the project root directory."
    exit 1
fi

# Build the project
echo "Compiling with Odin..."
odin build src "${BUILD_FLAGS[@]}" -out:$BINARY_NAME

# Verify binary was created
if [ ! -f "./$BINARY_NAME" ]; then
    echo "Error: Build failed. Binary not found."
    exit 1
fi

# Test the binary
echo "Testing binary..."
if ./$BINARY_NAME help > /dev/null 2>&1; then
    echo "✓ Binary test passed"
else
    echo "Warning: Binary test failed, but binary was created"
fi

echo "✓ Build complete: ./$BINARY_NAME"
echo "✓ Target: $OS/$ARCH"
