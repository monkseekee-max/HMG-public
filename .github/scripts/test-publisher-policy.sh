#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly workflow="${script_dir}/../workflows/publish-promoted-release.yml"
readonly publisher="${script_dir}/publish-promoted-release.sh"

readonly forbidden_literals=(
  '--clob''ber'
  '--cleanup-''tag'
  'gh release ''delete'
  "hmg-public-stage-\${"
  'HMG-Provenance-''Signature:'
  '.github/provenance''/hmg-public-promotion-ed25519.pub'
  "git/refs/tags/\${source_tag}"
  'X-GitHub-Api-Version: 2022-''11-28'
)
for forbidden in "${forbidden_literals[@]}"; do
  if grep -Fq -- "${forbidden}" "${workflow}" "${publisher}"; then
    echo "Forbidden publisher policy literal found: ${forbidden}" >&2
    exit 1
  fi
done

readonly required_literals=(
  'name: hmg-public-release'
  'PROMOTION_WORKTREE:'
  'HMG-Source-Repository'
  'HMG-Source-Tag'
  'HMG-Source-SHA'
  'HMG-Workflow-Run'
  'HMG-Asset-Set-SHA256'
  'HMG-Candidate-Tree'
  'HMG-Provenance-Key-ID'
  'HMG-Provenance-Signature-Ed25519'
  'hmg_trailer_count='
  "hmg-public-staging-\${source_tag}-\${source_sha}"
  'expected_key_fingerprint='
  "candidate-tree=\${candidate_tree}"
  'immutable == true'
  'make_latest=true'
  'delete_captured_starter_assets'
  "releases/assets/\${starter_id}"
  "git/refs/tags/\${staging_tag}"
)
for required in "${required_literals[@]}"; do
  if ! grep -Fq -- "${required}" "${workflow}" "${publisher}"; then
    echo "Required publisher policy literal is missing: ${required}" >&2
    exit 1
  fi
done

echo 'publish-promoted-release static policy checks passed'
