# Zephyr Shell Loader

A fast, dependency-aware shell module loader written in Odin.

## Overview

Zephyr is a shell module loader system that manages dependencies, load order, and configuration for shell modules (primarily ZSH). It reads TOML manifests, resolves dependencies using topological sorting, and emits shell code for sourcing modules in the correct order.

## Features

- **Dependency Resolution**: Automatic dependency resolution with cycle detection
- **Module Discovery**: Recursive discovery of modules in your shell configuration
- **TOML Configuration**: Simple, readable module manifests
- **Platform Filtering**: Load modules only on compatible platforms
- **Priority Ordering**: Control load order with priority values
- **Hook System**: Pre and post-load hooks for advanced module setup

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/xDarkicex/zephyr.git
cd zephyr

# Install Zephyr
./install.sh
```

### Usage

Add to your `.zshrc`:

```bash
eval "$(zephyr load)"
```

### Creating Modules

Create a new module:

```bash
zephyr init my-module
```

This creates a directory structure with a `module.toml` manifest:

```toml
[module]
name = "my-module"
version = "1.0.0"
description = "My custom shell module"

[load]
files = ["init.zsh"]
```

## Commands

- `zephyr load` - Generate shell code for loading modules (default)
- `zephyr list` - Show discovered modules and load order
- `zephyr validate` - Validate module manifests
- `zephyr init <name>` - Create a new module skeleton

## Module Configuration

Modules are configured using TOML manifests (`module.toml`):

```toml
[module]
name = "git-helpers"
version = "1.2.0"
description = "Git utility functions and aliases"
author = "John Doe <john@example.com>"
license = "MIT"

[dependencies]
required = ["core", "colors"]
optional = ["fzf-integration"]

[platforms]
os = ["linux", "darwin"]
arch = ["x86_64", "arm64"]
shell = "zsh"
min_version = "5.8"

[load]
priority = 50
files = ["git-aliases.zsh", "git-functions.zsh"]

[hooks]
pre_load = "git_check_version"
post_load = "git_setup_completion"

[settings]
default_branch = "main"
auto_fetch = "true"
```

## Requirements

- [Odin compiler](https://odin-lang.org/docs/install/)
- ZSH shell
- macOS or Linux

## Building from Source

```bash
./build.sh
```

## License

MIT License - see LICENSE file for details.
