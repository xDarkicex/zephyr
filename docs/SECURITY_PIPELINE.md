# Security Pipeline

## Overview

Zephyr protects installs with a **clone-scan-validate-move** pipeline. Modules are cloned into a temporary directory first, scanned and validated there, and only moved into the modules directory if they pass.

This keeps untrusted code out of your live modules directory and ensures failed scans leave no artifacts.

## Pipeline Steps

1. **Clone to temp**
Zephyr clones the repository into a temporary directory outside the modules path.

2. **Scan**
Zephyr scans all text files for critical and warning patterns. Binary files and oversized files are skipped with warnings. The scan runs in the temporary directory.

3. **Git hooks check**
Zephyr inspects `.git/hooks/` inside the temporary clone. Any non-sample hook file is treated as a critical finding. By default, the install is blocked unless `--unsafe` is provided.

4. **Validate**
Manifest and dependency validation are performed before any files are moved into the modules directory.

5. **Move to final location**
Only after a clean scan and successful validation does Zephyr move the module into `~/.zsh/modules/`.

## Git Hooks Blocking

Git hooks are scripts located in `.git/hooks/` that can execute during git operations. Zephyr detects hooks in a cloned module and blocks installation by default.

If you explicitly trust the module and want to proceed anyway, you can use `--unsafe`, which will override the block and record an audit entry.

## Security Notes

- Zephyr does not sandbox module execution at runtime. Approved modules still execute with your user privileges.
- The pipeline is designed to keep untrusted code isolated during the scan stage and prevent accidental persistence when a scan fails.
- For agent usage, treat security scans as signals rather than guarantees and restrict the use of `--unsafe`.
