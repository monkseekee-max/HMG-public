---
name: hmg-health
description: Produce an HMG health scorecard from doctor JSON, disposable memory smoke, agent-event explain, and daemon latency sampling.
---

# HMG Health

Use this workflow when HMG readiness is unclear or a benchmark/integration needs
an independent health scorecard.

## Workflow

1. Run `hmg doctor --format json`.
2. Use a disposable scope for a memorize/recall/handoff smoke.
3. Run `hmg agent-event explain --file event.json --format json`.
4. Run `hmg integrations explain --format json` and distinguish verified,
   advisory, and planned integration evidence.
5. Sample daemon latency with `hmg daemon status --format json` and a small
   scoped recall.
6. Report core memory, scope, hooks, daemon, scheduler, embedding, and optional
   integration status separately.

## Output

Return pass/warn/fail, evidence, blocker status, and the shortest repair
command. Do not treat warnings as blockers, and do not downgrade blockers to
warnings.
