# hmg

<p>
  <img src="https://img.shields.io/badge/version-1.7.6-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-Apache--2.0-green.svg" alt="License">
  <img src="https://img.shields.io/badge/python-3.9%2B-blue.svg" alt="Python">
</p>

Python SDK for the HMG agent memory system.

## Install

```bash
pip install hmg-sdk
```

## Quick Start

```python
from hmg import HMGClient

client = HMGClient(base_url="http://localhost:8080")

# Store a decision
client.memorize(
    content="We chose PostgreSQL for the main database",
    source="architecture-review",
    modality="text",
)

# Recall it later
result = client.recall(query="database choice")
for atom in result.atoms:
    print(f"[{atom.score:.2f}] {atom.text}")

# Correct when it changes
client.correct(
    atom_id=atom.id,
    action="replace",
    reason="Migrated to CockroachDB",
    new_content="We migrated to CockroachDB for horizontal scale",
)
```

## API Surface

| Method | Description |
|---|---|
| `client.memorize(...)` | Store a memory atom |
| `client.recall(...)` | Recall memories by query |
| `client.correct(...)` | Correct a memory atom |
| `client.govern(...)` | Govern a memory atom's visibility |
| `client.handoff(...)` | Store a cross-session handoff |
| `client.agent_brief(...)` | Get session-start context |
| `client.history(...)` | Get correction/governance history |
| `client.stats()` | Get memory store statistics |

## Requirements

- Python 3.9+
- HMG daemon running (`hmg daemon start`)

## License

Apache-2.0
