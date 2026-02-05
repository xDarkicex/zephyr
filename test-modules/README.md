# Test Modules

This directory contains example modules used for testing and demonstration purposes.

## Purpose

- **Integration Testing**: Used by the test suite to verify module loading and dependency resolution
- **Examples**: Demonstrates proper module structure and manifest format
- **Development**: Useful for testing changes to the loader without affecting real modules

## Modules

### core
Basic core utilities module demonstrating:
- Multiple file types (aliases, exports, functions)
- Module manifest structure
- Documentation

### git-helpers
Git workflow helpers demonstrating:
- Dependencies (requires core)
- Multiple shell files
- Practical use case

## Usage

These modules are automatically used by the test suite. You can also test them manually:

```bash
# Test with these modules
ZSH_MODULES_DIR="$PWD/test-modules" ./zephyr list

# Load them
ZSH_MODULES_DIR="$PWD/test-modules" ./zephyr load
```

## Note

These are **example modules only** - not meant for production use. For real modules, use `~/.zsh/modules` or your configured modules directory.
