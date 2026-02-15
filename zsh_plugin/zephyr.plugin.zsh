# Zephyr Shell Loader Plugin
# Automatically sets up Zephyr when loaded via zsh plugin managers

# Get the directory where this plugin is installed
ZEPHYR_PLUGIN_DIR="${0:A:h}"

# Set default paths
export ZEPHYR_BIN="${ZEPHYR_BIN:-$HOME/.zsh/bin/zephyr}"
export ZSH_MODULES_DIR="${ZSH_MODULES_DIR:-$HOME/.zephyr/modules}"

# Check if zephyr binary exists
if [[ ! -f "$ZEPHYR_BIN" ]]; then
    echo "⚠️  Zephyr binary not found at: $ZEPHYR_BIN"
    echo "   Run: make install"
    echo "   Or set ZEPHYR_BIN to the correct path"
    return 1
fi

# Add zephyr to PATH if not already there
if [[ ":$PATH:" != *":${ZEPHYR_BIN:h}:"* ]]; then
    export PATH="${ZEPHYR_BIN:h}:$PATH"
fi

# Load Zephyr modules
eval "$(zephyr load)"

# Optional: Add completion for zephyr command
if [[ -d "$ZEPHYR_PLUGIN_DIR/completions" ]]; then
    fpath=("$ZEPHYR_PLUGIN_DIR/completions" $fpath)
    autoload -Uz compinit
fi
