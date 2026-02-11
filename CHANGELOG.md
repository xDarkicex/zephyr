# Changelog

All notable changes to Zephyr will be documented in this file.

## Unreleased

- Added `zephyr update` for module updates with validation, security scan, and rollback.
- Added `zephyr upgrade` for self-upgrade via GitHub releases with checksum verification.
- Added command-mode scanning via `zephyr scan "<command>"` with exit-code semantics.
- Implemented git hook mitigation (clone without checkout → scan → validate → checkout).
- Expanded security scanning (credentials, reverse shells, CI/CD configs, pattern coupling).
- Added agent roles, session/audit logging, and SIEM-ready NDJSON logs.
- Added signed module verification and release tarball installation path.
- Added HTTP client plumbing for release discovery/downloads.
- Enhanced `--version` output with ASCII art branding and build metadata.
- Added short `-v` version output and updated help/README usage guidance.
- Embedded build metadata at compile time (version, git commit, build time).
- Improved shell detection on Linux (container-safe) and updated default modules directory to `~/.zephyr/modules` in docs/output.
- Added README examples and ASCII “screenshot” for version output.
