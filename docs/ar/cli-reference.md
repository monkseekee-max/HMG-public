---
sidebar_position: 1
---

# CLI Reference

All HMG capabilities are available through the `hmg` command line. This page lists the public commands by category; for the correspondence with in-session agent tools see [MCP Reference](mcp-reference.md).

## Global options

Most commands support:

| Option | Description |
|---|---|
| `--store <path>` | Specify the store directory (default `~/.local/share/hmg/stores/default`) |
| `--scope <tenant/workspace/repository/branch>` | Explicit scope; inferred from the current directory when omitted |
| `--format text\|json\|yaml` | Output format |
| `--direct` | Bypass the daemon and open the store in-process |
| `--dry-run` | Preview the changes without applying them |

Run `hmg help <command>` for examples of one command, `hmg help commands` for the full command list.

## Command overview

| Category | Commands |
|---|---|
| Memory read/write | `memorize`, `recall`, `correct`, `govern`, `history`, `stats`, `export` |
| Task context | `agent-brief`, `handoff` |
| Query | `query`, `suggest-query`, `query-templates`, `explain-query`, `schema`, `recall-view`, `noise-feedback`, `panorama`, `impact` |
| Install & integration | `setup`, `init`, `doctor`, `login`, `account status`, `onboard`, `integrations`, `update`, `uninstall` |
| Runtime | `daemon`, `model`, `hook`, `agent-event`, `agent-timeline` |
| Store maintenance | `store migrate`, `store hygiene`, `store repair-edges`, `verify` |
| Secret vault | `secret store / lookup / use / reveal / rotate / revoke` |
| Observation layer | `obs capture / promote / forget / maintain / review-queue`, `observation config / scheduler` |
| Other | `tui`, `version`, `language`, `completions` |

---

## Memory read/write

### hmg memorize

Write one long-term memory.

```
hmg memorize <content> [--source <src>] [--scope <t/w/r/b>] [--file <path>] [--dry-run]
```

| Argument | Description |
|---|---|
| `--source` | Source attribution (e.g. `user`, `cli`, custom labels) |
| `--file` | Read content from a file (use when content has quotes/multiple lines) |

```bash
hmg memorize "This project uses PostgreSQL 16 as the primary database, not MongoDB" --source cli
```

> Identical content is never written twice (returns the existing atom). Scope is inferred from the current directory when omitted.

### hmg recall

Recall memories by natural language.

```
hmg recall <query> [--max-results <n>] [--profile compact|summary|full|debug]
                   [--scope <t/w/r/b>] [--include-negated] [--precision]
```

```bash
hmg recall "database selection decision"
hmg recall "login 500 root cause" --profile full
```

| Argument | Description |
|---|---|
| `--profile` | Output detail: `compact` (default) / `summary` / `full` (with edges) / `debug` (with retrieval diagnostics) |
| `--include-negated` | Include negated memories (see "what we used to believe") |
| `--precision` | Stricter recall gating |

### hmg correct

Correct one memory.

```
hmg correct <atom_id> --action <action> --reason <text> [--new-content <text>]
```

`--action` values: `replace` / `confirm-actual` / `confirm-necessary` / `demote-possible`.

```bash
hmg correct 01J9ZK8... --action replace \
  --reason "migrated to PostgreSQL in v3" \
  --new-content "The primary database is PostgreSQL 16, replacing the old MongoDB plan"
```

> To negate a memory use `govern quarantine` (CLI layer); MCP/SDK uses `negate`. `negate` is not precisely reversible — recover with `replace`.

### hmg govern

Govern the lifecycle of one memory.

```
hmg govern <atom_id> --action <action> --reason <text> [--lesson <text>] [--destroy-payload]
```

`--action` values: `quarantine` / `seal` / `tombstone` / `derive-lesson`.

```bash
# Sensitive info written by mistake: remove completely
hmg govern 01J9ZK8... --action tombstone --destroy-payload --reason "API key written by mistake"

# Distill a redacted lesson, retire the original
hmg govern 01J9ZK8... --action derive-lesson --reason "original contains a secret" \
  --lesson "credentials belong in the secret vault, not in regular memories"
```

### hmg history / stats / export

```
hmg history <atom_id>          # full correction/governance evolution of one memory
hmg stats                      # atom / edge / index / snapshot version statistics
hmg export [--format json|csv] [--output <path>]   # export all atoms and edges
```

---

## Task context

### hmg agent-brief

Context summary at task start (last handoff, key decisions, known issues, open items).

```
hmg agent-brief [<query>] [--profile compact|summary|full|debug] [--scope <t/w/r/b>]
```

```bash
hmg agent-brief --query "fix intermittent 500 on the login endpoint"
```

> In agent integration the brief is injected automatically by the SessionStart hook — no manual call needed.

### hmg handoff

