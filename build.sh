#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="zephyr"
BUILD_FLAGS=(-o:speed)
LINKER_FLAGS=""

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

# Detect libgit2 via pkg-config (or use LIBGIT2_LIBS override)
if [ -n "${LIBGIT2_LIBS:-}" ]; then
    LINKER_FLAGS="${LINKER_FLAGS} ${LIBGIT2_LIBS}"
    echo "✓ libgit2 flags from LIBGIT2_LIBS: ${LIBGIT2_LIBS}"
elif command -v pkg-config &> /dev/null; then
    LIBGIT2_LIBS=$(pkg-config --libs libgit2 2>/dev/null || true)
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
if [ -n "${LIBMAGIC_LIBS:-}" ]; then
    LINKER_FLAGS="${LINKER_FLAGS} ${LIBMAGIC_LIBS}"
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_MAGIC=true")
    echo "✓ libmagic flags from LIBMAGIC_LIBS: ${LIBMAGIC_LIBS}"
elif command -v pkg-config &> /dev/null; then
    LIBMAGIC_LIBS=$(pkg-config --libs libmagic 2>/dev/null || true)
    if [ -n "${LIBMAGIC_LIBS:-}" ]; then
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
if [ -n "${OPENSSL_LIBS:-}" ]; then
    LINKER_FLAGS="${LINKER_FLAGS} ${OPENSSL_LIBS}"
    BUILD_FLAGS+=("-define:ZEPHYR_HAS_OPENSSL=true")
    echo "✓ OpenSSL flags from OPENSSL_LIBS: ${OPENSSL_LIBS}"
elif command -v pkg-config &> /dev/null; then
    OPENSSL_LIBS=$(pkg-config --libs openssl 2>/dev/null || true)
    if [ -n "${OPENSSL_LIBS:-}" ]; then
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

if [ -n "${LINKER_FLAGS// }" ]; then
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
