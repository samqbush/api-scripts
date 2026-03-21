# Copilot CLI Session Audit Hooks

Automatically capture and upload Copilot CLI session data for auditing and compliance when a session ends.

## How It Works

GitHub Copilot CLI stores all session data locally in `~/.copilot/session-store.db` (SQLite). These hooks tap into the CLI's [hook system](https://docs.github.com/en/copilot/reference/hooks-configuration) to extract and ship that data to a log aggregator on session end.

```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────────┐
│  Copilot CLI  │────▶│  sessionEnd hook   │────▶│  Audit Destination  │
│  session ends │     │  (hooks.json)      │     │  (file/http/dd/...)  │
└──────────────┘     └───────────────────┘     └─────────────────────┘
                            │
                            ▼
                     ┌───────────────────┐
                     │  session-store.db  │
                     │  (local SQLite)    │
                     └───────────────────┘
```

## Quick Start

### 1. Copy the hooks into your repo

```bash
# From your repository root
mkdir -p .github/hooks
cp hooks.json .github/hooks/
cp upload-session-audit.sh .github/hooks/
chmod +x .github/hooks/upload-session-audit.sh
```

### 2. Set your destination

```bash
# Default: writes JSON files to ~/.copilot/audit-logs/
export COPILOT_AUDIT_DEST="file"

# Or ship to Datadog, Splunk, S3, or any HTTP endpoint (see below)
```

### 3. That's it

Every Copilot CLI session will now be automatically captured when it ends.

## Prerequisites

- **`sqlite3`** — for reading the session store
- **`jq`** — for JSON processing
- **`curl`** — for HTTP-based destinations
- **`aws`** — only for the S3 destination

## Supported Destinations

Configure via the `COPILOT_AUDIT_DEST` environment variable:

### Local File (default)

Writes each session as a standalone JSON file. Good for development or as a starting point.

```bash
export COPILOT_AUDIT_DEST="file"
export COPILOT_AUDIT_DIR="$HOME/.copilot/audit-logs"  # optional, this is the default
```

Output: `~/.copilot/audit-logs/session-<uuid>.json`

### HTTP Webhook

POST the payload to any REST endpoint — works with custom compliance APIs, Azure Monitor ingestion, etc.

```bash
export COPILOT_AUDIT_DEST="http"
export COPILOT_AUDIT_URL="https://your-api.example.com/v1/audit"
export COPILOT_AUDIT_AUTH_HEADER="Bearer your-token"  # optional
```

### Datadog

Send to [Datadog Logs](https://docs.datadoghq.com/logs/).

```bash
export COPILOT_AUDIT_DEST="datadog"
export DD_API_KEY="your-datadog-api-key"
export DD_SITE="datadoghq.com"  # optional, default shown
export DD_ENV="production"       # optional, tagged as env:production
```

Search in Datadog: `source:copilot-cli service:copilot-cli`

### Splunk

Send to [Splunk HTTP Event Collector](https://docs.splunk.com/Documentation/Splunk/latest/Data/UsetheHTTPEventCollector).

```bash
export COPILOT_AUDIT_DEST="splunk"
export SPLUNK_HEC_URL="https://your-splunk:8088/services/collector/event"
export SPLUNK_HEC_TOKEN="your-hec-token"
```

Search in Splunk: `sourcetype="copilot:session"`

### AWS S3

Upload JSON files to an S3 bucket (requires [AWS CLI](https://aws.amazon.com/cli/) with configured credentials).

```bash
export COPILOT_AUDIT_DEST="s3"
export COPILOT_AUDIT_S3_BUCKET="my-audit-bucket"
export COPILOT_AUDIT_S3_PREFIX="copilot-audit"  # optional, default shown
```

Files organized by date: `s3://bucket/copilot-audit/2026/03/21/session-<uuid>.json`

## Audit Payload

Every captured session produces this JSON structure:

```json
{
  "schemaVersion": "1.0",
  "sessionId": "90856c5e-c613-4756-af20-1810695bb70c",
  "repository": "octocat/my-project",
  "branch": "main",
  "cwd": "/Users/dev/my-project",
  "user": "octocat",
  "hostType": "cli",
  "summary": "Implemented authentication middleware",
  "startedAt": "2026-03-21T10:00:00.000Z",
  "endedAt": "2026-03-21T10:45:00.000Z",
  "endReason": "complete",
  "turnCount": 8,
  "turns": [
    {
      "turn_index": 0,
      "user_message": "Help me add JWT auth",
      "assistant_response": "I'll help you set up...",
      "timestamp": "2026-03-21T10:00:05.000Z"
    }
  ],
  "checkpoints": [
    {
      "checkpoint_number": 1,
      "title": "Initial setup",
      "overview": "Created auth middleware and tests"
    }
  ]
}
```

| Field | Description |
|---|---|
| `schemaVersion` | Payload format version (`"1.0"`) |
| `sessionId` | UUID of the Copilot CLI session |
| `repository` | GitHub repository (owner/name) |
| `branch` | Git branch active during session |
| `user` | OS username (`$USER`) |
| `summary` | AI-generated session summary |
| `endReason` | `complete`, `error`, `abort`, `timeout`, or `user_exit` |
| `turns` | Full user/assistant conversation history |
| `checkpoints` | Session checkpoints (title + overview) |

## Available Hook Events

The `hooks.json` in this example uses three events, but Copilot CLI supports six:

| Event | When It Fires | Can Block? |
|---|---|---|
| `sessionStart` | New or resumed session | No |
| `userPromptSubmitted` | User submits a prompt | No |
| `preToolUse` | Before tool execution | **Yes** — can deny |
| `postToolUse` | After tool execution | No |
| `errorOccurred` | On agent error | No |
| `sessionEnd` | Session completes/ends | No |

See the [Hooks Configuration Reference](https://docs.github.com/en/copilot/reference/hooks-configuration) for full details on input/output schemas.

## Security Considerations

1. **Credentials** — Never hard-code API keys. Use environment variables, 1Password CLI, AWS Secrets Manager, or HashiCorp Vault.
2. **Sensitive data** — Session turns may contain code, file contents, or error messages. Restrict access to your audit destination and consider data retention policies.
3. **Network** — HTTP destinations use a 30-second timeout to avoid blocking the developer.
4. **Local data** — The session data already exists locally in `~/.copilot/session-store.db`. These hooks add *transport*, not new data collection.

## Customization

The upload script is intentionally straightforward Bash. Common customizations:

- **Add redaction**: Pipe the payload through a sanitization step before upload
- **Add metadata**: Include team name, cost center, or environment tags
- **Filter sessions**: Skip short sessions (e.g., `turnCount < 2`)
- **Change format**: Convert to CSV, Parquet, or your org's preferred format

## Troubleshooting

| Error | Fix |
|---|---|
| `'sqlite3' not found` | `brew install sqlite3` (macOS) or `sudo apt install sqlite3` (Linux) |
| `'jq' not found` | `brew install jq` (macOS) or `sudo apt install jq` (Linux) |
| `session store not found` | Run at least one Copilot CLI session first |
| `Unknown COPILOT_AUDIT_DEST` | Set to one of: `file`, `http`, `datadog`, `splunk`, `s3` |
| HTTP uploads failing | Check URL reachability and auth token validity |

## References

- [About Copilot CLI Hooks](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-hooks)
- [Hooks Configuration Reference](https://docs.github.com/en/copilot/reference/hooks-configuration)
- [Using Hooks with Copilot CLI (Tutorial)](https://docs.github.com/en/copilot/tutorials/copilot-cli-hooks)
