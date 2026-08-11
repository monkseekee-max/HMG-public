# HMG Examples

Integration quickstarts and synthetic data for HMG Community Edition.

## Quickstarts

| Language | File | Description |
|---|---|---|
| Python | [`quickstart.py`](quickstart.py) | Memorize, recall, correct, govern via Python SDK |
| TypeScript | [`quickstart.ts`](quickstart.ts) | Memorize, recall, correct, govern via TypeScript SDK |
| MCP (raw) | See [MCP Reference](../docs/en/mcp-reference.md) | Direct MCP tool calls |
| HTTP (curl) | See [MCP Reference](../docs/en/mcp-reference.md) | REST API examples |

## Prerequisites

Start a local HMG daemon:

```bash
# Install HMG
curl -L https://hmg1ai.com/releases/latest/download/install.sh | sh

# Start the daemon
hmg daemon start
```

## Python

```bash
pip install hmg-sdk
python quickstart.py
```

```python
from hmg import HMGClient

client = HMGClient(base_url="http://localhost:8080")

# Store a decision
client.memorize(
    content="We chose PostgreSQL for the main database",
    source="architecture-review",
)

# Recall memories
result = client.recall(query="database choice")
for atom in result.atoms:
    print(f"[{atom.score:.2f}] {atom.text}")
```

## TypeScript

```bash
npm install @hmg_ai/sdk-ts
npx ts-node quickstart.ts
```

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://localhost:8080" });

await client.memorize({
  content: "API uses JWT tokens with 24h expiry",
  domain_pack_id: "software-engineering",
});

const result = await client.recall({ query: "authentication approach" });
for (const atom of result.atoms) {
  console.log(atom.text);
}
```

## Synthetic Fixtures

The [`synthetic-fixtures/`](synthetic-fixtures/) directory contains sample atom data for testing integrations. No real user data is included — all fixtures are synthetic.

## More Resources

- [Quick Start](../docs/en/quick-start.md) — full setup guide
- [MCP Reference](../docs/en/mcp-reference.md) — all tools and endpoints
- [Concepts](../docs/en/concepts.md) — memory atoms, correction, governance

## License

Apache-2.0
