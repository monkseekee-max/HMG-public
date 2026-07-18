# @hmg_ai/sdk-ts

<p>
  <img src="https://img.shields.io/badge/version-1.7.8-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-Apache--2.0-green.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-Node.js%2018%2B-blue.svg" alt="Platform">
</p>

TypeScript SDK for the HMG agent memory system.

## Install

```bash
npm install @hmg_ai/sdk-ts
```

## Quick Start

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://localhost:8080" });

// Store a decision
await client.memorize({
  content: "We chose PostgreSQL for the main database",
  source: "architecture-review",
  modality: "text",
});

// Recall it later
const result = await client.recall({ query: "database choice" });
for (const atom of result.atoms) {
  console.log(`[${atom.score}] ${atom.text}`);
}

// Correct when it changes
await client.correct(atom.id, {
  action: "replace",
  reason: "Migrated to CockroachDB",
  newContent: "We migrated to CockroachDB for horizontal scale",
});
```

## API Surface

| Method | Description |
|---|---|
| `client.memorize(options)` | Store a memory atom |
| `client.recall(options)` | Recall memories by query |
| `client.correct(atomId, options)` | Correct a memory atom |
| `client.govern(atomId, options)` | Govern a memory atom's visibility |
| `client.handoff(summary)` | Store a cross-session handoff |
| `client.agentBrief(options)` | Get session-start context |
| `client.history(atomId)` | Get correction/governance history |
| `client.stats()` | Get memory store statistics |

## Types

```typescript
interface HMGClientOptions {
  baseUrl?: string;  // default: http://localhost:8080
  apiKey?: string;   // for Enterprise
}

interface MemorizeOptions {
  content: string;
  source?: string;
  modality?: "text" | "code" | "dialogue" | "observation";
  context?: MemoryContext;
}

interface RecallOptions {
  query: string;
  maxResults?: number;
  outputFormat?: "yaml" | "json" | "markdown";
  context?: MemoryContext;
}

interface MemoryContext {
  tenant_id?: string;
  workspace?: string;
  repository?: string;
  branch?: string;
}
```

## Requirements

- Node.js 18+
- HMG daemon running (`hmg daemon start`)

## License

Apache-2.0
