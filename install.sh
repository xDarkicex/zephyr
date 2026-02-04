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
description = "Core shell configuration and utilities"
author = "Zephyr Shell Loader"
license = "MIT"

[load]
priority = 10
files = ["exports.zsh", "aliases.zsh", "functions.zsh"]

[settings]
editor = "vim"
pager = "less"
history_size = "10000"
EOF

# Create example exports file
cat > "$MODULES_DIR/core/exports.zsh" << 'EOF'
# Core shell exports and environment variables
# This file is part of the Zephyr core module

# Set default editor and pager
export EDITOR="${EDITOR:-${ZSH_MODULE_CORE_EDITOR:-vim}}"
export PAGER="${PAGER:-${ZSH_MODULE_CORE_PAGER:-less}}"

# History configuration
export HISTSIZE="${ZSH_MODULE_CORE_HISTORY_SIZE:-10000}"
export SAVEHIST="$HISTSIZE"
export HISTFILE="$HOME/.zsh_history"

# Add Zephyr bin directory to PATH if not already present
if [[ ":$PATH:" != *":$HOME/.zsh/bin:"* ]]; then
    export PATH="$HOME/.zsh/bin:$PATH"
fi

# Set up colors for ls and grep
export CLICOLOR=1
export LSCOLORS="ExFxBxDxCxegedabagacad"

# Core module loaded indicator
export ZEPHYR_CORE_LOADED=1
EOF

# Create aliases file
cat > "$MODULES_DIR/core/aliases.zsh" << 'EOF'
# Core shell aliases
# This file is part of the Zephyr core module

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# List files with colors and details
alias ls='ls -G'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Quick directory listing
alias tree='find . -type d | sed -e "s/[^-][^\/]*\//  |/g" -e "s/|\([^ ]\)/|-\1/"'

# Zephyr-specific aliases
alias zr='zephyr load'
alias zl='zephyr list'
alias zv='zephyr validate'
alias zi='zephyr init'
EOF

# Create functions file
cat > "$MODULES_DIR/core/functions.zsh" << 'EOF'
# Core shell functions
# This file is part of the Zephyr core module

# Create directory and cd into it
mkcd() {
    if [ $# -ne 1 ]; then
        echo "Usage: mkcd <directory>"
        return 1
    fi
    mkdir -p "$1" && cd "$1"
}

# Find files by name
ff() {
    if [ $# -eq 0 ]; then
        echo "Usage: ff <filename_pattern>"
        return 1
    fi
    find . -name "*$1*" -type f
}

# Find directories by name
fd() {
    if [ $# -eq 0 ]; then
        echo "Usage: fd <dirname_pattern>"
        return 1
    fi
    find . -name "*$1*" -type d
}

# Extract various archive formats
extract() {
    if [ $# -ne 1 ]; then
        echo "Usage: extract <archive_file>"
        return 1
    fi
    
    if [ ! -f "$1" ]; then
        echo "Error: '$1' is not a valid file"
        return 1
    fi
    
    case "$1" in
        *.tar.bz2)   tar xjf "$1"     ;;
        *.tar.gz)    tar xzf "$1"     ;;
        *.bz2)       bunzip2 "$1"     ;;
        *.rar)       unrar x "$1"     ;;
        *.gz)        gunzip "$1"      ;;
        *.tar)       tar xf "$1"      ;;
        *.tbz2)      tar xjf "$1"     ;;
        *.tgz)       tar xzf "$1"     ;;
        *.zip)       unzip "$1"       ;;
        *.Z)         uncompress "$1"  ;;
        *.7z)        7z x "$1"        ;;
        *)           echo "Error: '$1' cannot be extracted via extract()" ;;
    esac
}

# Show PATH in a readable format
path() {
    echo "$PATH" | tr ':' '\n' | nl
}

# Reload Zephyr modules
reload_zephyr() {
    echo "Reloading Zephyr modules..."
    eval "$(zephyr load)"
    echo "✓ Zephyr modules reloaded"
}
EOF

echo "✓ Zephyr installed successfully!"
echo ""
echo "=== INTEGRATION INSTRUCTIONS ==="
echo ""
echo "Add this line to your ~/.zshrc to load modules automatically:"
echo ""
echo "  eval \"\$(\$HOME/.zsh/bin/zephyr load)\""
echo ""
echo "Or if you prefer to add the bin directory to your PATH first:"
echo ""
echo "  export PATH=\"\$HOME/.zsh/bin:\$PATH\""
echo "  eval \"\$(zephyr load)\""
echo ""
echo "=== QUICK START ==="
echo ""
echo "1. Add the eval line to your ~/.zshrc:"
echo "   echo 'eval \"\$(\$HOME/.zsh/bin/zephyr load)\"' >> ~/.zshrc"
echo ""
echo "2. Reload your shell:"
echo "   source ~/.zshrc"
echo ""
echo "3. Verify installation:"
echo "   zephyr list"
echo ""
echo "=== LOCATIONS ==="
echo "Binary: $BIN_DIR/zephyr"
echo "Modules: $MODULES_DIR"
echo "Integration guide: ./INTEGRATION.md"
echo ""
echo "=== NEXT STEPS ==="
echo "- Create new modules with: zephyr init <module-name>"
echo "- Validate modules with: zephyr validate"
echo "- List modules with: zephyr list"
echo ""
echo "For detailed integration instructions, see INTEGRATION.md"