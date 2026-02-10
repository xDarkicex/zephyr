# Security Audit Logs & SIEM Integration

Zephyr writes **append‑only JSON Lines (NDJSON)** audit logs under:

```
~/.zephyr/audit/
  sessions/                         # Session registrations
  commands/YYYY-MM-DD/<session>.log # Command scan events
  operations/YYYY-MM-DD/operations.log
```

Each line is a single JSON object suitable for SIEM ingestion.

## Schema (Stable Fields)

All events include:

- `schema_version` — audit schema version (currently `"1.0"`)
- `@timestamp` — RFC3339 timestamp (UTC)
- `timestamp` — same as `@timestamp` (human‑friendly field)
- `agent_id`, `agent_type`, `session_id`, `role`
- `event_action`, `event_outcome`, `event_category`

Event‑specific fields:

- **session**: `parent_process`, `started_at`
- **command_scan**: `command`, `exit_code`, `reason`
- **operations**: `action`, `module`, `source`, `signature_verified`, `reason`

### Example (operation)

```json
{"schema_version":"1.0","@timestamp":"2026-02-10T21:56:07Z","timestamp":"2026-02-10T21:56:07Z","session_id":"session-5","agent_id":"agent-5","agent_type":"cursor","user_name":"z3robit","host_name":"macbook","role":"agent","action":"install","module":"demo-module","source":"local-test","result":"blocked","reason":"test-seed","event_action":"install","event_outcome":"blocked","event_category":"package","signature_verified":false}
```

## SIEM Notes

This format is compatible with:

- **Wazuh** (JSON decoder + file monitoring)
- **ELK/Elastic** (Filebeat/Logstash JSON input)
- **OpenSearch Security Analytics** (JSON/ECS‑like mapping)

**Recommended ingestion:** watch `~/.zephyr/audit/**` with your log shipper, and parse as JSON.

## ECS Mapping Guidance (Optional)

If you use Elastic Common Schema (ECS), you can map:

- `@timestamp` → `@timestamp`
- `agent_id` → `agent.id`
- `agent_type` → `agent.type`
- `session_id` → `session.id`
- `event_action` → `event.action`
- `event_outcome` → `event.outcome`
- `event_category` → `event.category`
- `user_name` → `user.name`
- `host_name` → `host.name`

## Retention

Audit logs are pruned by date via `cleanup_old_audit_logs` (default retention: 30 days). Adjust retention in code or via your log shipper.

## macOS Notes (Extended Attributes)

Some macOS setups apply `com.apple.provenance` extended attributes to newly created
directories, which can block writes to `~/.zephyr/audit/**` with “Operation not permitted”.
If you see that error, clear the xattr once:

```bash
xattr -c ~/.zephyr ~/.zephyr/audit ~/.zephyr/audit/operations
```
