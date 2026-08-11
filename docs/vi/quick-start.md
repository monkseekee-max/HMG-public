---
sidebar_position: 2
---

# Quick Start

## Installing HMG

HMG ships as a standalone binary via an official installer. The installer detects your platform, installs to the default directory, and configures PATH.

### macOS / Linux

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### Verify the installation

```bash
hmg version
# Expected output, e.g.: hmg 1.7.8-developer
```

### Upgrade

```bash

# Upgrade to the latest version (after installation)
hmg update

# To use a specific installer source
hmg update --installer-url <installer URL>
```

### Uninstall

Remove the install directory and clean up the PATH entry. Store data is not deleted automatically (your memories are kept); delete the store directory manually for a full cleanup.

> Install failure? See [Install failure](troubleshooting.md#install-failure).

## Login and plans (optional)

Basic memory features work without login. To unlock developer-edition features and a higher memory capacity:

1. **Upgrade your plan** in the user center on the HMG website
2. Log in locally:

```bash
hmg login
```

Login requires network: HMG verifies your account with the remote service, identifies your plan, receives a signature, and unlocks the corresponding capabilities after local signature verification.

- Login performs **no data migration**: local reads and writes always use your OS username as the tenant; the account is only used for identity mapping in cloud scenarios
- Logging out or switching accounts only affects the cloud-side identity — local memories are untouched

## Starting HMG locally

After installation, let HMG prepare the local runtime. `setup` handles the daemon, the embedding model, and the components needed to run locally.

### Prepare the runtime

```bash
# Preview what setup will do
hmg setup --dry-run

# Actually prepare the local runtime
hmg setup
```

### Confirm it started

```bash
hmg doctor
```

`doctor` checks the core, store, integrations, and runtime state. On a fresh install it usually reports some agents as not integrated yet — that is normal.

### Connect an agent

If you want Codex, Cursor, or Claude Code to manage memory automatically in daily conversations:

```bash
hmg init --agent codex --dry-run
```

Then run `hmg init --agent <agent-id>` for the agents you actually use. See [Integration](integration.md) for details.

---

## Write, recall, correct

HMG memory operations come down to three core commands: write, recall, correct. Let's walk through a simple example.

### 1. Write a memory

```bash
hmg memorize "This project uses SQLite for the local cache; Redis is not introduced because we are offline-first" --source quick-start
```

A single self-contained sentence is enough: no `decision:` style prefix needed — HMG infers certainty, polarity, and other metadata automatically. The output returns an atom id (the memory's unique identifier) like `atom-xxxx`. Keep it — you'll need it in the next step.

### 2. Recall memories

```bash
hmg recall "what do we use for the local cache"
```

If the "SQLite cache" you just wrote shows up, the write-and-recall pipeline works.

### 3. Correct a memory

When an old memory turns out wrong or outdated, correct it with `correct` instead of appending a new one:

```bash
# Replace the content of the memory you just wrote
hmg correct atom-xxxx --action replace --reason "switched to LevelDB" --new-content "This project uses LevelDB for the local cache; Redis is not introduced because we are offline-first"
```

`hmg recall "what do we use for the local cache"` now returns the updated content.

> Once an agent is integrated, the agent performs these three steps automatically at the right moments — no manual work needed. See [Integration](integration.md).

---

Next: [Daily Usage Guide](daily-usage.md)
