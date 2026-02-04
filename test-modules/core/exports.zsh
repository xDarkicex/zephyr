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