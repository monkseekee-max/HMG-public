# Hermes Community Adapter Template

This template provides a starting point for contributing a Hermes adapter to HMG.

## Files

- `adapter.toml` — Adapter metadata (name, version, config paths, hook support)
- `config.json` — MCP server configuration template
- `hooks.json` — Lifecycle hook configuration template

## Usage

1. Copy this template directory.
2. Edit `adapter.toml` with your agent's details.
3. Run `hmg init --agent <id>` to verify the adapter works.
4. Submit a PR adding the completed template under `adapters/templates/<agent-id>/`.

## Adapter Metadata Format

```toml
[adapter]
name = "hermes"
display_name = "Hermes Agent"
support_level = "HookFirstSupported"
canonical_id = "hermes"

[adapter.detection]
binary = "hermes"
marker_dir = ".hermes"

[adapter.config]
format = "json"
path = "hmg-mcp.json"

[adapter.hooks]
format = "json"
hooks_path = ".hermes/hooks.json"
script_path = ".hermes/hooks/hmg-lifecycle.sh"
```
