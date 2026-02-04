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