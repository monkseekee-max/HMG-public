# OpenClaw Community Adapter Template

This template provides a starting point for contributing an OpenClaw adapter to HMG.

## Files

- `adapter.toml` — Adapter metadata (name, version, config paths, hook support)

## Usage

1. Copy this template directory.
2. Edit `adapter.toml` with your agent's details.
3. Run `hmg init --agent <id>` to verify the adapter works.
4. Submit a PR adding the completed template under `adapters/templates/<agent-id>/`.

## Adapter Metadata Format

```toml
[adapter]
name = "openclaw"
display_name = "OpenClaw"
support_level = "HookFirstSupported"
canonical_id = "openclaw"

[adapter.detection]
binary = "openclaw"
marker_dir = ".openclaw"

[adapter.config]
format = "json"
path = "hmg-mcp.json"

[adapter.hooks]
format = "json"
hooks_path = ".openclaw/hooks.json"
script_path = ".openclaw/hooks/hmg-lifecycle.sh"
```
