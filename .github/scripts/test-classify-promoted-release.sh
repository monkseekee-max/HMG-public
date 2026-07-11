#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly classifier="${script_dir}/classify-promoted-release.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

git init --bare --initial-branch=main "${fixture_root}/origin.git" >/dev/null
git clone --quiet "${fixture_root}/origin.git" "${fixture_root}/work" \
  2> "${fixture_root}/clone.log"
cd "${fixture_root}/work"
git config user.name 'HMG Publisher Fixture'
git config user.email 'publisher-fixture@example.com'

run_classifier() {
  local commit_sha="$1"
  local output_file="$2"
  local summary_file="$3"
  local event_name="${4:-push}"
  local requested_sha=''
  if [[ "${event_name}" == 'workflow_dispatch' ]]; then
    requested_sha="${commit_sha}"
  fi
  GITHUB_REPOSITORY='HMG-AI/HMG-public' \
  GITHUB_REF='refs/heads/main' \
  EVENT_NAME="${event_name}" \
  EVENT_SHA="${commit_sha}" \
  REQUESTED_PROMOTION_SHA="${requested_sha}" \
  RUNNER_TEMP="${fixture_root}/runner" \
  GITHUB_OUTPUT="${output_file}" \
  GITHUB_STEP_SUMMARY="${summary_file}" \
    bash "${classifier}"
}

mkdir -p "${fixture_root}/runner"
git commit --allow-empty --no-gpg-sign -m 'docs: ordinary protected-main update' \
  >/dev/null
git push --quiet origin HEAD:main
ordinary_sha="$(git rev-parse HEAD)"
run_classifier \
  "${ordinary_sha}" "${fixture_root}/ordinary.out" "${fixture_root}/ordinary.summary"
grep -Fxq 'publish=false' "${fixture_root}/ordinary.out"
grep -Fxq "promotion_commit=${ordinary_sha}" "${fixture_root}/ordinary.out"

git commit --allow-empty --no-gpg-sign \
  -m 'docs: fixture unknown HMG trailer' \
  -m 'HMG-Untrusted-Extension: must-fail-closed' \
  >/dev/null
git push --quiet origin HEAD:main
unknown_sha="$(git rev-parse HEAD)"
if run_classifier \
    "${unknown_sha}" "${fixture_root}/unknown.out" "${fixture_root}/unknown.summary" \
    2> "${fixture_root}/unknown.err"; then
  echo 'An unknown HMG trailer unexpectedly passed as an ordinary no-op.' >&2
  exit 1
fi

git commit --allow-empty --no-gpg-sign \
  -m 'chore(public): fixture complete promotion' \
  -m $'HMG-Source-Repository: HMG-AI/HMG\nHMG-Source-Tag: v9.8.7\nHMG-Source-SHA: 1111111111111111111111111111111111111111\nHMG-Workflow-Run: https://github.com/HMG-AI/HMG/actions/runs/123\nHMG-Asset-Set-SHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nHMG-Candidate-Tree: sha1:2222222222222222222222222222222222222222\nHMG-Provenance-Key-ID: ed25519-spki-sha256-fixture\nHMG-Provenance-Signature-Ed25519: fixture' \
  >/dev/null
git push --quiet origin HEAD:main
complete_sha="$(git rev-parse HEAD)"
run_classifier \
  "${complete_sha}" "${fixture_root}/complete.out" "${fixture_root}/complete.summary"
grep -Fxq 'publish=true' "${fixture_root}/complete.out"
grep -Fxq "promotion_commit=${complete_sha}" "${fixture_root}/complete.out"
run_classifier \
  "${complete_sha}" "${fixture_root}/dispatch.out" "${fixture_root}/dispatch.summary" \
  workflow_dispatch
grep -Fxq 'publish=true' "${fixture_root}/dispatch.out"

if GITHUB_REPOSITORY='HMG-AI/HMG-public' \
    GITHUB_REF='refs/heads/main' \
    EVENT_NAME='workflow_dispatch' \
    EVENT_SHA="${complete_sha}" \
    REQUESTED_PROMOTION_SHA='deadbeef' \
    RUNNER_TEMP="${fixture_root}/runner" \
    GITHUB_OUTPUT="${fixture_root}/short-dispatch.out" \
    GITHUB_STEP_SUMMARY="${fixture_root}/short-dispatch.summary" \
      bash "${classifier}" 2> "${fixture_root}/short-dispatch.err"; then
  echo 'A short workflow_dispatch promotion SHA unexpectedly passed.' >&2
  exit 1
fi

git commit --allow-empty --no-gpg-sign \
  -m 'chore(public): fixture partial promotion' \
  -m $'HMG-Source-Tag: v9.8.8\nHMG-Source-SHA: 3333333333333333333333333333333333333333' \
  >/dev/null
git push --quiet origin HEAD:main
partial_sha="$(git rev-parse HEAD)"
if run_classifier \
    "${partial_sha}" "${fixture_root}/partial.out" "${fixture_root}/partial.summary" \
    2> "${fixture_root}/partial.err"; then
  echo 'Partial promotion trailers unexpectedly passed classification.' >&2
  exit 1
fi

echo 'classify-promoted-release fixtures passed'
