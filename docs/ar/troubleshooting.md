# Troubleshooting

## Install failure {#install-failure}
**Symptom**: `hmg --version` prints nothing or the command is not found.

**Steps**:
1. Confirm the installer completed; check that PATH includes the HMG install directory.
2. Re-run the official install command.
3. Verify the binary directly:
   ```bash
   /full/path/to/hmg --version
   ```
4. Download failures from network/permission issues: check proxy and disk permissions.

## Agent doesn't see HMG tools {#agent-cant-see-hmg-tools}
**Symptom**: no `memory_memorize` / `memory_recall` etc. (`memory_*`) tools in the agent session.

**Steps**:
1. Confirm the MCP configuration was generated: `hmg doctor --agent <id>`.
2. Run `hmg init --agent <id> --dry-run` to see which host files the current version writes.
3. Check the configuration uses `hmg-server <store-path>`.
4. Restart the agent (MCP configuration usually needs a restart).
5. Verify the local runtime: `hmg doctor`, `hmg daemon status`.
6. Check the agent's own MCP / hooks logs for connection errors.

```bash
hmg doctor --agent codex
hmg init --agent codex --dry-run
hmg daemon status
```

## No memory context injected into the session

**Symptom**: no memory brief at session start, or no prefetch results per turn.

**Steps**:
1. Confirm hooks are registered and contain the three events (`SessionStart` / `UserPromptSubmit` / `PreToolUse`):
   ```bash
   cat ~/.codex/hooks.json        # Codex
   cat .cursor/hooks.json         # Cursor
   ```
2. Confirm the adapter script exists and is executable: `ls -l ~/.codex/hooks/hmg-lifecycle.sh`.
3. Test the dispatch chain manually (run inside your project directory):
   ```bash
   echo '{"hook_event_name":"SessionStart","cwd":"'"$PWD"'"}' | ~/.codex/hooks/hmg-lifecycle.sh
   ```
   Normally this prints the memory brief; no output or an error → run `hmg doctor`.
4. Hook failures exit silently (they never block the agent), so "no error but no brief" requires manual checking as above.
5. Re-integrate: `hmg init --agent <id>` rewrites the hooks configuration.

## HMG service not running

**Symptom**: commands report the daemon unavailable, model not ready, or persistent direct fallback.

**Steps**:
1. Run `hmg setup` to ensure the local runtime is prepared.
2. `hmg model status` for embedding model state.
3. `hmg daemon status` for daemon state.
4. Read the error on startup failure; use `--store` if the store path is wrong.
5. Still broken: `hmg daemon restart`, or temporarily bypass the daemon with `--direct`.
6. For autostart: `hmg daemon install-service`.

```bash
hmg setup
hmg model status
hmg daemon status
```

## Login failure / plan not taking effect

**Symptom**: `hmg login` errors, or the plan was upgraded on the website but capabilities stay locked.

**Steps**:
1. Login requires network: confirm the HMG user center is reachable (check proxy).
2. Confirm the plan upgrade completed on the website, and the account used for `hmg login` matches the one that purchased the plan.
3. Signature verification failure: retry once; if it persists contact support with `hmg doctor --verbose` output.
4. Login only affects developer-edition features and capacity — basic memory features work without login.

## Recall can't find what I want {#recall-cannot-find}
**Possible causes and fixes**:

| Cause | Fix |
|------|------|
| Query too broad or conversational | Use noun phrases: `login 500 root cause` beats "how did we handle this before" |
| Never stored | Write it first with `hmg memorize` |
| Wrong scope | Current repo/branch differs from when the memory was stored — specify `--scope`; note ephemeral-session memories live in `personal/chats/main` and are invisible in project sessions |
| Memory demoted/tombstoned | Check state with `hmg history <id>` |
| Noise interference | Report noise phrases with `hmg noise-feedback` |
| Spelling/terminology mismatch | Try synonyms, or `hmg suggest-query` for suggestions |

## Too many or messy recall results

**Fixes**:
1. Narrow the query.
2. Limit results with `--max-results <n>`.
3. Compact output with `--profile compact`.
4. Clean stale memories: `hmg store hygiene`, correct/demote old info.
5. Report noise: `hmg noise-feedback "<noise phrase>"`.

## Wrote a memory by mistake

**Don't delete — correct**:

```bash
# Wrong content → replace
hmg correct <atom-id> --action replace --reason "wrote it wrong" --new-content "correct content"

# No longer needed → demote
hmg correct <atom-id> --action demote-possible --reason "no longer applicable"
```

Wrong replace? Just replace again on that same atom. Corrections keep history — `hmg history <atom-id>` traces everything.

## Wrote sensitive information by mistake

**Govern immediately — don't just delete** (keep the audit trail):

```bash
# Full removal (tombstone + destroy payload)
hmg govern <atom-id> --action tombstone --destroy-payload --reason "API key written by mistake"

# Isolate only (content kept, hidden from recall)
hmg govern <atom-id> --action quarantine --reason "sensitive info temporarily isolated"

# Distill a redacted lesson
hmg govern <atom-id> --action derive-lesson --lesson "credentials belong in the secret vault"
```

From now on store credentials with `hmg secret store`. See [Removing or isolating sensitive information](daily-usage.md#sensitive-memory-governance).

## Memories from multiple projects mixed together

**Cause**: shared default store without scope separation.

**Fixes**:
1. In agent integration scope is inferred automatically from the session directory, so this rarely happens; if a session was started outside a project directory, memories land in the scope inferred for that directory.
2. Use a project-dedicated store: `hmg memorize "..." --store /proj/store`.
3. Or explicit `--scope repository`/`branch` within the default store.
4. Cross-project preferences only at `--scope tenant`.

See [Scope](concepts.md#scope) for the mechanism.

## Store lock or daemon issues

**Symptom**: write errors about locks, or the daemon is unresponsive.

**Steps**:
1. `hmg daemon status` — is it stuck?
2. `hmg daemon restart`.
3. Check for multiple processes contending for the same store (several agents + direct CLI writing simultaneously). Prefer going through the daemon.
4. Corrupt indexes: `hmg store repair-edges --backup --apply`.
5. Still failing: back up the store, then operate in `--direct` mode to isolate the issue.

## Backing up or migrating local data {#backup-or-migrate-local-data}
```bash
# Backup: copy the directory
cp -r "<store-dir>" ./hmg-backup-$(date +%F)

# Or export
hmg export --format json --output ./hmg-export.json

# Migrate to a new machine/path
hmg store migrate --from /old/store --to /new/store --backup --apply
```

> Default store path: see [Store directory](settings.md#store-directory); `hmg doctor --verbose` prints it.

---

Next: [FAQ](faq.md)