Write a handoff summary at task end (recalled with priority by the next session's startup brief).

```
hmg handoff <summary> [--source <src>] [--scope <t/w/r/b>]
```

```bash
hmg handoff "Fixed login 500: token expiry check switched to UTC. Validation: 200 concurrent logins, no 500. Risk: old clients cache expiry. Next: check the refresh token flow."
```

> Cover the five elements: what changed / why / validation / risks / next steps.

---

## Query

| Command | Purpose |
|---|---|
| `hmg query <intent-task> <query-text>` | Run a structured query template (e.g. decision tracing) |
| `hmg query --sql <sql>` | Read-only MemoryQL query (advanced) |
| `hmg query-templates` | List available query templates |
| `hmg suggest-query <text>` | Let HMG suggest how to ask |
| `hmg explain-query` | Explain a query plan |
| `hmg schema` | Show the MemoryQL logical schema |
| `hmg recall-view <query> --view <id>` | Recall through a named view (normal / governance / audit) |
| `hmg noise-feedback <content>` | Report noise phrases to down-weight in retrieval |
| `hmg panorama <query>` | Explore broader graph context |
| `hmg impact <query>` | Assess the blast radius of a change |

```bash
hmg query-templates                 # see available templates
hmg query <intent-task> "cache selection decision"
hmg noise-feedback "npm install succeeded"
```

---

## Install & integration

### hmg setup / init / doctor

```
hmg setup [--dry-run] [--no-daemon] [--no-model] [--no-agent-adapters]
hmg init [--global] [--agent <id>] [--all-agents] [--dry-run]
hmg doctor [--agent <id>] [--all-agents] [--fix] [--live-tool-smoke] [--verbose]
```

| Command | Role |
|---|---|
| `setup` | Prepare the local runtime (daemon, embedding model) |
| `init` | Write agent integration configuration (MCP, hooks, memory policy file). `--dry-run` previews |
| `doctor` | Health check: core / store / integrations / runtime; `--fix` repairs what it can |

```bash
hmg setup
hmg init --agent codex --dry-run
hmg init --agent codex
hmg doctor --agent codex
```

### hmg login / account status

```
hmg login
hmg account status
```

Basic memory features work without login. After upgrading your plan in the user center on the website, run `hmg login` to verify the account online and unlock the corresponding capabilities and capacity. Login does not migrate local data; the tenant is always the OS username.

### hmg onboard

Import existing agent memories and verify with real recall.

```
hmg onboard [--import <file>] [--memory-path <path>] [--all] [--dry-run] [--non-interactive]
```

> Saying "import memories into HMG" to your agent (the `hmg-memory-import` skill) runs a conversational import; `hmg onboard` is the direct CLI import.

### Others

```
hmg update [--installer-url <url>]    # upgrade
hmg uninstall [--purge-data]          # uninstall (store data preserved by default)
hmg integrations list|detect|explain|remove   # manage agent integrations
hmg version                           # version and edition
```

---

## Runtime

```
hmg daemon start|status|stop|restart [--store <path>]
hmg daemon install-service            # install as a user service (autostart)
hmg model status                      # embedding model state
```

Hooks and event bridging:

```
hmg hook dispatch --host <id> --event <name> [--payload <json>]   # unified entry for host hooks
hmg hook status [--host <id>] [--session-id <id>]                 # session and receipt diagnostics (body-free)
hmg agent-event --payload <json> [--explain] [--dry-run]          # bridge external agent lifecycle events
hmg agent-timeline --event-id <id>                                # query persisted agent timelines
```

> `hmg hook dispatch` is called by host hook scripts (see [Integration](integration.md)) — normally no manual use; run it manually to verify the hook chain when troubleshooting.

---

## Store maintenance

```
hmg store migrate --from <path> --to <path> [--backup] [--apply|--dry-run]
hmg store hygiene [--scope <t/w/r/b>] [--dry-run] [--force]      # clean orphan edges/indexes
hmg store repair-edges [--backup] [--apply] [--dry-run]          # repair corrupted edges
hmg verify                                                        # graph and storage integrity check
```

---

## Secret vault

Credentials never go into regular memories — use the vault:

```
hmg secret store <name> <value>     # store
hmg secret lookup <name>            # metadata (no plaintext)
hmg secret use <name>               # server-side authorized use
hmg secret reveal <name>            # reveal plaintext when necessary
hmg secret rotate <name> <new>      # rotate
hmg secret revoke <name>            # revoke
```

---

## Observation layer (optional)

Not activated in agent integration; for CLI / automation pipelines:

```
hmg obs capture <content> [--source <src>]   # capture one observation
hmg obs review-queue                         # observations pending promotion
hmg obs promote [--dry-run]                  # promote to durable memory
hmg obs forget [<id>|--query <text>] [--confirm]   # delete observations
hmg obs maintain                             # run retention cleanup
hmg observation config get|set <field> <value>     # observation config
hmg observation scheduler status|run-once          # consolidation scheduler
```

---

## Other

```
hmg tui [--theme <name>] [--language <lang>]   # terminal UI
hmg language show|list|set <lang>|reset        # CLI language
hmg completions <shell>                        # shell completion scripts
```

---

Next: [MCP Reference](mcp-reference.md)
