# VS Code Community Adapter Template

This template provides a starting point for contributing a VS Code adapter to HMG.

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
name = "vscode"
display_name = "VS Code"
support_level = "HookFirstSupported"
canonical_id = "vscode"

[adapter.detection]
binary = "code"
marker_dir = ".vscode"

[adapter.config]
format = "json"
path = ".vscode/mcp.json"

[adapter.hooks]
format = "json"
hooks_path = ".vscode/hooks.json"
script_path = ".vscode/hooks/hmg-lifecycle.sh"
```
