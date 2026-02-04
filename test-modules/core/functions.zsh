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