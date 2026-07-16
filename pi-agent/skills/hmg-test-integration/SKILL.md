---
name: hmg-test-integration
description: Independently verify that an HMG integration can write, recall, handoff, preserve scope isolation, and emit lifecycle events.
---

# HMG Test Integration

Use this workflow after an integration plan or init has been applied.

## Workflow

1. Run flag-off tests to establish unchanged baseline behavior.
2. Run flag-on tests for HMG MCP visibility.
3. Check hook event flow with `hmg agent-event explain`.
4. Check scoped daemon recall.
5. Check handoff write and later scoped brief recall.
6. Produce a pass/fail scorecard with minimal reproduction commands.

Use the deterministic runner for the handoff artifact:

```bash
python3 scripts/hmg-integration-scorecard.py test --agent <id> --target <repo> \
  --baseline-command '<existing flag-off test command>'
```

It writes `.hmg-integration/scorecard.json` with command exit state and hashed
evidence, never raw command output. Host loaded, executed, emitted, and
acknowledged stages must still be interpreted separately from
`hmg integrations explain`.

The result should prove memory write, recall, handoff, and scope isolation, not
merely that config files exist.
