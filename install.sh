#!/usr/bin/env bash
set -euo pipefail

ZSH_DIR="$HOME/.zsh"
BIN_DIR="$ZSH_DIR/bin"
MODULES_DIR="$ZSH_DIR/modules"

echo "Installing Zephyr Shell Loader..."

# Create directories
echo "Creating directories..."
mkdir -p "$BIN_DIR" "$MODULES_DIR"

# Build binary
echo "Building Zephyr..."
if [ ! -f "./build.sh" ]; then
    echo "Error: build.sh not found. Please run from the project root directory."
    exit 1
fi

./build.sh

# Check if binary was created
if [ ! -f "./zephyr" ]; then
    echo "Error: Build failed. Binary not found."
    exit 1
fi

# Move binary
echo "Installing binary to $BIN_DIR..."
mv zephyr "$BIN_DIR/"

# Create example core module
echo "Creating example core module..."
mkdir -p "$MODULES_DIR/core"
cat > "$MODULES_DIR/core/module.toml" << 'EOF'
[module]
name = "core"
version = "1.0.0"
description = "Core shell configuration"
priority = 10

[load]
files = ["exports.zsh"]
EOF

# Create example exports file
cat > "$MODULES_DIR/core/exports.zsh" << 'EOF'
# Core shell exports
export EDITOR="${EDITOR:-vim}"
export PAGER="${PAGER:-less}"

# Add Zephyr bin directory to PATH if not already present
if [[ ":$PATH:" != *":$HOME/.zsh/bin:"* ]]; then
    export PATH="$HOME/.zsh/bin:$PATH"
fi
EOF

echo "✓ Zephyr installed successfully!"
echo ""
echo "Installation complete. Add this to your .zshrc:"
echo '  eval "$($HOME/.zsh/bin/zephyr load)"'
echo ""
echo "Or add the bin directory to your PATH and use:"
echo '  eval "$(zephyr load)"'
echo ""
echo "Modules directory: $MODULES_DIR"
echo "Binary location: $BIN_DIR/zephyr"