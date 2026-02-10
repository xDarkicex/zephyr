# Zephyr Shell Loader

A fast, dependency-aware shell module loader written in Odin that brings order to your shell configuration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](https://github.com/zephyr-systems/zephyr)

## Overview

Zephyr is a shell module loader system that manages dependencies, load order, and configuration for shell modules (ZSH and Bash). It reads TOML manifests, resolves dependencies using topological sorting, and emits shell code for sourcing modules in the correct order.

**Why Zephyr?**
- 🚀 **Fast**: Written in Odin for minimal startup overhead
- 🔗 **Smart Dependencies**: Automatic resolution with cycle detection
- 📦 **Modular**: Organize your shell config into reusable modules
- 🎯 **Platform Aware**: Load modules only where they're supported
- 🛠️ **Developer Friendly**: Simple TOML configuration
- 🐛 **Excellent Debugging**: Verbose output, colored errors, and helpful suggestions
- 🎨 **Beautiful Output**: Colored terminal output with clear formatting
- 🤖 **Machine Readable**: JSON security scan output for AI assistants and automation tools
- 🧪 **Security Scanning**: Language-agnostic scanning with CVE coverage, credential and reverse shell detection, and git hook blocking
- 🛡️ **Command Scanning**: Silent safety check for runtime commands via `zephyr scan "cmd"`

## Security Model

Zephyr provides **structured security signals** to help identify obvious risks in shell modules.
It is **not a security guarantee**—no static scanner can detect all malicious code.

### Installation Security Pipeline

Zephyr uses a **clone (no checkout) → scan → validate → checkout → move** pipeline to isolate modules during analysis:

1. **Clone to temp (no checkout)**: Repository cloned without checking out files (hooks cannot execute)
2. **Security scan**: All files scanned for dangerous patterns while isolated
3. **Validation**: Manifest and dependencies validated
4. **Controlled checkout**: Files are checked out only after scan + validation
5. **Move to final**: Only if all checks pass, moved to `~/.zsh/modules/`

This ensures malicious code cannot execute during the scan, and failed scans leave no artifacts.
Git hooks are detected during the scan and **blocked by default** (install fails unless `--unsafe` is used).

See [docs/SECURITY_PIPELINE.md](docs/SECURITY_PIPELINE.md) for a technical breakdown.

### What Zephyr Detects (v1.2)
- ✅ Obvious remote code execution patterns (`curl|bash`, `wget|sh`)
- ✅ Dangerous operations (`rm -rf /`, `dd if=`)
- ✅ Insecure HTTP downloads (`curl http://`)
- ✅ Common obfuscation patterns (e.g., `base64 -d | sh`, process substitution)
- ✅ Git hooks present in `.git/hooks/` (blocked unless `--unsafe`)
- ✅ Symlink evasion attempts (symlinks pointing outside the module)
- ✅ Binary and oversized files (skipped with warnings; libmagic improves detection)
- ✅ Credential file access (AWS, SSH, Docker, Kubernetes, package managers, AI APIs)
- ✅ Reverse shell patterns (bash TCP/UDP, netcat, socat, Python, Perl)
- ✅ CI/CD configuration manipulation (GitHub Actions, GitLab CI, CircleCI)
- ✅ Context-aware downgrades in build tooling files
- ✅ Pattern coupling to reduce false positives
- ✅ Trusted module relaxations (oh-my-zsh, zinit, nvm, rbenv, pyenv, asdf)

### Critical Limitations
- ⚠️ **Cannot detect sophisticated obfuscation** (multi-stage or encrypted payloads)
- ⚠️ **Cannot analyze behavior** (code may execute only under specific conditions)
- ⚠️ **No runtime protection** (approved modules execute with full user privileges)
- ✅ **Git hook mitigation**: Zephyr clones without checkout, so hooks cannot run before scan

### Responsible Usage
- 🔒 **For agents**: Only install from pre-vetted sources. Never allow autonomous `--unsafe`.
- 👁️ **For humans**: Review source before approving warnings or using `--unsafe`.
- 📜 **For compliance**: Treat `zephyr scan` as a *risk assessment tool*, not a security boundary.

### Trusted Modules
Zephyr supports a trusted module allowlist to reduce false positives for known frameworks
(`oh-my-zsh`, `zinit`, `nvm`, `rbenv`, `pyenv`, `asdf`). You can extend this list via:

`~/.zephyr/trusted_modules.toml`

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Module Development](#module-development)
- [Configuration Reference](#configuration-reference)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Installation

### Prerequisites

- [Odin compiler](https://odin-lang.org/docs/install/) (for building from source)
- libgit2 (required for git-based module management)
- OpenSSL (required for security scanning and module signing)
- libcurl (required for signed module release discovery)
- pkg-config (recommended for auto-detection of dependencies)
- libmagic (optional, improves binary detection in security scans)
- ZSH shell
- macOS or Linux

### Quick Install (Plugin Manager)

If you use a zsh plugin manager (Oh My Zsh, Zinit, Antigen, etc.):

```bash
# 1. Build and install zephyr
git clone https://github.com/zephyr-systems/zephyr.git
cd zephyr
make install

# 2. Add as plugin (example for Oh My Zsh)
git clone https://github.com/zephyr-systems/zephyr.git \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zephyr

# 3. Add to ~/.zshrc plugins list
plugins=(... zephyr)
```

See [zsh_plugin/README.md](zsh_plugin/README.md) for detailed instructions for all plugin managers.

### Install from Source

```bash
# Clone the repository
git clone https://github.com/zephyr-systems/zephyr.git
cd zephyr

# Install dependencies (examples)
# macOS (Homebrew)
brew install libgit2 pkg-config openssl curl
# Ubuntu/Debian
sudo apt-get install -y libgit2-dev pkg-config libssl-dev libcurl4-openssl-dev

# Build and install (recommended)
make install

# Or build only
make build
```

This will:
1. Build the `zephyr` binary
2. Install it to `$HOME/.zsh/bin/zephyr`
3. Create the modules directory at `$HOME/.zsh/modules`
4. Set up a basic `core` module

**Available make targets:**
```bash
make help           # Show all available commands
make build          # Build the binary
make install        # Build and install
make test           # Run test suite
make benchmark      # Run performance benchmark
make clean          # Remove build artifacts
```

Note: `make build` and `make test` will automatically link libgit2, OpenSSL,
and libcurl if they are available via `pkg-config`.

### Shell Integration

Zephyr supports both **ZSH** and **Bash**. It automatically detects your shell from the `$SHELL` environment variable.

**For ZSH** - add to your `.zshrc`:
```bash
eval "$($HOME/.zsh/bin/zephyr load)"
```

**For Bash** - add to your `.bashrc`:
```bash
eval "$($HOME/.zsh/bin/zephyr load)"
```

Or if you prefer to add the bin directory to your PATH:

```bash
export PATH="$HOME/.zsh/bin:$PATH"
eval "$(zephyr load)"
```

#### Force Shell Type

You can override automatic detection with the `--shell` flag:

```bash
# Force Bash output (even when running in ZSH)
zephyr load --shell=bash

# Force ZSH output (even when running in Bash)
zephyr load --shell=zsh

# Generate a Bash script from a ZSH environment
zephyr load --shell=bash > /tmp/modules.sh
```

**Note:** Environment variables use the `ZSH_MODULE_*` prefix for historical reasons, but work perfectly in both ZSH and Bash.

### Verify Installation

```bash
# Check if zephyr is working
zephyr list

# Should show something like:
# MODULE DISCOVERY RESULTS
#   Directory: /Users/user/.zsh/modules
#   Modules: 1 total, 1 compatible
#   Platform: darwin/arm64, shell: zsh 5.9
#
# ✓ core v1.0.0
#   Description: Core shell utilities and functions
#   Path: /Users/user/.zsh/modules/core

# Test with verbose output
zephyr -v validate
# Should show: ✓ All modules are valid and ready to load!
```

## Quick Start

### 1. Create Your First Module

```bash
# Create a new module for your aliases
zephyr init my-aliases
```

This creates:
```
$HOME/.zsh/modules/my-aliases/
├── module.toml
├── aliases.zsh
└── functions.zsh
```

### 2. Add Some Content

Edit `$HOME/.zsh/modules/my-aliases/aliases.zsh`:

```bash
# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'

# Directory navigation
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
```

### 3. Reload Your Shell

```bash
# Reload your shell configuration
exec zsh

# Or test without reloading using verbose mode
zephyr -v load
```

Your aliases are now available! Zephyr automatically discovered and loaded your module.

**Tip**: Use `zephyr list` to see all your modules and their load order, or `zephyr validate` to check for any configuration issues.

## Commands

Zephyr supports various command-line flags for enhanced output and debugging:

### Global Flags

- `-v, --verbose`: Enable verbose output with detailed operation information
- `-d, --debug`: Enable debug output with internal processing details  
- `--trace`: Enable maximum verbosity with trace-level debugging
- `--no-color`: Disable colored output (useful for scripts or non-color terminals)
- `-h, --help`: Show help information

### Environment Variables

- `ZEPHYR_DEBUG`: Enable debug output (0-3 or false/true/debug/trace)
- `ZEPHYR_VERBOSE`: Enable verbose output (0-3 or false/true)
- `ZEPHYR_DEBUG_TIMESTAMPS`: Show timestamps in debug output
- `ZEPHYR_DEBUG_LOCATION`: Show source location in debug output
- `NO_COLOR`: Disable colored output
- `ZSH_MODULES_DIR`: Override default modules directory

### `zephyr load` (default)

Generates shell code for loading all discovered modules in dependency order.

```bash
# Generate and execute module loading code
eval "$(zephyr load)"

# Or just see what would be loaded
zephyr load

# With verbose output to see what's happening
zephyr -v load

# With debug output for troubleshooting
zephyr --debug load
```

**Output example:**
```bash
# Generated by Zephyr Shell Loader
# Generated: 2024-01-15 10:30:45

# === Module: core v1.0.0 ===
export ZSH_MODULE_CORE_THEME="default"
source "$HOME/.zsh/modules/core/exports.zsh"

# === Module: my-aliases v1.0.0 ===
source "$HOME/.zsh/modules/my-aliases/aliases.zsh"
```

### `zephyr list`

Shows all discovered modules and their load order with enhanced formatting.

```bash
# Basic module listing
zephyr list

# With verbose output showing platform compatibility
zephyr -v list

# With debug information
zephyr --debug list
```

**Output example:**
```
MODULE DISCOVERY RESULTS
  Directory: /Users/user/.zsh/modules
  Modules: 4 total, 3 compatible
  Platform: darwin/arm64, shell: zsh 5.9

⚠ INCOMPATIBLE MODULES
  ⚠ linux-only v1.0.0 (OS: linux)

✓ LOAD ORDER
4 module(s) will be loaded in dependency order

#  Module      Version  Priority  Dependencies
1  core        1.0.0    10        -
2  colors      1.1.0    20        core
3  git-helpers 2.0.0    50        core, colors
4  my-aliases  1.0.0    100       -

✓ core v1.0.0
  Description: Core shell utilities and functions
  Path: /Users/user/.zsh/modules/core

✓ Summary: 4 modules ready to load
```

#### JSON Output

Get machine-readable JSON output for programmatic access:

```bash
# Output module information as JSON
zephyr list --json

# Pretty-printed JSON with indentation
zephyr list --json --pretty

# Filter modules by name pattern (case-insensitive)
zephyr list --json --filter=git

# Combine with other flags
zephyr -v list --json --pretty --filter=core
```

**JSON Output Structure:**
```json
{
  "schema_version": "1.0",
  "generated_at": "2026-02-06T10:30:45Z",
  "environment": {
    "zephyr_version": "1.0.0",
    "modules_directory": "/Users/user/.zsh/modules",
    "platform": {
      "os": "darwin",
      "arch": "arm64",
      "shell": "zsh",
      "shell_version": "5.9"
    }
  },
  "summary": {
    "total_modules": 4,
    "compatible_modules": 3,
    "incompatible_modules": 1
  },
  "modules": [
    {
      "name": "core",
      "version": "1.0.0",
      "description": "Core shell utilities",
      "load_order": 1,
      "priority": 10,
      "dependencies": {
        "required": [],
        "optional": []
      },
      "exports": {
        "functions": ["mkcd", "extract"],
        "aliases": ["ll", "la"],
        "environment_variables": ["ZSH_MODULE_CORE_THEME"]
      }
    }
  ],
  "incompatible_modules": [
    {
      "name": "linux-only",
      "version": "1.0.0",
      "reason": "OS mismatch: requires linux, current: darwin"
    }
  ]
}
```

**Use Cases:**
- **AI Assistants**: Discover available shell functions and aliases
- **Scripts**: Parse module information programmatically
- **Tools**: Integrate with external tools using `jq` or similar
- **Monitoring**: Track module configuration across systems

**Example with jq:**
```bash
# List all module names
zephyr list --json | jq -r '.modules[].name'

# Get modules with dependencies
zephyr list --json | jq '.modules[] | select(.dependencies.required | length > 0)'

# Count total exported functions
zephyr list --json | jq '[.modules[].exports.functions[]] | length'

# Find modules exporting a specific function
zephyr list --json | jq -r '.modules[] | select(.exports.functions[] | contains("mkcd")) | .name'
```

### `zephyr validate`

Validates all module manifests for syntax errors and dependency issues with detailed error reporting and suggestions.

```bash
# Basic validation
zephyr validate

# With verbose output
zephyr -v validate

# With debug information for troubleshooting
zephyr --debug validate
```

**Success output:**
```
Validating modules in: /Users/user/.zsh/modules

Found 3 module manifest(s)

VALIDATION SUMMARY
==================
Total: 3 | Success: 3 | Errors: 0

✓ All modules are valid and ready to load!
Use 'zephyr list' to see the load order.
```

**Error output with suggestions:**
```
Validating modules in: /Users/user/.zsh/modules

Found 2 module manifest(s)

✗ PARSING ERRORS
Found 1 module(s) with parsing errors

✗ /Users/user/.zsh/modules/bad-module/module.toml
  Error: Missing required 'name' field in [module] section
  File: /Users/user/.zsh/modules/bad-module/module.toml
  Operation: Manifest validation

Suggested fixes:

  1. Add required fields
     Why: Ensure your module.toml has at least a [module] section with a 'name' field

  2. Check field names  
     Why: Verify all field names match the expected schema (name, version, dependencies, etc.)

  3. Use init template
     Command: zephyr init example-module
     Why: Create a new module to see the correct manifest format

✗ DEPENDENCY ERRORS
Found modules with dependency issues

✗ Module: git-helpers
  Path: /Users/user/.zsh/modules/git-helpers/module.toml
  ✗ Missing required dependency: 'colors'

Suggested fixes:

  1. Install the missing dependency
     Command: zephyr init colors
     Why: Create the missing dependency module if it doesn't exist

  2. Check available modules
     Command: zephyr list
     Why: See what modules are currently available in your modules directory

VALIDATION SUMMARY
==================
Total: 2 | Success: 0 | Errors: 2

✗ Validation failed. Please fix the errors above.
Use 'zephyr validate' again after making changes.
```

### `zephyr install <source>`

Installs a module from a git repository and validates it before moving it into your modules directory.

Supported source formats:
- HTTPS or SSH git URL
- GitHub shorthand: `user/repo`
- Local path (requires `--local`)

```bash
# Install from HTTPS
zephyr install https://github.com/user/zephyr-git-helpers

# Install from GitHub shorthand
zephyr install user/zephyr-git-helpers

# Install from a local repo path
zephyr install --local /path/to/module-repo

# Reinstall an existing module
zephyr install --force https://github.com/user/zephyr-git-helpers

# Install despite critical security findings (bypass scan)
zephyr install --unsafe https://github.com/user/zephyr-git-helpers
```

**Flags:**
- `--force`: Reinstall if the module already exists
- `--local`: Treat the source as a local path
- `--unsafe`: Bypass security scan blocking (still prints findings)
  - ⚠️ **WARNING**: This does **not** make a module safe. Only use after manual review.

**Notes:**
- Git commands require libgit2 to be installed and discoverable at build time.
- The module name is derived from the repo name (with `zephyr-module-` and `zephyr-` prefixes stripped).
- Install runs a security scan after clone; critical findings block install and warnings require confirmation unless `--unsafe` is used.

### `zephyr scan <source>`

Scans a module source for security findings **without** installing it. This is the recommended entry point for
agent frameworks or CI workflows that need machine-readable security signals.

```bash
# Human-friendly scan report
zephyr scan https://github.com/user/zephyr-git-helpers

# Machine-readable scan report
zephyr scan https://github.com/user/zephyr-git-helpers --json
```

**JSON output (stable schema):**
- `schema_version`: current schema version (string, currently `1.0`)
- `scan_summary`: counts and timing (files, lines, duration, finding counts)
- `findings`: list of findings with severity, file, line, snippet, and bypass hint
- `credential_findings`: detected credential access (type + exfiltration)
- `reverse_shell_findings`: detected reverse shell patterns (type + location)
- `trusted_module_applied`: whether trusted-module relaxations were applied
- `policy_recommendation`: `allow`, `warn`, or `block`
- `exit_code_hint`: `0` (clean), `1` (warnings), `2` (critical)

See [docs/SECURITY_SCAN.md](docs/SECURITY_SCAN.md) for the full schema and exit code contract.

**Exit codes (when `--json` is used):**
- `0`: No findings
- `1`: Warning findings present
- `2`: Critical findings present
- `3`: Scan failed (I/O error, timeout, or other scan error)
- `4`: Invalid arguments

### `zephyr scan "<command>"`

If the argument is **not** a git URL or local path, `zephyr scan` treats it as a command string and returns a **silent** exit code:

```bash
zephyr scan "ls -la"          # exit 0 (safe)
zephyr scan "rm -rf /"        # exit 1 (critical)
zephyr scan "cat ~/.aws/credentials"  # exit 2 (warning)
```

**Exit codes (command mode):**
- `0`: Safe / no findings
- `1`: Critical findings
- `2`: Warning findings

### `zephyr update [module-name]`

Updates modules by fetching and pulling from their origin remotes.

```bash
# Update all modules
zephyr update

# Update a single module
zephyr update git-helpers
```

If a validation check fails after pulling, Zephyr attempts to roll back the module to the previous commit.
Updates also run the security scan; critical findings block the update and warnings require confirmation.

### `zephyr uninstall <module-name>`

Removes an installed module from your modules directory.

```bash
# Uninstall a module
zephyr uninstall git-helpers

# Uninstall with confirmation when dependents are detected
zephyr uninstall git-helpers --confirm
```

For more details on install/update workflows, see `docs/MODULE_INSTALLATION.md`.

### `zephyr init <name>`

Creates a new module skeleton with boilerplate files and helpful suggestions.

```bash
# Create a basic module
zephyr init my-new-module

# With verbose output to see what's being created
zephyr -v init my-new-module
```

**Success output:**
```
✓ Creating new module: my-new-module
Location: /Users/user/.zsh/modules/my-new-module

ℹ Creating module directory: /Users/user/.zsh/modules/my-new-module
ℹ Creating subdirectory: functions
ℹ Creating subdirectory: aliases  
ℹ Creating subdirectory: completions
ℹ Creating module manifest: module.toml
ℹ Creating main script: init.zsh
ℹ Creating example functions: functions/example.zsh
ℹ Creating example aliases: aliases/example.zsh
ℹ Creating documentation: README.md

✓ Module created successfully!

Files created:
   /Users/user/.zsh/modules/my-new-module/
   |-- module.toml          # Module manifest and configuration
   |-- init.zsh            # Main initialization script
   |-- README.md           # Documentation and usage guide
   |-- functions/
   |   `-- example.zsh     # Example shell functions
   |-- aliases/
   |   `-- example.zsh     # Example shell aliases
   `-- completions/        # Directory for shell completions

Next steps:
1. Edit the module manifest:
   vim /Users/user/.zsh/modules/my-new-module/module.toml

2. Customize your module:
   vim /Users/user/.zsh/modules/my-new-module/init.zsh

3. Test your module:
   zephyr validate          # Check for manifest errors
   zephyr list              # See module in load order

✓ Happy coding with your new 'my-new-module' module!
```

**Error output with suggestions:**
```
✗ Invalid module name '123invalid'

Suggested fixes:

  1. Use valid characters only
     Why: Module names can only contain letters, numbers, hyphens, and underscores

  2. Start with a letter
     Why: Module names must begin with a letter (a-z, A-Z)

  3. Keep it under 50 characters
     Why: Module names should be concise and descriptive
```

## Module Development

### Basic Module Structure

A minimal module needs only two files:

```
my-module/
├── module.toml         # Required: module manifest
└── init.zsh           # Required: at least one shell file
```

### Module Manifest (`module.toml`)

#### Minimal Example

```toml
[module]
name = "my-module"
version = "1.0.0"

[load]
files = ["init.zsh"]
```

#### Complete Example

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
pager = "less -R"
```

### Shell Files

Shell files contain your actual ZSH code:

**aliases.zsh:**
```bash
# Git shortcuts
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline'

# Directory shortcuts
alias ..='cd ..'
alias ...='cd ../..'
```

**functions.zsh:**
```bash
# Create and enter directory
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Git commit with message
gcm() {
    git commit -m "$1"
}
```

### Using Dependencies

Modules can depend on other modules:

```toml
[dependencies]
required = ["core"]        # Must be loaded first
optional = ["colors"]      # Load if available
```

**In your shell code:**
```bash
# Check if optional dependency is loaded
if [[ -n "$ZSH_MODULE_COLORS_LOADED" ]]; then
    # Use colors module functionality
    echo "${GREEN}Git helpers loaded!${RESET}"
else
    echo "Git helpers loaded!"
fi
```

### Environment Variables

Modules can export settings as environment variables:

```toml
[settings]
editor = "nvim"
pager = "less -R"
theme = "dark"
```

These become available as:
- `$ZSH_MODULE_MYMODULE_EDITOR`
- `$ZSH_MODULE_MYMODULE_PAGER`
- `$ZSH_MODULE_MYMODULE_THEME`

### Hooks

Use hooks for setup and cleanup:

```toml
[hooks]
pre_load = "setup_git_config"
post_load = "register_completions"
```

**In your shell file:**
```bash
setup_git_config() {
    # Run before module files are sourced
    git config --global core.editor "$ZSH_MODULE_GIT_EDITOR"
}

register_completions() {
    # Run after module files are sourced
    compdef _git gc=git-commit
}
```

## Configuration Reference

### Module Directory

By default, Zephyr looks for modules in `$HOME/.zsh/modules`. You can override this:

```bash
export ZSH_MODULES_DIR="/path/to/my/modules"
```

### Priority System

Modules load in priority order (lower numbers first):

- `1-10`: Core system modules
- `11-50`: Framework and utility modules  
- `51-100`: Application-specific modules
- `101+`: User customizations

### Platform Filtering

Restrict modules to specific platforms:

```toml
[platforms]
os = ["darwin"]              # macOS only
arch = ["x86_64", "arm64"]   # Intel and Apple Silicon
shell = "zsh"                # ZSH only
min_version = "5.8"          # Minimum ZSH version
```

## Examples

### Example 1: Development Environment Module

```toml
# modules/dev-env/module.toml
[module]
name = "dev-env"
version = "1.0.0"
description = "Development environment setup"

[dependencies]
required = ["core"]

[load]
priority = 30
files = ["exports.zsh", "aliases.zsh", "functions.zsh"]

[settings]
editor = "code"
browser = "firefox"
```

```bash
# modules/dev-env/exports.zsh
export EDITOR="$ZSH_MODULE_DEV_ENV_EDITOR"
export BROWSER="$ZSH_MODULE_DEV_ENV_BROWSER"
export PATH="$HOME/.local/bin:$PATH"
```

```bash
# modules/dev-env/aliases.zsh
alias e='$EDITOR'
alias b='$BROWSER'
alias serve='python -m http.server 8000'
```

### Example 2: Git Workflow Module

```toml
# modules/git-flow/module.toml
[module]
name = "git-flow"
version = "2.1.0"
description = "Git workflow helpers"

[dependencies]
required = ["core"]
optional = ["colors"]

[load]
priority = 60
files = ["git-aliases.zsh", "git-functions.zsh"]

[hooks]
post_load = "setup_git_completion"

[settings]
default_branch = "main"
push_default = "simple"
```

```bash
# modules/git-flow/git-functions.zsh
# Create feature branch
gf() {
    local branch_name="feature/$1"
    git checkout -b "$branch_name"
    git push -u origin "$branch_name"
}

# Quick commit and push
gcp() {
    git add .
    git commit -m "$1"
    git push
}

setup_git_completion() {
    # Set up custom completions
    compdef gf=git-checkout
    compdef gcp=git-commit
}
```

### Example 3: macOS-Specific Module

```toml
# modules/macos-utils/module.toml
[module]
name = "macos-utils"
version = "1.0.0"
description = "macOS-specific utilities"

[platforms]
os = ["darwin"]

[load]
priority = 80
files = ["macos-aliases.zsh"]
```

```bash
# modules/macos-utils/macos-aliases.zsh
# macOS specific aliases
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias flushdns='sudo dscacheutil -flushcache'

# Homebrew shortcuts
alias brewup='brew update && brew upgrade'
alias brewclean='brew cleanup && brew doctor'
```

## Debugging and Troubleshooting

Zephyr provides comprehensive debugging and error reporting features to help you diagnose issues with your shell modules.

### Verbose and Debug Output

Use the verbose and debug flags to get detailed information about what Zephyr is doing:

```bash
# Verbose output - shows high-level operations
zephyr -v load
# Output:
# [INFO] Verbose mode enabled
# [INFO] Using modules directory: /Users/user/.zsh/modules
# [INFO] Starting module discovery
# [INFO] Discovered 3 modules
# [INFO] Starting platform filtering
# [INFO] Found 3 compatible modules
# [INFO] Starting dependency resolution
# [INFO] Resolved 3 modules in dependency order

# Debug output - shows detailed internal operations  
zephyr --debug validate
# Output:
# [DEBUG] Debug mode enabled
# [INFO] Processing command: validate
# [DEBUG] Scanning directory: /Users/user/.zsh/modules
# [DEBUG] Found manifest: /Users/user/.zsh/modules/core/module.toml
# [DEBUG] Discovered module: core at /Users/user/.zsh/modules/core
# [INFO] Resolving dependencies for 3 modules
# [INFO] Resolution successful: 3 modules in order

# Maximum verbosity with trace output
zephyr --trace list
# Shows function entry/exit, file operations, and detailed timing
```

### Environment Variables for Debugging

Control debug output through environment variables:

```bash
# Enable debug output (levels 0-3)
export ZEPHYR_DEBUG=2
zephyr load

# Enable verbose output  
export ZEPHYR_VERBOSE=1
zephyr validate

# Show timestamps in debug output
export ZEPHYR_DEBUG_TIMESTAMPS=1
zephyr --debug load
# Output: [1642234567] [DEBUG] Starting module discovery

# Disable colors (useful for logging)
export NO_COLOR=1
zephyr validate
```

### Common Error Scenarios

#### Missing Modules Directory

```bash
$ zephyr load
✗ Modules directory does not exist: /Users/user/.zsh/modules

Suggested fixes:

  1. Create the modules directory
     Command: mkdir -p ~/.zsh/modules
     Why: This creates the default modules directory where Zephyr looks for modules

  2. Set a custom modules directory
     Command: export ZSH_MODULES_DIR=/path/to/your/modules
     Why: Use this if you want to store modules in a different location

  3. Create your first module
     Command: zephyr init my-first-module
     Why: This will create both the directory structure and a sample module
```

#### Invalid Module Manifest

```bash
$ zephyr validate
✗ Invalid manifest
  Error: Missing required 'name' field in [module] section of /path/to/module.toml
  File: /Users/user/.zsh/modules/bad-module/module.toml
  Operation: Manifest validation

Suggested fixes:

  1. Add required fields
     Why: Ensure your module.toml has at least a [module] section with a 'name' field

  2. Use init template
     Command: zephyr init example-module
     Why: Create a new module to see the correct manifest format
```

#### Circular Dependencies

```bash
$ zephyr load
✗ CIRCULAR DEPENDENCY
  Error: Circular dependency detected involving modules: [module-a, module-b]
  Operation: Dependency resolution

Suggested fixes:

  1. Review dependency graph
     Command: zephyr list
     Why: Examine the dependency relationships to identify the cycle

  2. Remove unnecessary dependencies
     Why: Check if any dependencies can be removed or made optional to break the cycle
```

#### Platform Incompatibility

```bash
$ zephyr load
⚠ No compatible modules found for current platform in: /Users/user/.zsh/modules

Suggested fixes:

  1. Check platform filters
     Why: Review the [platforms] section in module.toml files

  2. Remove platform restrictions
     Why: Comment out or remove platform filters if they're too restrictive

  3. Add your platform
     Why: Add your OS/architecture to the platform filters in the module manifest
```

### Performance Debugging

Use debug output to identify performance bottlenecks:

```bash
# Time module operations
zephyr --debug load 2>&1 | grep "took"
# Output:
# [DEBUG] Operation 'module discovery' took 2.3ms
# [DEBUG] Operation 'dependency resolution' took 1.1ms
# [DEBUG] Operation 'shell code generation' took 0.8ms
```

### Colored Output

Zephyr automatically detects terminal color support and provides colored output for better readability:

- ✓ **Green**: Success messages and valid items
- ✗ **Red**: Errors and failures  
- ⚠ **Yellow**: Warnings and skipped items
- ℹ **Blue**: Information and status messages

Disable colors when needed:
```bash
# Disable colors for this command
zephyr --no-color validate

# Disable colors globally
export NO_COLOR=1
```

## Troubleshooting

See the [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for common issues and solutions.

## Performance

Zephyr is designed for minimal startup overhead and efficient module processing. Benchmark results on macOS (Apple Silicon):

### Performance Metrics

| Metric | Value | Requirement |
|--------|-------|-------------|
| **Module Count** | 49 modules | < 50 modules |
| **Average Load Time** | 56ms | < 100ms ✓ |
| **Processing Rate** | 875 modules/sec | - |
| **Min/Max Time** | 43ms / 74ms | - |
| **Memory Management** | Zero leaks | ✓ |

### Key Features

- **Fast Startup**: Sub-100ms load time for typical configurations
- **Efficient Memory**: Zero memory leaks, enterprise-grade cleanup
- **Scalable**: Tested with 45+ modules without performance degradation
- **Optimized**: Batch string building for large module sets (20+ modules)
- **Cached**: Dependency resolution caching for repeated loads

### Running Benchmarks

```bash
# Run standard benchmark (49 modules, 10 cycles)
make benchmark

# Quick validation (25 modules, 5 cycles)
make benchmark-quick

# Test scalability (50, 75, 100 modules)
make benchmark-scale

# Or use the script directly
./benchmark.sh --help
```

**Note:** Performance may vary based on hardware, module complexity, and shell configuration. The benchmarks above represent typical usage on modern hardware.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Testing Your Changes

Before submitting a PR, run the acceptance tests:

```bash
./run-acceptance-tests.sh
```

All acceptance tests must pass for the PR to be accepted.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Odin](https://odin-lang.org/) programming language
- Inspired by modern package managers and module systems
- Thanks to the ZSH community for inspiration
