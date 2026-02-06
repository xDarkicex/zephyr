# Module Installation Guide

This guide explains how to install, update, and remove Zephyr modules using the git-based workflow.

## Requirements

- libgit2 (required for git operations)
- pkg-config (recommended for build-time auto-detection)
- A working git remote or local repository

If you build from source without libgit2 available, git commands will not work. See the README Installation section for platform-specific install commands.

## Install Sources

Zephyr accepts three source formats:

1. HTTPS or SSH git URL
2. GitHub shorthand (`user/repo`)
3. Local path (requires `--local`)

Examples:

```bash
# HTTPS URL
zephyr install https://github.com/user/zephyr-git-helpers

# SSH URL
zephyr install git@github.com:user/zephyr-git-helpers.git

# GitHub shorthand
zephyr install user/zephyr-git-helpers

# Local repo path
zephyr install --local /path/to/module-repo
```

## Module Name Rules

The module name is derived from the repository name:

- The `.git` suffix is removed
- `zephyr-module-` is stripped first (if present)
- `zephyr-` is stripped next (if present)

The final module name must satisfy:

- Lowercase only
- Start with a letter or number
- Allowed characters: `a-z`, `0-9`, `-`, `_`
- Maximum length: 50 characters
- Reserved names are blocked (for example: `core`, `stdlib`, `system`, `kernel`)

If the name is invalid, installation fails with a descriptive error.

## Installation Flow

1. Clone to a temporary directory
2. Validate `module.toml` and load files
3. Move the module into your modules directory
4. Print next steps (`zephyr load`)

A failed validation prevents installation and cleans up the temp directory.

## Update Modules

```bash
# Update all modules
zephyr update

# Update a single module
zephyr update git-helpers
```

After pulling, modules are validated again. If validation fails, Zephyr attempts to roll back to the previous commit.

## Uninstall Modules

```bash
zephyr uninstall git-helpers
```

If dependency checking is enabled and other modules depend on the target, Zephyr will require confirmation:

```bash
zephyr uninstall git-helpers --confirm
```

## Local Path Installs

Local installs are useful for testing modules before publishing. Use `--local` to explicitly allow them:

```bash
zephyr install --local /path/to/module-repo
```

When installing from a local path, Zephyr derives the module name from the module manifest rather than the path.

## Troubleshooting

If installs or updates fail, see:

- `docs/TROUBLESHOOTING.md`
- `SECURITY_SPEC.md` for security considerations
