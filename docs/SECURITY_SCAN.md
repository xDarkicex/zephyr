# Security Scan Output (JSON)

`zephyr scan <source> --json` emits a machine-readable security report to stdout.
This output is designed for agent frameworks and CI tooling. Human-friendly output
is the default when `--json` is not provided.

## Security Isolation During Install

Zephyr uses a **clone-scan-validate-move** pipeline to ensure modules are analyzed
before they can execute:

1. **Clone to temporary directory**: Module is cloned to a temp location outside your modules directory
2. **Security scan**: All files are scanned for dangerous patterns while isolated
3. **Validation**: Manifest and dependencies are validated
4. **Move to final location**: Only if all checks pass, module is moved to `~/.zsh/modules/`

This ensures that:
- Malicious code cannot execute during the scan
- Failed scans leave no artifacts in your modules directory
- Git hooks in the module cannot run until after security approval
- Temporary files are cleaned up on any failure

**Note:** Git hooks in the cloned repository may execute during the clone operation
itself, before the scan runs. This is a limitation of git's design. Always clone
from trusted sources.

## Stability

- The JSON schema is versioned with `schema_version`.
- Fields documented here are stable within the same major version.
- New fields may be added in minor releases; consumers should ignore unknown fields.

## Exit Codes

When `--json` is used, `zephyr scan` exits with a status code that mirrors the
scan outcome:

- `0`: No findings
- `1`: Warning findings present
- `2`: Critical findings present
- `3`: Scan failed (I/O error, timeout, or other scan error)
- `4`: Invalid arguments

Agents can rely on exit codes without parsing JSON for quick policy checks.

## Schema Evolution Policy

- Minor versions (`1.1`, `1.2`, …) may add fields but will not remove or
  change existing fields.
- Major versions (`2.0`, …) may introduce breaking changes.
- Consumers should validate `schema_version` and ignore unknown fields.

## Schema (v1.0)

```json
{
  "schema_version": "1.0",
  "source": {
    "type": "git",
    "url": "https://github.com/user/module.git",
    "commit": "a1b2c3d4e5f67890abcdef0123456789abcdef01"
  },
  "scan_summary": {
    "files_scanned": 12,
    "lines_scanned": 458,
    "duration_ms": 42,
    "critical_findings": 1,
    "warning_findings": 3
  },
  "policy_recommendation": "block",
  "exit_code_hint": 2,
  "findings": [
    {
      "severity": "critical",
      "pattern": "curl\\s+.*\\|\\s*bash",
      "description": "Download and execute via curl",
      "file": "init.zsh",
      "line": 47,
      "snippet": "curl https://example.com/install.sh | bash",
      "bypass_required": "--unsafe"
    }
  ]
}
```

### Field Notes

- `source.commit` is included when the source is a Git repository and the head
  commit can be resolved.
- `pattern` is the regex pattern that matched. It is provided for transparency
  and debugging.
- `snippet` is the trimmed line content where the match occurred.
- `bypass_required` is informational and indicates the explicit flag needed to
  bypass a finding.
