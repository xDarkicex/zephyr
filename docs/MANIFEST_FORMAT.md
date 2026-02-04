# TOML Manifest Format Reference

This document provides a comprehensive reference for the `module.toml` manifest format used by Zephyr Shell Loader.

## Table of Contents

- [Overview](#overview)
- [File Structure](#file-structure)
- [Section Reference](#section-reference)
- [Field Types](#field-types)
- [Examples](#examples)
- [Validation Rules](#validation-rules)
- [Best Practices](#best-practices)

## Overview

Every Zephyr module must contain a `module.toml` file in its root directory. This file describes the module's metadata, dependencies, platform requirements, and loading configuration.

The manifest uses [TOML](https://toml.io/) (Tom's Obvious, Minimal Language) format, which is human-readable and easy to parse.

## File Structure

```toml
[module]           # Required: Basic module information
[dependencies]     # Optional: Module dependencies
[platforms]        # Optional: Platform compatibility
[load]            # Optional: Loading configuration
[hooks]           # Optional: Pre/post load hooks
[settings]        # Optional: Environment variables
```

## Section Reference

### `[module]` Section (Required)

Contains basic module metadata.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique module identifier (kebab-case recommended) |
| `version` | string | Yes | Semantic version (e.g., "1.2.3") |
| `description` | string | No | Brief description of the module |
| `author` | string | No | Author name and email |
| `license` | string | No | License identifier (e.g., "MIT", "GPL-3.0") |

**Example:**
```toml
[module]
name = "git-helpers"
version = "1.2.0"
description = "Git utility functions and aliases"
author = "John Doe <john@example.com>"
license = "MIT"
```

### `[dependencies]` Section (Optional)

Specifies module dependencies that must be loaded before this module.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `required` | array of strings | No | Modules that must be present and loaded first |
| `optional` | array of strings | No | Modules that should be loaded first if available |

**Example:**
```toml
[dependencies]
required = ["core", "colors"]
optional = ["fzf-integration", "git-completion"]
```

**Dependency Resolution:**
- Required dependencies must exist or loading fails
- Optional dependencies are loaded if available, ignored if missing
- Circular dependencies are detected and cause loading to fail
- Dependencies are resolved using topological sorting

### `[platforms]` Section (Optional)

Restricts module loading to compatible platforms.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `os` | array of strings | No | Operating systems: "linux", "darwin", "windows" |
| `arch` | array of strings | No | Architectures: "x86_64", "arm64", "i386" |
| `shell` | string | No | Shell requirement: "zsh", "bash", "fish" |
| `min_version` | string | No | Minimum shell version required |

**Example:**
```toml
[platforms]
os = ["linux", "darwin"]
arch = ["x86_64", "arm64"]
shell = "zsh"
min_version = "5.8"
```

**Platform Matching:**
- If any platform field is specified, ALL conditions must match
- Empty arrays or missing fields match any platform
- Version comparison uses semantic versioning rules

### `[load]` Section (Optional)

Controls how the module is loaded.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `priority` | integer | No | Load priority (lower numbers load first, default: 100) |
| `files` | array of strings | No | Shell files to source (default: ["init.zsh"]) |

**Example:**
```toml
[load]
priority = 50
files = ["aliases.zsh", "functions.zsh", "completions.zsh"]
```

**Priority Guidelines:**
- `1-10`: Core system modules
- `11-50`: Framework and utility modules
- `51-100`: Application-specific modules
- `101+`: User customizations

### `[hooks]` Section (Optional)

Defines functions to execute before and after loading module files.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `pre_load` | string | No | Function name to call before sourcing files |
| `post_load` | string | No | Function name to call after sourcing files |

**Example:**
```toml
[hooks]
pre_load = "setup_git_config"
post_load = "register_completions"
```

**Hook Requirements:**
- Hook functions must be defined in one of the module's shell files
- Hooks are called with `typeset -f` check for safety
- Failed hooks don't prevent module loading

### `[settings]` Section (Optional)

Defines environment variables to export when the module loads.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `<key>` | string | No | Any key-value pair to export as environment variable |

**Example:**
```toml
[settings]
editor = "nvim"
theme = "dark"
auto_update = "true"
```

**Environment Variable Naming:**
Settings are exported with the prefix `ZSH_MODULE_<MODULE_NAME>_<KEY>`:
- `editor` becomes `ZSH_MODULE_GIT_HELPERS_EDITOR`
- `theme` becomes `ZSH_MODULE_GIT_HELPERS_THEME`
- Module names are converted to uppercase
- Hyphens in module names become underscores

## Field Types

### String
Single-line text values enclosed in quotes:
```toml
name = "my-module"
description = "A sample module"
```

### Array of Strings
Multiple string values in square brackets:
```toml
files = ["aliases.zsh", "functions.zsh"]
required = ["core", "colors"]
```

### Integer
Numeric values without quotes:
```toml
priority = 50
```

### Boolean
True/false values (for future use):
```toml
enabled = true
```

## Examples

### Minimal Module

```toml
[module]
name = "simple-aliases"
version = "1.0.0"

[load]
files = ["aliases.zsh"]
```

### Complete Module

```toml
[module]
name = "advanced-git"
version = "2.1.0"
description = "Advanced Git workflow tools"
author = "Jane Developer <jane@example.com>"
license = "MIT"

[dependencies]
required = ["core"]
optional = ["colors", "fzf"]

[platforms]
os = ["linux", "darwin"]
shell = "zsh"
min_version = "5.8"

[load]
priority = 60
files = [
    "git-aliases.zsh",
    "git-functions.zsh",
    "git-completions.zsh"
]

[hooks]
pre_load = "check_git_version"
post_load = "setup_git_completions"

[settings]
default_branch = "main"
push_default = "simple"
auto_fetch = "true"
editor = "code"
```

### Framework Module

```toml
[module]
name = "zsh-framework"
version = "3.0.0"
description = "Core ZSH framework functionality"
author = "Framework Team <team@framework.org>"
license = "Apache-2.0"

[load]
priority = 5
files = [
    "core.zsh",
    "utils.zsh",
    "prompt.zsh"
]

[hooks]
pre_load = "framework_init"
post_load = "framework_ready"

[settings]
theme = "default"
auto_update = "weekly"
prompt_style = "minimal"
```

## Validation Rules

### Required Fields
- `[module]` section must exist
- `module.name` must be specified
- `module.version` must be specified

### Naming Conventions
- Module names should use kebab-case (e.g., "git-helpers")
- Module names must be unique within a modules directory
- File names should use kebab-case or snake_case

### Version Format
- Must follow semantic versioning (MAJOR.MINOR.PATCH)
- Examples: "1.0.0", "2.1.3", "0.5.0-beta"

### File Paths
- All file paths in `files` array are relative to module directory
- Files must exist when module is loaded
- Shell files should have `.zsh`, `.sh`, or no extension

### Dependencies
- Dependency names must match existing module names exactly
- Circular dependencies are not allowed
- Self-dependencies are not allowed

## Best Practices

### Module Naming
- Use descriptive, kebab-case names
- Avoid generic names like "utils" or "helpers"
- Include the primary function: "git-workflow", "docker-aliases"

### Version Management
- Start with "1.0.0" for stable modules
- Use "0.x.x" for experimental modules
- Increment appropriately for breaking changes

### Dependencies
- Keep dependencies minimal
- Use optional dependencies for nice-to-have features
- Document dependency requirements in module README

### File Organization
- Use descriptive file names: "aliases.zsh", "functions.zsh"
- Group related functionality in separate files
- Keep files focused on single concerns

### Priority Assignment
- Use standard priority ranges
- Leave gaps for future modules
- Document priority choices in module README

### Settings
- Use clear, descriptive setting names
- Provide sensible defaults
- Document all settings in module README

### Platform Compatibility
- Be specific about platform requirements
- Test on all supported platforms
- Use platform checks in shell code when needed

## Common Patterns

### Theme Module
```toml
[module]
name = "my-theme"
version = "1.0.0"

[dependencies]
required = ["core"]

[load]
priority = 90
files = ["theme.zsh"]

[settings]
primary_color = "blue"
secondary_color = "green"
prompt_style = "minimal"
```

### Tool Integration
```toml
[module]
name = "docker-helpers"
version = "1.5.0"

[dependencies]
optional = ["completion-framework"]

[platforms]
os = ["linux", "darwin"]

[load]
priority = 70
files = ["docker-aliases.zsh", "docker-functions.zsh"]

[hooks]
pre_load = "check_docker_installed"

[settings]
default_registry = "docker.io"
auto_cleanup = "true"
```

### Development Environment
```toml
[module]
name = "dev-env"
version = "2.0.0"

[dependencies]
required = ["core", "colors"]

[load]
priority = 40
files = ["exports.zsh", "aliases.zsh", "functions.zsh"]

[settings]
editor = "code"
terminal = "alacritty"
browser = "firefox"
node_version = "18"
```