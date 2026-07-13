---
name: hmg-eval-baseline
description: Run the local mem0 OSS vs HMG branch-isolation scorecard and interpret latency, hit rate, scope leakage, and agent brief usefulness.
---

# HMG Eval Baseline

Use this workflow to reproduce the product scorecard that treats mem0 as a
local friction benchmark for HMG's coding-agent memory path.

## Command

```bash
python3 scripts/run-hmg-product-optimization-scorecard.py
```

When a separate local mem0 virtualenv is required, provide its interpreter explicitly:

```bash
MEM0_PYTHON=/path/to/mem0-venv/bin/python
"$MEM0_PYTHON" scripts/run-hmg-product-optimization-scorecard.py --python "$MEM0_PYTHON"
```

The lower-level comparison harness remains available for debugging:

```bash
python3 scripts/compare-mem0-hmg-local.py --engine both --hmg-mode all --hmg-response-profile full --hmg-fast-recall --reset --cmd-timeout-secs 120 --top-k 5
```

## Dataset

The comparison harness resolves its versioned synthetic 8-fact
branch-isolation dataset from the repository checkout. Do not substitute
customer or production data.

## Required Product Checks

- HMG live daemon setup is ok
- HMG live daemon passes every recall and agent-brief check
- HMG live daemon scope leakage is 0
- HMG live daemon hit@k and agent brief injection quality meet the target
- HMG live daemon recall p50/p95 stay within the target
- HMG live daemon recall p95 is not slower than mem0 OSS local recall p95
- HMG embedded Rust, HMG embedded Python, and HMG embedded TypeScript pass every in-process recall check
- HMG embedded Rust, HMG embedded Python, and HMG embedded TypeScript report in-process transport with no daemon, CLI, or process spawn
- HMG embedded Rust, HMG embedded Python, and HMG embedded TypeScript recall p95 are not slower than mem0 OSS local recall p95
- HMG direct CLI fallback passes correctness and scope-leakage checks
- HMG direct CLI internal engine recall p95 stays within the fast-path target
- canonical skills do not drift from package/export copies

## Scorecard Fields

- latency p50, p95, average, min, max
- recall latency p50, p95, average, min, max
- agent brief latency p50, p95, average, min, max
- hit@k
- scope leakage
- context usefulness
- agent brief injection quality
- required checks and watch items

Do not claim broad production superiority from this mini workload alone. It
proves the local coding-memory live gate only. Direct CLI cold-start total
latency remains a watch item, but direct engine recall latency is a required
fast-path check.
