# Agent Roles & Session Management

Zephyr provides an IAM-like role system for AI agents and humans. It detects agent context, registers sessions on shell load, enforces permissions, and writes audit logs for compliance.

## Role Model

Default roles (from `~/.zephyr/security.toml`):
- `user`: full permissions
- `agent`: restricted permissions
- `admin`: full permissions for automation/CI

Permissions controlled by role:
- Install
- Install Unsigned
- Use `--unsafe`
- Uninstall
- Modify Config
- Require Confirmation

## How Sessions Are Created

`zephyr load` emits a small shell block that:
- Detects agent type from environment variables
- Determines agent ID
- Sets `ZEPHYR_AGENT_ID`, `ZEPHYR_AGENT_TYPE`, `ZEPHYR_SESSION_ID`
- Calls `zephyr register-session` to record the session

If `zephyr` is not on `PATH`, the load script uses the absolute path of the binary that generated it.

## CLI Commands

View current session:
```bash
zephyr session
```

List recent sessions:
```bash
zephyr sessions
```

Review audit logs:
```bash
zephyr audit --type=operations
zephyr audit --type=commands --since=2026-02-10
zephyr audit --type=sessions --agent=agent-5
```

Register a session manually:
```bash
zephyr register-session --agent-id=agent-1 --agent-type=cursor --session-id=abc123 --parent=zsh
```

## Security Model & Bypass Risks

Zephyr provides **enforcement and auditability**, not a hard security boundary.

Bypass risks to be aware of:
- Agents can spoof environment variables or call `register-session` directly.
- Agents can re-exec commands with `--unsafe` if their role allows it.
- Shell execution is not sandboxed; approved code runs with user privileges.

Recommended controls:
- Only allow trusted agents to run with `user` or `admin` roles.
- Keep `agent` role restrictive in `security.toml`.
- Review audit logs for anomalies.
- Combine with signed modules and security scanning.

## Privacy & Data Collection

Zephyr audit logs include:
- `agent_id`, `agent_type`, `session_id`, `role`
- `timestamp` and `@timestamp`
- `event_action`, `event_outcome`, `event_category`
- Operation details like `module`, `source`, and `signature_verified`

Zephyr does **not** log:
- Command arguments
- File contents
- API keys or secrets

Retention:
- Audit logs are pruned by date via `cleanup_old_audit_logs` (default 30 days).

## Troubleshooting

No active session:
- Ensure you are using `eval "$(zephyr load)"` in your shell.
- Verify `zephyr` is on `PATH` or regenerate the load script after moving the binary.

Audit logs not writing:
- Check permissions on `~/.zephyr/audit/`.
- On macOS, clear extended attributes if needed:
```bash
xattr -c ~/.zephyr ~/.zephyr/audit ~/.zephyr/audit/operations
```

Agent detected incorrectly:
- Clear any leftover agent env vars before testing.
- Example:
```bash
unset ANTHROPIC_API_KEY ANTHROPIC_AGENT_ID CURSOR_AGENT_ID GITHUB_COPILOT_SESSION TERM_PROGRAM
```

## Related Docs

- [SECURITY_AUDIT.md](SECURITY_AUDIT.md)
- [SECURITY.md](SECURITY.md)
