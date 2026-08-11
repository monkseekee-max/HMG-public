# Best Practices

## What is worth remembering

Criteria — meeting any one makes it worth storing:

- **Reused in the future**: you will need this information again
- **Affects decisions**: helps future choices
- **Cuts repeated explanation**: no need to re-explain every time
- **Reduces risk**: known pitfalls/constraints help you avoid trouble

Typically worth storing: decisions with reasons, root causes, stable constraints, stable user preferences, verification results, known risks, next steps.

A simpler test in agent integration: **Will this information still be useful in the next session?** Yes → store. Only useful for the current task → don't.

## What is not worth remembering

Never store:
- **secrets / tokens / passwords / credentials** (use the secret vault)
- full logs, full command output
- transient debugging fragments (console.log, throwaway variables)
- unconfirmed guesses

Better not store:
- one-off instructions ("just do it this way this time")
- running accounts ("I just installed X")
- anything directly inferable from the code (no memory needed)

## How to write high-quality memories

Four qualities: **concise, verifiable, contextual, reasoned** — no noise.

### Before / after

**❌ Before (bad):**

```
I just added a check in the login module comparing token expiry, there seemed to be a problem before, should be fine now, also used the moment library
```

Problems: no reason, not verifiable, reads like a running account, piles in unrelated detail (moment).

**✅ After (good):**

```
The intermittent login 500 was caused by comparing token expiry against local time. Fixed by comparing in UTC and dropping moment for native Date. Verified with 200 concurrent logins, no 500s.
```

### Writing rules

- **Self-contained declarative sentence**: understandable without the original conversation; no "decision:" style prefix (HMG infers type and certainty itself)
- **One memory, one sentence**: store 1-3 items at a time, 1-2 sentences each — no essays
- **Store in the language of the conversation**: Chinese conversations stored in Chinese, English in English
- **Mark the source**: what the user said verbatim is `user` (more authoritative); what the agent concluded is `agent`; later corrections can trace who said it
- **No need to check for duplicates first**: HMG deduplicates exactly; if a semantically close memory is already in view, update it with `correct` instead of adding a new one

## How to write high-quality handoffs

Five elements: **what changed / why / validation / risks / next steps**. The handoff is a document for the next session; the startup brief recalls it with priority.

### Template

```
What:  <one-sentence change>
Why:   <motivation / root cause>
Validated: <what ran / result>
Risk:  <hidden issues / boundaries>
Next:  <follow-ups>
```

### Good vs bad

**❌ Bad:** `done, should be fine`

**✅ Good:** `Fixed login 500: token expiry check now UTC. Why: old logic misjudged with local timezone. Validated: 200 concurrent logins, no 500. Risk: old clients cache expiry — needs assessment. Next: check refresh token flow.`

## How to reduce recall noise

| Practice | Explanation |
|------|------|
| Specific queries | `login 500 root cause` beats `login` |
| Noun phrases | `PostgreSQL connection pool config` beats "what database did we decide on again"; keep key names (people/projects/technologies/files) |
| Right scope | Don't put project info at tenant level; in agent integration scope is automatic |
| Correct stale info promptly | Don't let old and new coexist |
| Don't write low-quality memories | Source-level denoising is most effective |
| Use `--profile compact` | Compact results for agents |
| Report noise phrases | `hmg noise-feedback "some noise phrase"` teaches HMG to down-weight it |

```bash
# Repeated noisy results? Report them
hmg noise-feedback "npm install succeeded"   # down-weight this phrase in retrieval
```

## Dangerous operations: be careful

Daily use is low-risk — only three things deserve attention:

- **Credentials never go into memory**: API keys, passwords, connection strings belong in `hmg secret store`. Written by mistake? Immediately `hmg govern <atom-id> --action tombstone --destroy-payload`.
- **`tombstone` / `seal` are irreversible**: confirm the atom first (`hmg history <atom-id>`). Just want to hide it temporarily? Use `quarantine` (recoverable).
- **Never commit the store to Git**: the store directory contains indexes and binary data — add it to `.gitignore`; back up by copying the directory.

---

Next: [Integration](integration.md)
