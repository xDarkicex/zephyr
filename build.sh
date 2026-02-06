#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="zephyr"
BUILD_FLAGS=(-o:speed)

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
    BUILD_FLAGS+=("-extra-linker-flags:${LIBGIT2_LIBS}")
    echo "✓ libgit2 flags from LIBGIT2_LIBS: ${LIBGIT2_LIBS}"
elif command -v pkg-config &> /dev/null; then
    LIBGIT2_LIBS=$(pkg-config --libs libgit2 2>/dev/null || true)
    if [ -n "${LIBGIT2_LIBS:-}" ]; then
        BUILD_FLAGS+=("-extra-linker-flags:${LIBGIT2_LIBS}")
        echo "✓ libgit2 detected: ${LIBGIT2_LIBS}"
    else
        echo "ℹ libgit2 not detected; install libgit2 or set LIBGIT2_LIBS"
    fi
else
    echo "ℹ pkg-config not available; libgit2 auto-detect skipped"
    echo "  Install pkg-config or set LIBGIT2_LIBS if libgit2 is not on the default linker path"
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
