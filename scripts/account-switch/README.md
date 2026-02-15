# Account Switch

Credential rotation for Claude Code. Manages multiple Claude accounts via macOS Keychain, with automatic rotation on rate limits.

## How It Works

Three components work together:

1. **`account-switch.sh`** — Saves/switches/rotates Keychain credentials between profiles
2. **`stop-notify.sh` (Stop hook)** — Detects rate limits in conversation JSONL, triggers rotation
3. **`run.sh`** — Snapshots `CLAUDE_ACCOUNT` env var at launch for race condition prevention

### Automatic Flow

```
Agent hits rate limit
  → Claude stops (Stop hook fires)
  → stop-notify.sh tails JSONL for "rate_limit" patterns
  → Calls account-switch.sh rotate (round-robin)
  → Triggers fleet.sh restart-all (all panes get new credentials)
```

### Race Condition Prevention

In a multi-pane fleet, all panes may hit the same rate limit simultaneously. Without coordination, every pane would rotate — cycling past the good account.

**Solution**: `run.sh` snapshots the active account into `CLAUDE_ACCOUNT` at launch. When `rotate` runs, it compares `CLAUDE_ACCOUNT` to the current active account. If they differ, another pane already rotated — this pane skips.

## Adding a New Account

```bash
# 1. Log in with the new account
claude login

# 2. Save the credentials as a named profile
engine account-switch save user@gmail.com

# 3. Log in with another account and save it too
claude login   # (log in as second account)
engine account-switch save other@gmail.com
```

You need at least 2 saved accounts for rotation to work.

## Commands

```bash
engine account-switch save [email]       # Save current Keychain creds as a profile
engine account-switch switch <email>     # Switch to a saved profile
engine account-switch rotate             # Rotate to next account (round-robin)
engine account-switch list               # List saved profiles (* = active)
engine account-switch status             # Show current state + rotation count
engine account-switch remove <email>     # Remove a saved profile
```

## Storage

```
~/.claude/accounts/
├── state.json              # Active account, rotation count, account order
└── profiles/
    ├── user@gmail.com.json       # Saved credentials + metadata
    └── other@gmail.com.json
```

Credentials are stored as JSON snapshots of the Keychain entry. The active credentials always live in macOS Keychain under the `Claude Code-credentials` service — profiles are backups that get swapped in.

## When Does It Act?

The system is **passive** — it only acts when Claude's Stop hook fires (agent finishes a turn). It does not poll or run in the background.

Rate limit detection checks the last 50 lines of the current conversation JSONL for patterns: `rate_limit`, `rate_limit_error`, `overloaded`. If found, rotation happens automatically.

**No accounts configured?** The hook exits silently. The tool is opt-in — without saved profiles, nothing happens.

## Fleet Integration

When rotation succeeds inside a fleet (tmux), `fleet.sh restart-all` is called to restart all panes with the new credentials. Outside tmux, only the current session benefits from the rotation.
