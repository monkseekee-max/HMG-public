#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

readonly expected_repository='HMG-AI/HMG-public'
readonly expected_ref='refs/heads/main'
readonly trailer_pattern='^HMG-(Source-Repository|Source-Tag|Source-SHA|Workflow-Run|Asset-Set-SHA256|Candidate-Tree|Provenance-Key-ID|Provenance-Signature-Ed25519):'

if [[ "${GITHUB_REPOSITORY:-}" != "${expected_repository}" || \
      "${GITHUB_REF:-}" != "${expected_ref}" ]]; then
  echo 'This publisher only accepts HMG-AI/HMG-public protected-main events.' >&2
  exit 2
fi

case "${EVENT_NAME:-}" in
  push)
    promotion_commit="${EVENT_SHA:-}"
    ;;
  workflow_dispatch)
    promotion_commit="${REQUESTED_PROMOTION_SHA:-}"
    ;;
  *)
    echo "Unsupported publisher event: ${EVENT_NAME:-missing}" >&2
    exit 2
    ;;
esac

if [[ ! "${promotion_commit}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'The promotion commit must be a full lowercase 40-character SHA.' >&2
  exit 2
fi
if [[ "${EVENT_NAME}" == 'push' && "${promotion_commit}" != "${EVENT_SHA}" ]]; then
  echo 'A push event may only classify its exact event SHA.' >&2
  exit 2
fi

git fetch --no-tags origin \
  '+refs/heads/main:refs/remotes/origin/main'
resolved_commit="$(git rev-parse --verify "${promotion_commit}^{commit}")"
if [[ "${resolved_commit}" != "${promotion_commit}" ]]; then
  echo 'The promotion SHA did not resolve to the exact requested commit.' >&2
  exit 2
fi
if ! git merge-base --is-ancestor \
    "${promotion_commit}" refs/remotes/origin/main; then
  echo 'The promotion commit is not reachable from protected main.' >&2
  exit 2
fi

trailer_file="${RUNNER_TEMP}/promotion-trailers.txt"
git show -s --format=%B "${promotion_commit}" \
  | git interpret-trailers --parse > "${trailer_file}"
recognized_count="$(grep -Ec "${trailer_pattern}" "${trailer_file}" || true)"
hmg_trailer_count="$(grep -Ec '^HMG-[A-Za-z0-9-]+:' "${trailer_file}" || true)"
if ((hmg_trailer_count == 0)); then
  {
    echo 'publish=false'
    echo "promotion_commit=${promotion_commit}"
  } >> "${GITHUB_OUTPUT}"
  {
    echo '### Promoted release publisher'
    echo
    echo "No HMG promotion trailers were present on ${promotion_commit}."
    echo 'No release was changed and no protected environment approval was requested.'
  } >> "${GITHUB_STEP_SUMMARY}"
  exit 0
fi

readonly trailer_keys=(
  HMG-Source-Repository
  HMG-Source-Tag
  HMG-Source-SHA
  HMG-Workflow-Run
  HMG-Asset-Set-SHA256
  HMG-Candidate-Tree
  HMG-Provenance-Key-ID
  HMG-Provenance-Signature-Ed25519
)
if ((recognized_count != ${#trailer_keys[@]} || \
      hmg_trailer_count != ${#trailer_keys[@]})); then
  echo 'Promotion commits must contain exactly the eight required HMG trailers.' >&2
  exit 2
fi
for trailer_key in "${trailer_keys[@]}"; do
  trailer_count="$(grep -Ec "^${trailer_key}:" "${trailer_file}" || true)"
  if ((trailer_count != 1)); then
    echo "Promotion commits require exactly one ${trailer_key} trailer." >&2
    exit 2
  fi
done

{
  echo 'publish=true'
  echo "promotion_commit=${promotion_commit}"
} >> "${GITHUB_OUTPUT}"
