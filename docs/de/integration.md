# Integration

HMG integrates with agents via the MCP protocol and host-native hooks. This chapter describes the integration shape finalized by the August 2026 integration-layer design.

## What you get after integrating

Once integrated, the agent manages memory precisely on its own during daily conversations — no need to keep reminding it to "remember this" or "recall the history first".

Concretely:

- **At session start**, the agent automatically receives a memory brief: last handoff, key decisions, known risks, next steps.
- **On every turn**, your message is used to prefetch relevant memories into the current context.
- **Scope isolation is automatic**: project / repository / branch are inferred mechanically from the session directory and injected — the agent never passes them and cannot get them wrong.
- **Writing is fully autonomous**: the agent calls `memorize` incrementally as decisions and exchanges happen, and calls `handoff` when the task ends.
- When new information conflicts with old memory, the agent corrects the stale memory (`correct`) instead of following outdated conclusions.

The agent no longer relies on the current session context alone — it gains long-term memory that accumulates continuously and recalls on demand. The longer you work on a project, the better the agent understands your codebase, conventions, and preferences.

## How it works

The integration layer has three parts:

1. **MCP server**: the agent reads and writes memory via MCP tools (`memory_memorize` / `memory_recall` / `memory_correct` / `memory_govern` / `memory_handoff` / `memory_stats`).
2. **Lifecycle hooks (3)**: inject context or calibrate parameters at fixed moments.

   | Hook | When | Job |
   |---|---|---|
   | `SessionStart` | session start / resume / clear / compact | emit the memory brief + status line |
   | `UserPromptSubmit` | every user message | prefetch relevant memories using the message; remind the agent to store when needed |
   | `PreToolUse` | before the agent calls an HMG MCP tool | infer scope from the session directory and inject it into the tool arguments |

3. **Memory policy file** (`hmg.md` / rules / CLAUDE.md injection): teaches the agent when to search on its own, when to store, how to attribute sources, and how to handle sensitive information.

Two hard design rules:

- **Memory writing has exactly two channels**: `memorize` (incremental) and `handoff` (session handoff). There is no mechanical fallback — rule scoring cannot tell "this conversation implies an important decision", so durable memory relies entirely on agent initiative.
- **The observation pipeline is not activated**: no mechanical capture of raw conversation or command output in agent integration, keeping low-quality memories out.

## General integration flow

```bash
# 1. Prepare the local runtime
hmg setup

# 2. Preview which files will be written for an agent
hmg init --agent codex --dry-run

# 3. Actually write the configuration
hmg init --agent codex

# 4. Check integration status
hmg doctor --agent codex
```

`hmg init` is the recommended entry point. It writes the MCP configuration, memory policy, and lifecycle hooks for each host. For manual configuration, use `hmg-server` directly.

## Integrating Codex

Codex integration consists of:

- `~/.codex/config.toml`: registers the `hmg` MCP server
- `~/.codex/hooks.json`: registers the 3 lifecycle hooks
- `~/.codex/hooks/hmg-lifecycle.sh`: a thin adapter that forwards host events to `hmg hook dispatch` (all logic lives inside the HMG binary)
- `~/.codex/hmg.md`: injects the autonomous memory policy

### Preview

```bash
hmg init --agent codex --dry-run
```

### Apply

```bash
hmg init --global --agent codex

# or update only the configuration tied to the current project context
hmg init --agent codex
```

### MCP configuration example

`hmg init` writes this automatically. The shape:

```toml
[mcp_servers.hmg]
type = "stdio"
command = "/Users/<user>/.local/bin/hmg-server"
args = ["/Users/<user>/.local/share/hmg/stores/default"]
startup_timeout_sec = 30

[mcp_servers.hmg.env]
HMG_PROVIDER_BACKEND = "local"
HMG_USE_LOCAL_DAEMON = "1"
```

> Do not set a fixed `cwd` for `mcp_servers.hmg`: the MCP server child process must inherit the session's working directory — HMG relies on it to infer scope.

### Hook behavior

- **SessionStart**: HMG assembles the memory brief (latest handoff, key decisions) + status line (`HMG Active | scope=... | atoms=N`) and injects it as context.
- **UserPromptSubmit**: prefetch recall using the current user message; the agent uses hits directly, and may search further on its own when nothing matches.
- **PreToolUse**: before any `mcp__hmg__*` call, scope is inferred from the session directory and injected into the arguments. Wrong scope passed by the agent is silently corrected.

### Verify

```bash
hmg doctor --agent codex
hmg doctor --agent codex --live-tool-smoke
```

After a successful integration, Codex lists HMG tools: `memory_memorize`, `memory_recall`, `memory_correct`, `memory_govern`, `memory_handoff`, `memory_stats`.

## Integrating Cursor

Cursor integration files are usually in the project directory:

