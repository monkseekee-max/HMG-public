# @hmg_ai/pi-agent

![Version](https://img.shields.io/badge/version-1.7.8-blue.svg)

Pi Package that exposes HMG memory tools to pi as native custom tools.

## Install

```bash
pi install npm:@hmg_ai/pi-agent@1.6.5
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

## Offline Self-Test

Use the HMG CLI self-test to verify the HMG pi package files expected by this build without calling a model provider:

```bash
hmg doctor --agent pi --package-self-test --format json
```

This check is intentionally independent of pi's LLM backend. If pi returns a model-service error, rerun the package self-test to separate HMG package-file health from provider availability. A full runtime tool invocation smoke remains a separate integration check.

## Tool Output

`hmg_agent_brief` defaults to HMG's `compact_yaml` profile and returns only the brief text to pi, while keeping small metadata in tool details. Pass `brief_format: "full"` or `include_debug: true` only when debugging the HMG server payload.

`hmg_recall` defaults to compact agent-readable YAML (`response_profile: "compact"`, `output_format: "yaml"`). Use `response_profile: "summary"` with Markdown for human review, or explicit `response_profile: "full"` / `"debug"` when a client needs the JSON payload or recall trace diagnostics. Set `primary_only: true` for exact/entity/sentinel lookups where the agent should receive only the primary answer/source set instead of broad supporting context.

## Uninstall

```bash
pi remove npm:@hmg_ai/pi-agent
```

If you want to restore the legacy extension backup, move it back to `~/.pi/agent/extensions/hmg` after removing the package.
