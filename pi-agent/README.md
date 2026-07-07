# @hmg_ai/pi-agent

<p>
  <img src="https://img.shields.io/badge/version-1.7.5-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT%20%7C%20Apache--2.0-green.svg" alt="License">
</p>

Pi Package that exposes HMG memory tools to pi (Codex fork) as native custom tools.

If npm publication is temporarily delayed by npm account policy, the matching release tarball is also published on the HMG-public GitHub release for the same tag.

## Install

```bash
pi install npm:@hmg_ai/pi-agent@1.7.5
```

HMG's installer and `hmg init -g` use the same package route when pi is detected.

If you previously used the legacy generated extension at `~/.pi/agent/extensions/hmg`, remove or move that directory before starting pi. HMG's `hmg init --agent pi` path retires it automatically into `~/.pi/agent/extension-backups/`; direct `pi install` users can run:

```bash
mkdir -p ~/.pi/agent/extension-backups
mv ~/.pi/agent/extensions/hmg ~/.pi/agent/extension-backups/hmg.legacy-backup
```

Do not keep backups under `~/.pi/agent/extensions/`; pi loads extension-looking directories from there.

## Configuration

The extension reads local HMG binaries and storage from the environment, with safe defaults:

- `HMG_CLI` defaults to `hmg`
- `HMG_SERVER` defaults to `hmg-server`
- `HMG_PI_DATA_DIR` overrides storage; otherwise `HMG_DATA_DIR` or the platform default `~/.local/share/hmg/stores/default` is used
- `HMG_PROVIDER_BACKEND` defaults to `local` for spawned MCP calls

## Tool Output

`hmg_agent_brief` defaults to HMG's `compact_yaml` profile and returns only the brief text to pi, while keeping small metadata in tool details. Pass `brief_format: "full"` or `include_debug: true` only when debugging the HMG server payload.

`hmg_recall` defaults to compact agent-readable YAML (`response_profile: "compact"`, `output_format: "yaml"`). Use `response_profile: "summary"` with Markdown for human review, or explicit `response_profile: "full"` / `"debug"` when a client needs the JSON payload or recall trace diagnostics.

## Uninstall

```bash
pi remove npm:@hmg_ai/pi-agent
```

If you want to restore the legacy extension backup, move it back to `~/.pi/agent/extensions/hmg` after removing the package.