- `.cursor/mcp.json`
- `.cursor/rules/hmg-memory.mdc`
- `.cursor/hooks.json`
- `.cursor/hooks/hmg-lifecycle.sh`

### Preview and apply

```bash
hmg init --agent cursor --dry-run
hmg init --agent cursor
```

### MCP configuration example

```json
{
  "mcpServers": {
    "hmg": {
      "command": "/Users/<user>/.local/bin/hmg-server",
      "args": ["/Users/<user>/.local/share/hmg/stores/default"],
      "env": {
        "HMG_DATA_DIR": "/Users/<user>/.local/share/hmg/stores/default",
        "HMG_PROVIDER_BACKEND": "local",
        "HMG_USE_LOCAL_DAEMON": "1"
      }
    }
  }
}
```

Cursor's hook event names differ from Codex (dialect difference); the adapter maps them automatically:

| Codex event | Cursor event |
|---|---|
| `SessionStart` | `sessionStart` |
| `UserPromptSubmit` | `beforeSubmitPrompt` |
| `PreToolUse` | `preToolUse` |

`.cursor/rules/hmg-memory.mdc` injects the memory usage rules — the same role as Codex's `hmg.md`.

### Verify

```bash
hmg doctor --agent cursor
```

See [Agent doesn't see HMG tools](troubleshooting.md#agent-cant-see-hmg-tools).

## Integrating Claude Code

Claude Code integration files typically include:

- `.mcp.json` in the project
- `CLAUDE.md` in the project
- `~/.claude/settings.json`
- `~/.claude/hooks/hmg-lifecycle.sh`

### Configure

```bash
hmg init --agent claude --dry-run
hmg init --agent claude
```

### MCP configuration example

```json
{
  "mcpServers": {
    "hmg": {
      "command": "/Users/<user>/.local/bin/hmg-server",
      "args": ["/Users/<user>/.local/share/hmg/stores/default"],
      "env": {
        "HMG_DATA_DIR": "/Users/<user>/.local/share/hmg/stores/default",
        "HMG_PROVIDER_BACKEND": "local",
        "HMG_USE_LOCAL_DAEMON": "1"
      }
    }
  }
}
```

Claude Code's hook event names are identical to Codex (`SessionStart` / `UserPromptSubmit` / `PreToolUse`), configured in the hooks section of `~/.claude/settings.json`. Behavior matches Codex: startup brief, per-turn prefetch, mechanical scope injection.

### Verify

```bash
hmg doctor --agent claude
```

## Memory attribution for ephemeral sessions

Ephemeral sessions (e.g. Codex desktop Chats opened from the bottom-left corner) are not attached to any project. They all share one fixed scope:

```
<os-username> / personal / chats / main
```

- Different ephemeral sessions share memories with each other (not isolated by session directory)
- Ephemeral sessions are isolated from project sessions: a user preference stored in an ephemeral session does not automatically appear in a project session; if needed, memorize it again inside the project session

## Importing existing memories {#importing-existing-memories}

If you accumulated conversation history or host-native memory files (Codex memories, CLAUDE.md, Cursor rules, etc.) before using HMG, import them in one pass with the `hmg-memory-import` skill:

Say "**import memories into HMG**" to your agent. It will:

1. Scan conversation history and native memory files, extracting items with long-term value
2. Classify by attribution: project-related → current project scope; cross-project user preferences → `personal/chats/main`
3. Show the list for your confirmation, write item by item, and report the results

The skill lives in `~/.codex/skills/hmg-memory-import/` (or `~/.claude/skills/` for Claude Code) and ships with HMG.

## Other MCP clients

HMG supports more agents than the three above. Check the current support list:

```bash
hmg integrations list
hmg integrations detect
hmg integrations explain codex cursor claude
```

### Generic MCP integration

Any MCP-compatible client can integrate manually, though `hmg init` auto-generation is still recommended.

1. Add the server to the client's MCP configuration:
   ```json
   {
     "mcpServers": {
       "hmg": {
         "command": "/Users/<user>/.local/bin/hmg-server",
         "args": ["/Users/<user>/.local/share/hmg/stores/default"]
       }
     }
   }
   ```
2. For a specific store or daemon mode, add `HMG_DATA_DIR` and `HMG_USE_LOCAL_DAEMON=1` to the environment.
3. Verify the client lists `memory_memorize`, `memory_recall`, `memory_correct`, `memory_handoff`, etc.

Hosts without hooks still work: MCP reads and writes are fully available, and scope is inferred by HMG from the MCP server process's working directory — you only miss the two automatic injection points (startup brief and per-turn prefetch).

### External event bridge

Hosts that cannot use MCP directly can bridge via the lifecycle bridge:

```bash
hmg agent-event --explain --payload '{"event":"pre_edit_recall","files":["src/lib.rs"]}'
```

---

Next: [Troubleshooting](troubleshooting.md)
