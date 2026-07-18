# Getting Started with HMG

## Prerequisites

- Linux (x86_64 or ARM64) or macOS (Intel or Apple Silicon)
- An AI agent or coding tool that supports MCP (Model Context Protocol)

## Install

### Linux / macOS
```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows (PowerShell)
```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

Or download directly from [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases):

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/

# Windows x86_64
# Download from https://github.com/HMG-AI/HMG-public/releases/latest
```

## Verify

```bash
hmg --version
# hmg 1.7.6-community
```

## Update or Uninstall

```bash
hmg update
hmg uninstall
```

Install and update automatically verify the complete candidate before stopping
the current daemon, create a verified offline memory backup, preserve keys,
switch binaries, repair setup, and verify daemon takeover. Required-step failure
restores the previous binaries and daemon automatically.

`hmg uninstall` removes the runtime and HMG-owned integration entries while
preserving memories, observations, audit history, and keys. Permanent removal
requires the explicit destructive form below; a custom store outside HMG's
managed data home is still preserved.

```bash
hmg uninstall --purge-data --confirm-purge PURGE-HMG-DATA
```


## Start the Memory Service

```bash
hmg daemon start
```

The daemon starts a local MCP server at `~/.local/share/hmg/stores/default` by default.
No data leaves your machine.


## Connect Your Agent

### Cursor

```bash
hmg init --agent cursor
# Restart Cursor. HMG tools appear in MCP settings.
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```


### Pi

```bash
hmg init --agent pi
```

### Generic MCP Client

HMG exposes a standard MCP server over stdio. Configure your client to run:

```json
{
  "mcpServers": {
    "hmg": {
      "command": "hmg-server",
      "args": ["~/.local/share/hmg/stores/default"]
    }
  }
}
```

## Verify Your Setup

```bash
hmg doctor
```

`hmg doctor` checks all integrations, daemon status, and MCP readiness:


## Detect Available Agents

```bash
hmg integrations detect
```


## First Memory

Use any MCP tool to store and retrieve memories:

```json
// Store a decision
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "Decision: Use PostgreSQL for user data. Rationale: ACID compliance and mature tooling.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// Recall later
{
  "tool": "memory_recall",
  "arguments": {
    "query": "What database did we choose?"
  }
}
```



## Edition and License

Check your current edition and feature limits:

```bash
hmg license status
```


## What's Available in Community Edition

| Feature | Available |
|---|---|
| Memory storage (memorize) | ✅ |
| Memory retrieval (recall) | ✅ One-Shot Recall (P1-P9) |
| Correction lifecycle | ✅ Full |
| Governance lifecycle | ✅ Full |
| MCP protocol | ✅ Full |
| HTTP API | ✅ Full |
| Agent integration | ✅ All adapters |
| One-Shot Recall Engine | ✅ Full (P1-P9) |
| Automated consolidation | ❌ Developer/Enterprise |
| Domain Packs | ❌ Developer/Enterprise |
| Semantic (vector) search | ✅ |

## Next Steps

- [Concepts](concepts.md) — understand memory atoms, correction, governance, scope
- [Architecture](architecture.md) — how HMG works, plus TUI visual tour
- [API Reference](api-reference.md) — all MCP tools and HTTP endpoints
- [Correction and Governance](correction-governance.md)
- [FAQ](faq.md)
- [Upgrade to Developer](upgrade.md)
