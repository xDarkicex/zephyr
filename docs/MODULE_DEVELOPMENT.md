# Module Development Best Practices

This guide provides best practices, conventions, and patterns for developing high-quality Zephyr shell modules.

## Table of Contents

- [Module Design Principles](#module-design-principles)
- [Project Structure](#project-structure)
- [Naming Conventions](#naming-conventions)
- [Configuration Best Practices](#configuration-best-practices)
- [Shell Code Guidelines](#shell-code-guidelines)
- [Dependency Management](#dependency-management)
- [Testing and Validation](#testing-and-validation)
- [Documentation Standards](#documentation-standards)
- [Performance Considerations](#performance-considerations)
- [Security Guidelines](#security-guidelines)
- [Distribution and Sharing](#distribution-and-sharing)
- [Signed Modules](#signed-modules)

## Module Design Principles

### Single Responsibility Principle

Each module should have a single, well-defined purpose:

**Good:**
```
git-helpers/     # Git-specific utilities
docker-tools/    # Docker-specific utilities
dev-env/         # Development environment setup
```

**Bad:**
```
utils/           # Too generic, unclear purpose
everything/      # Multiple unrelated functions
```

### Composability

Design modules to work well together:

```toml
# Base functionality
[module]
name = "core"

# Builds on core
[module]
name = "colors"
[dependencies]
required = ["core"]

# Uses both core and colors
[module]
name = "git-helpers"
[dependencies]
required = ["core", "colors"]
```

### Minimal Dependencies

Keep dependencies minimal and well-justified:

```toml
# Good - only essential dependencies
[dependencies]
required = ["core"]
optional = ["colors"]

# Bad - unnecessary dependencies
[dependencies]
required = ["core", "colors", "utils", "themes", "fonts"]
```

### Graceful Degradation

Handle missing optional dependencies gracefully:

```bash
# Check for optional dependency
if [[ -n "$ZSH_MODULE_COLORS_LOADED" ]]; then
    echo "${GREEN}Success!${RESET}"
else
    echo "Success!"
fi
```

## Project Structure

### Standard Directory Layout

```
my-module/
├── module.toml          # Required: Module manifest
├── README.md            # Recommended: Module documentation
├── init.zsh            # Main initialization file
├── aliases.zsh         # Shell aliases
├── functions.zsh       # Shell functions
├── completions.zsh     # Tab completions
├── exports.zsh         # Environment variables
├── config/             # Optional: Configuration files
│   ├── defaults.conf
│   └── templates/
├── lib/                # Optional: Library functions
│   ├── utils.zsh
│   └── helpers.zsh
└── tests/              # Optional: Test files
    ├── test-aliases.zsh
    └── test-functions.zsh
```

### File Organization Patterns

**By Function Type:**
```
module/
├── aliases.zsh         # All aliases
├── functions.zsh       # All functions
└── completions.zsh     # All completions
```

**By Feature Area:**
```
git-module/
├── git-aliases.zsh     # Git aliases
├── git-functions.zsh   # Git functions
├── git-completions.zsh # Git completions
└── github-api.zsh      # GitHub-specific features
```

**Hybrid Approach:**
```
dev-env/
├── init.zsh           # Main initialization
├── exports.zsh        # Environment variables
├── tools/             # Tool-specific features
│   ├── git.zsh
│   ├── docker.zsh
│   └── node.zsh
└── lib/               # Shared utilities
    └── common.zsh
```

## Naming Conventions

### Module Names

Use kebab-case for module names:

```bash
# Good
git-helpers
docker-tools
dev-environment
my-custom-theme

# Bad
gitHelpers
docker_tools
DevEnvironment
my.custom.theme
```

### File Names

Use descriptive, kebab-case or snake_case names:

```bash
# Good
git-aliases.zsh
docker-functions.zsh
completion-helpers.zsh
theme-config.zsh

# Bad
ga.zsh
d.zsh
comp.zsh
tc.zsh
```

### Function Names

Use clear, descriptive names with consistent prefixes:

```bash
# Good - with module prefix
git_quick_commit()
git_branch_cleanup()
docker_container_logs()

# Good - without prefix if module scope is clear
quick_commit()    # In git-helpers module
branch_cleanup()  # In git-helpers module

# Bad - unclear or inconsistent
gc()
qc()
cleanup()  # Too generic
```

### Alias Names

Keep aliases short but memorable:

```bash
# Good - clear abbreviations
alias gs='git status'
alias gd='git diff'
alias ll='ls -la'

# Good - mnemonic patterns
alias ..='cd ..'
alias ...='cd ../..'

# Bad - cryptic or confusing
alias x='git status'
alias q='ls -la'
alias z='cd ..'
```

## Configuration Best Practices

### Module Manifest Structure

Use consistent structure and comprehensive metadata:

```toml
[module]
name = "git-helpers"
version = "1.2.0"
description = "Git workflow utilities and shortcuts"
author = "Your Name <your.email@example.com>"
license = "MIT"

[dependencies]
required = ["core"]
optional = ["colors", "fzf-integration"]

[platforms]
os = ["linux", "darwin"]
shell = "zsh"
min_version = "5.8"

[load]
priority = 50
files = [
    "git-aliases.zsh",
    "git-functions.zsh",
    "git-completions.zsh"
]

[hooks]
pre_load = "git_check_requirements"
post_load = "git_setup_completions"

[settings]
default_branch = "main"
auto_fetch = "false"
editor = "vim"
```

### Priority Guidelines

Use consistent priority ranges:

```toml
# System and core modules
[load]
priority = 1-10

# Framework and utility modules
[load]
priority = 11-50

# Application-specific modules
[load]
priority = 51-100

# User customizations and themes
[load]
priority = 101-200
```

### Settings Design

Design settings to be intuitive and well-documented:

```toml
[settings]
# Use clear, descriptive names
default_branch = "main"          # Not: db = "main"
auto_fetch = "true"              # Not: af = "1"
editor = "code"                  # Not: ed = "code"

# Provide sensible defaults
timeout = "30"
max_results = "100"
theme = "default"
```

## Shell Code Guidelines

### Code Organization

Structure shell code for readability and maintainability:

```bash
#!/usr/bin/env zsh
# git-helpers: Git workflow utilities
# Version: 1.2.0

# =============================================================================
# Configuration and Setup
# =============================================================================

# Module settings
GIT_DEFAULT_BRANCH="${ZSH_MODULE_GIT_HELPERS_DEFAULT_BRANCH:-main}"
GIT_AUTO_FETCH="${ZSH_MODULE_GIT_HELPERS_AUTO_FETCH:-false}"

# =============================================================================
# Utility Functions
# =============================================================================

# Check if we're in a git repository
_git_is_repo() {
    git rev-parse --git-dir >/dev/null 2>&1
}

# Get current branch name
_git_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null
}

# =============================================================================
# Public Functions
# =============================================================================

# Quick commit with message
git_quick_commit() {
    local message="$1"
    if [[ -z "$message" ]]; then
        echo "Usage: git_quick_commit <message>"
        return 1
    fi
    
    git add . && git commit -m "$message"
}

# =============================================================================
# Aliases
# =============================================================================

alias gs='git status'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'

# =============================================================================
# Initialization
# =============================================================================

# Mark module as loaded
export ZSH_MODULE_GIT_HELPERS_LOADED=1
```

### Error Handling

Implement robust error handling:

```bash
# Check prerequisites
git_quick_push() {
    # Check if in git repo
    if ! _git_is_repo; then
        echo "Error: Not in a git repository" >&2
        return 1
    fi
    
    # Check if remote exists
    if ! git remote get-url origin >/dev/null 2>&1; then
        echo "Error: No remote 'origin' configured" >&2
        return 1
    fi
    
    # Perform operation with error checking
    if ! git push origin "$(_git_current_branch)"; then
        echo "Error: Failed to push to remote" >&2
        return 1
    fi
    
    echo "Successfully pushed to origin"
}
```

### Performance Optimization

Write efficient shell code:

```bash
# Good - cache expensive operations
_git_branch_cache=""
_git_branch_cache_time=0

git_current_branch() {
    local current_time=$(date +%s)
    
    # Cache for 5 seconds
    if [[ $((current_time - _git_branch_cache_time)) -gt 5 ]]; then
        _git_branch_cache=$(git symbolic-ref --short HEAD 2>/dev/null)
        _git_branch_cache_time=$current_time
    fi
    
    echo "$_git_branch_cache"
}

# Good - avoid subshells when possible
files=($(git diff --name-only))  # Creates subshell
git diff --name-only | while read file; do  # More efficient for large outputs
    echo "Processing: $file"
done
```

### Variable Scoping

Use proper variable scoping:

```bash
# Good - use local variables in functions
process_files() {
    local file_pattern="$1"
    local output_dir="$2"
    local temp_file
    
    temp_file=$(mktemp)
    # ... process files
    rm "$temp_file"
}

# Good - use readonly for constants
readonly MODULE_VERSION="1.2.0"
readonly MODULE_NAME="git-helpers"

# Bad - global variables in functions
process_files() {
    file_pattern="$1"  # Pollutes global namespace
    output_dir="$2"    # Could conflict with other modules
}
```

## Dependency Management

### Declaring Dependencies

Be explicit about dependencies:

```toml
[dependencies]
# Required - module won't work without these
required = ["core"]

# Optional - enhances functionality if available
optional = ["colors", "fzf-integration"]
```

### Checking Dependencies

Check for dependencies in shell code:

```bash
# Check for required dependency
if [[ -z "$ZSH_MODULE_CORE_LOADED" ]]; then
    echo "Error: git-helpers requires 'core' module" >&2
    return 1
fi

# Check for optional dependency
if [[ -n "$ZSH_MODULE_COLORS_LOADED" ]]; then
    # Use colors if available
    success_color="$GREEN"
    error_color="$RED"
    reset_color="$RESET"
else
    # Fallback without colors
    success_color=""
    error_color=""
    reset_color=""
fi
```

### Avoiding Circular Dependencies

Design module hierarchy to avoid cycles:

```
# Good - hierarchical dependencies
core
├── colors (depends on core)
├── utils (depends on core)
└── git-helpers (depends on core, colors)

# Bad - circular dependencies
module-a (depends on module-b)
└── module-b (depends on module-a)  # Creates cycle
```

## Testing and Validation

### Module Testing

Create comprehensive tests for your modules:

```bash
# tests/test-git-functions.zsh
#!/usr/bin/env zsh

# Test setup
setup_test_repo() {
    local test_dir=$(mktemp -d)
    cd "$test_dir"
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > test.txt
    git add test.txt
    git commit -m "Initial commit"
}

# Test git_quick_commit function
test_git_quick_commit() {
    setup_test_repo
    
    echo "new content" >> test.txt
    git_quick_commit "Test commit"
    
    # Verify commit was created
    local last_commit=$(git log -1 --pretty=format:"%s")
    if [[ "$last_commit" == "Test commit" ]]; then
        echo "✓ git_quick_commit test passed"
    else
        echo "✗ git_quick_commit test failed"
        return 1
    fi
}

# Run tests
test_git_quick_commit
```

### Validation Checklist

Before releasing a module:

- [ ] `zephyr validate` passes without errors
- [ ] All declared files exist and are readable
- [ ] Functions work with and without dependencies
- [ ] No global variable pollution
- [ ] Error handling works correctly
- [ ] Performance is acceptable
- [ ] Documentation is complete

### Continuous Integration

Set up automated testing:

```bash
#!/bin/bash
# .github/workflows/test-modules.yml equivalent

# Install zephyr
git clone https://github.com/zephyr-systems/zephyr.git
cd zephyr && ./install.sh

# Test module validation
zephyr validate

# Test module loading
eval "$(zephyr load)"

# Run module-specific tests
for test_file in tests/*.zsh; do
    echo "Running $test_file"
    zsh "$test_file"
done
```

## Documentation Standards

### Module README Template

```markdown
# Module Name

Brief description of what the module does.

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

This module is automatically discovered by Zephyr when placed in your modules directory.

## Dependencies

- **Required**: core
- **Optional**: colors, fzf-integration

## Configuration

Available settings in `module.toml`:

```toml
[settings]
setting1 = "default_value"  # Description of setting1
setting2 = "true"           # Description of setting2
```

## Usage

### Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `gs` | `git status` | Show git status |
| `gd` | `git diff` | Show git diff |

### Functions

#### `function_name()`

Description of what the function does.

**Usage:**
```bash
function_name arg1 arg2
```

**Examples:**
```bash
function_name "example" "usage"
```

## Troubleshooting

Common issues and solutions.

## License

MIT License
```

### Inline Documentation

Document shell code thoroughly:

```bash
# =============================================================================
# Git Branch Management Functions
# =============================================================================

# Create and switch to a new feature branch
# Usage: git_feature_branch <branch-name>
# Example: git_feature_branch "add-user-auth"
git_feature_branch() {
    local branch_name="$1"
    
    # Validate input
    if [[ -z "$branch_name" ]]; then
        echo "Usage: git_feature_branch <branch-name>" >&2
        return 1
    fi
    
    # Create and switch to branch
    git checkout -b "feature/$branch_name"
}
```

## Performance Considerations

### Startup Performance

Minimize shell startup time:

```bash
# Good - lazy loading
git_advanced_function() {
    # Load heavy dependencies only when needed
    if [[ -z "$_git_advanced_loaded" ]]; then
        source "${0:A:h}/lib/advanced-git.zsh"
        _git_advanced_loaded=1
    fi
    
    _git_advanced_function_impl "$@"
}

# Good - conditional loading
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
    # Only load VS Code specific functions in VS Code
    source "${0:A:h}/vscode-integration.zsh"
fi
```

### Memory Usage

Manage memory efficiently:

```bash
# Good - clean up temporary variables
process_large_dataset() {
    local temp_array=()
    local i
    
    # Process data
    for i in {1..1000}; do
        temp_array+=("item_$i")
    done
    
    # Use data
    echo "Processed ${#temp_array[@]} items"
    
    # Clean up
    unset temp_array
}

# Good - use appropriate data structures
# For large datasets, consider external tools instead of shell arrays
process_files() {
    find . -name "*.txt" | while read -r file; do
        process_file "$file"
    done
}
```

### Caching Strategies

Implement intelligent caching:

```bash
# Cache expensive git operations
_git_status_cache=""
_git_status_cache_time=0
_git_status_cache_pwd=""

git_cached_status() {
    local current_time=$(date +%s)
    local current_pwd="$PWD"
    
    # Invalidate cache if directory changed or cache is old
    if [[ "$current_pwd" != "$_git_status_cache_pwd" ]] || 
       [[ $((current_time - _git_status_cache_time)) -gt 5 ]]; then
        _git_status_cache=$(git status --porcelain 2>/dev/null)
        _git_status_cache_time=$current_time
        _git_status_cache_pwd="$current_pwd"
    fi
    
    echo "$_git_status_cache"
}
```

## Security Guidelines

### Input Validation

Always validate user input:

```bash
# Good - validate and sanitize input
git_commit_with_message() {
    local message="$1"
    
    # Validate input
    if [[ -z "$message" ]]; then
        echo "Error: Commit message required" >&2
        return 1
    fi
    
    # Sanitize input (remove dangerous characters)
    message="${message//[;&|]/}"
    
    # Use safely
    git commit -m "$message"
}

# Bad - direct use of user input
git_commit_with_message() {
    git commit -m "$1"  # Dangerous - could contain shell metacharacters
}
```

### File Operations

Handle file operations securely:

```bash
# Good - validate file paths
process_config_file() {
    local config_file="$1"
    
    # Validate file path
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found: $config_file" >&2
        return 1
    fi
    
    # Check if file is readable
    if [[ ! -r "$config_file" ]]; then
        echo "Error: Config file not readable: $config_file" >&2
        return 1
    fi
    
    # Process safely
    while IFS= read -r line; do
        process_config_line "$line"
    done < "$config_file"
}
```

### Environment Variables

Handle environment variables safely:

```bash
# Good - provide defaults and validate
get_editor() {
    local editor="${ZSH_MODULE_MYMODULE_EDITOR:-${EDITOR:-vim}}"
    
    # Validate editor exists
    if ! command -v "$editor" >/dev/null 2>&1; then
        echo "Warning: Editor '$editor' not found, using vim" >&2
        editor="vim"
    fi
    
    echo "$editor"
}
```

## Distribution and Sharing

### Module Packaging

Structure modules for easy distribution:

```
my-module/
├── module.toml          # Complete manifest
├── README.md            # Comprehensive documentation
├── LICENSE              # License file
├── CHANGELOG.md         # Version history
├── install.sh           # Optional installation script
└── src/                 # Source files
    ├── aliases.zsh
    ├── functions.zsh
    └── completions.zsh
```

### Version Management

Follow semantic versioning:

```toml
[module]
version = "1.2.3"  # MAJOR.MINOR.PATCH

# MAJOR: Breaking changes
# MINOR: New features, backward compatible
# PATCH: Bug fixes, backward compatible
```

### Release Process

1. **Update version** in `module.toml`
2. **Update CHANGELOG.md** with changes
3. **Test thoroughly** with `zephyr validate`
4. **Tag release** in version control
5. **Update documentation** if needed

### Sharing Guidelines

When sharing modules:

- Use clear, descriptive names
- Provide comprehensive documentation
- Include usage examples
- Test on multiple platforms
- Respond to user feedback
- Maintain backward compatibility when possible

This guide provides a foundation for creating high-quality, maintainable Zephyr modules that integrate well with the ecosystem and provide value to users.

## Signed Modules

First-party Zephyr modules can be distributed as **signed tarballs** for stronger
integrity guarantees. Signed modules are verified with OpenSSL during installation
and may be trusted to perform privileged actions.

### Signing a Release Tarball

1. Create a tarball:
   ```bash
   tar -czf my-module-v1.0.0.tar.gz my-module/
   ```

2. Sign and hash:
   ```bash
   export ZEPHYR_SIGNING_KEY=/path/to/private_key.pem
   ./scripts/sign-module.sh my-module-v1.0.0.tar.gz
   ```

3. Publish the `.tar.gz`, `.tar.gz.sig`, and `.tar.gz.sha256` assets in your release.

### Verification

Users can verify a signed module locally:

```bash
zephyr verify /path/to/module-or-tarball
```

### Notes

- Signed modules are intended for **first-party** or **official** modules.
- If signature or hash verification fails, installation is blocked.
- Keep private signing keys offline and backed up securely.
