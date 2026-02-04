# Core Module

The core module provides essential shell configuration and utilities for Zephyr Shell Loader.

## Features

### Environment Variables
- Sets up `EDITOR`, `PAGER`, and history configuration
- Configures colors for `ls` and `grep`
- Adds Zephyr bin directory to PATH

### Aliases
- Directory navigation shortcuts (`..`, `...`, `....`)
- Enhanced `ls` commands with colors (`ll`, `la`, `l`)
- Safety aliases for destructive operations (`rm -i`, `cp -i`, `mv -i`)
- Colored grep commands
- Zephyr command shortcuts (`zr`, `zl`, `zv`, `zi`)

### Functions
- `mkcd <dir>` - Create directory and cd into it
- `ff <pattern>` - Find files by name pattern
- `fd <pattern>` - Find directories by name pattern
- `extract <file>` - Extract various archive formats
- `path` - Display PATH in readable format
- `reload_zephyr` - Reload all Zephyr modules

## Configuration

The module respects the following settings (configured in `module.toml`):

- `editor` - Default text editor (default: vim)
- `pager` - Default pager (default: less)
- `history_size` - Shell history size (default: 10000)

These settings are exported as environment variables with the `ZSH_MODULE_CORE_` prefix.

## Usage

This module is automatically loaded by Zephyr and should be given a low priority (10) to ensure it loads before other modules that might depend on its functionality.