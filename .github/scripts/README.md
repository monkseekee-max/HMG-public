# Protected public release publisher

`publish-promoted-release.yml` is the only workflow allowed to turn a merged
public-export promotion into a final `v*.*.*` release. Ordinary `main` commits
without HMG promotion trailers are read-only no-ops.

The publisher requires exactly these signed trailers:

- `HMG-Source-Repository`
- `HMG-Source-Tag`
- `HMG-Source-SHA`
- `HMG-Workflow-Run`
- `HMG-Asset-Set-SHA256`
- `HMG-Candidate-Tree`
- `HMG-Provenance-Key-ID`
- `HMG-Provenance-Signature-Ed25519`

Any partial, duplicate, or unknown `HMG-*` trailer set fails closed.

The protected-main commit tree and all ten release assets are verified against
the Ed25519 statement before any repository write. Staging assets are read by
captured asset ID from the deterministic
`hmg-public-staging-${SOURCE_TAG}-${SOURCE_SHA}` draft/prerelease. The final tag
is created once as a lightweight tag at the merged promotion commit and is
never moved or deleted. A separate final draft is byte-for-byte rechecked,
published as latest, and required to report `immutable: true` before staging
cleanup is attempted.

Interrupted uploads in GitHub's `starter` state are repaired only by deleting
the captured incomplete asset ID after a trusted local copy has passed the
signed aggregate digest, then uploading that exact copy without clobbering.
Already-uploaded conflicting bytes are never deleted or overwritten.

Manual reconciliation requires a full protected-main `promotion_sha`. An exact
already-published immutable release is a read-only success, which makes retries
safe after staging cleanup.

Local checks:

```bash
bash -n .github/scripts/*.sh
shellcheck .github/scripts/*.sh
actionlint .github/workflows/publish-promoted-release.yml
bash .github/scripts/test-classify-promoted-release.sh
bash .github/scripts/test-publisher-policy.sh
```
