# Modules Directory

This directory is a placeholder for development modules.

## Default Module Location

By default, Zephyr looks for modules in `~/.zsh/modules`, not this directory.

## Using This Directory

If you want to use this directory for development:

```bash
# Set the modules directory
export ZSH_MODULES_DIR="$PWD/modules"

# Create a module
./zephyr init my-dev-module

# List modules
./zephyr list
```

## Recommendation

For production use, keep your modules in `~/.zsh/modules` as configured in your shell.

For testing, use the `test-modules/` directory which contains example modules.
