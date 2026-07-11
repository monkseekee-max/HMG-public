#!/usr/bin/env bash
# check-export-leak.sh — canonical public-export leak and boundary policy.
# This exact implementation ships in HMG-public; the monorepo wrapper invokes it
# against export/ so preflight and target checks cannot drift independently.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK_DIR="${REPO_ROOT}"
OUTPUT_MODE="text"

while (($# > 0)); do
  case "$1" in
    --dir=*)
      CHECK_DIR="${1#--dir=}"
      shift
      ;;
    --dir)
      (($# >= 2)) || { echo "--dir requires a path" >&2; exit 2; }
      CHECK_DIR="$2"
      shift 2
      ;;
    --json)
      OUTPUT_MODE="json"
      shift
      ;;
    --help|-h)
      echo "Usage: bash scripts/check-export-leak.sh [--dir DIR] [--json]"
      echo "Checks a prepared public tree for secrets, private implementation details, and unsafe files."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "${CHECK_DIR}" ]]; then
  echo "[leak-check] directory not found: ${CHECK_DIR}" >&2
  exit 2
fi
CHECK_DIR="$(cd "${CHECK_DIR}" && pwd)"

TRACKED_MODE=false
if git -C "${CHECK_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED_MODE=true
fi

TOTAL_CHECKS=0
PASS_COUNT=0
FAIL_COUNT=0
FAIL_MESSAGES=()
TEXT_PATHS=(
  '*.rs' '*.ts' '*.py' '*.json' '*.yaml' '*.yml' '*.md' '*.sh' '*.html' '*.toml'
)

info() {
  if [[ "${OUTPUT_MODE}" == "text" ]]; then
    printf '[leak-check] %s\n' "$*"
  fi
}

pass() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  info "PASS: $1"
}

fail() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_MESSAGES+=("$1")
  if [[ "${OUTPUT_MODE}" == "text" ]]; then
    printf '[leak-check] FAIL: %b\n' "$1" >&2
  fi
}

text_matches() {
  local pattern="$1"
  local exclude="${2:-}"
  local skip='(^|/)scripts/check-export-leak\.sh:|ADR-PUBLIC-RELEASE-HARDENING'
  if [[ -n "${exclude}" ]]; then
    skip="${skip}|${exclude}"
  fi

  if [[ "${TRACKED_MODE}" == "true" ]]; then
    git -C "${CHECK_DIR}" grep -n -I -E -e "${pattern}" -- "${TEXT_PATHS[@]}" \
      2>/dev/null | grep -vE "${skip}" || true
  else
    grep -rnE "${pattern}" "${CHECK_DIR}" \
      --include='*.rs' --include='*.ts' --include='*.py' \
      --include='*.json' --include='*.yaml' --include='*.yml' \
      --include='*.md' --include='*.sh' --include='*.html' \
      --include='*.toml' --exclude='check-export-leak.sh' \
      2>/dev/null | grep -vE "${skip}" || true
  fi
}

check_text() {
  local name="$1"
  local pattern="$2"
  local exclude="${3:-}"
  local matches
  matches="$(text_matches "${pattern}" "${exclude}")"
  if [[ -n "${matches}" ]]; then
    fail "${name}:\n${matches}"
  else
    pass "${name}"
  fi
}

tracked_paths() {
  if [[ "${TRACKED_MODE}" == "true" ]]; then
    git -C "${CHECK_DIR}" ls-files
  else
    find "${CHECK_DIR}" -path '*/.git' -prune -o -print \
      | sed "s#^${CHECK_DIR}/##"
  fi
}

check_paths() {
  local name="$1"
  local pattern="$2"
  local matches
  matches="$(tracked_paths | grep -E "${pattern}" || true)"
  if [[ -n "${matches}" ]]; then
    fail "${name}:\n${matches}"
  else
    pass "${name}"
  fi
}

check_absent() {
  local name="$1"
  local path="$2"
  if [[ -e "${CHECK_DIR}/${path}" ]]; then
    fail "${name}:\n${path}"
  else
    pass "${name}"
  fi
}

info "Checking ${CHECK_DIR}"

check_absent "No docs/adr directory" "docs/adr"
check_absent "No ADR classification inventory" "docs/md/adr-classification.md"

check_text "No private crate references" 'hmg-core|hmg-llm|crates/hmg-'
check_text "No private memory model types" 'MemoryAtom|ContentEnvelope|CategoryCoord|AgentQueryResultView'
check_text "No private taxonomy details" 'Kant.*(CategoryCoord|taxonomy|enum)'
check_text "No private storage implementation" '[Ff]jall|TieredStore|FjallStore|noise_gate|fingerprint_index'
check_text "No private index implementation" 'semantic[ _-]?shard|shard[ _-]?manifest|HNSW|posting[ _-]?list'
check_text "No private write sequencing" 'write-ahead|WAL recovery|commit_sequence|write[ _-]serialization'
check_text "No private daemon name" 'hmg-local-daemon'
check_text "No private recall symbols" 'one_shot_recall_engine|canonical_(ingest|marker)|recall_router|answer_materializer|intent_(embed|prototypes)|topic_key|fusion_weight|adaptive_recall'
check_text "No private ingest symbols" 'memorize_admission|memorize_pipeline|domain_lens_(compiler|enhance)'
check_text "No private consolidation symbols" 'biomimetic|consolidation_runtime|observation_scoring|episode_planner|promotion_scoring|consolidation.*architecture'
check_text "No proprietary internals prose" 'proprietary.*internals'
check_text "No private ADR inventory" 'Private.*11|\*\*Private\*\*.*Reveals|private monorepo'

check_paths \
  "No generated build artifacts in the published tree" \
  '(^|/)(target|node_modules|__pycache__|dist|[^/]+\.egg-info)(/|$)|(^|/)[^/]+\.pyc$'

check_text \
  "No credential-like material" \
  'BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16}'
check_text "No internal service addresses" 'internal\.hmg\.com'
check_text "No developer-local source roots" '(/home|/Users)/[^/]+/(Documents|Projects|src)/'
check_text \
  "No unreviewed GPL/AGPL references" \
  '\b(AGPL|GPL)(-[0-9.]+)?\b' \
  'NOT GPL|not GPL|dual license|is licensed'
email_pattern='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
email_allow='@(example|test|localhost|noreply)|users\.noreply|@hmg\.ai|@apache\.org|@github\.com|@hmg1ai\.com|@hmg2ai\.com'
if [[ "${TRACKED_MODE}" == "true" ]]; then
  email_hits="$(
    git -C "${CHECK_DIR}" grep -n -I -E -e "${email_pattern}" -- \
      '*.rs' '*.toml' '*.ts' '*.py' '*.sh' 2>/dev/null \
      | grep -vE '(^|/)scripts/check-export-leak\.sh:|ADR-PUBLIC-RELEASE-HARDENING' \
      | grep -vE "${email_allow}" || true
  )"
else
  email_hits="$(
    grep -rnE "${email_pattern}" "${CHECK_DIR}" \
      --include='*.rs' --include='*.toml' --include='*.ts' \
      --include='*.py' --include='*.sh' --exclude='check-export-leak.sh' \
      2>/dev/null | grep -vE "${email_allow}" || true
  )"
fi
if [[ -n "${email_hits}" ]]; then
  fail "Possible customer or personal email addresses found:\n${email_hits}"
else
  pass "No customer or personal email addresses"
fi

if [[ "${TRACKED_MODE}" == "true" ]]; then
  symlinks="$(
    git -C "${CHECK_DIR}" ls-files -s \
      | awk '$1 == "120000" {sub(/^[^\t]*\t/, ""); print}'
  )"
else
  symlinks="$(find "${CHECK_DIR}" -path '*/.git' -prune -o -type l -print)"
fi
if [[ -n "${symlinks}" ]]; then
  fail "Symbolic links found:\n${symlinks}"
else
  pass "No symbolic links"
fi

oversized_files="$(
  if [[ "${TRACKED_MODE}" == "true" ]]; then
    while IFS= read -r -d '' path; do
      if [[ -f "${CHECK_DIR}/${path}" ]] && \
          (( $(stat -c '%s' "${CHECK_DIR}/${path}") > 20 * 1024 * 1024 )); then
        printf '%s\n' "${path}"
      fi
    done < <(git -C "${CHECK_DIR}" ls-files -z)
  else
    find "${CHECK_DIR}" -path '*/.git' -prune -o -type f -size +20M -print
  fi
)"
if [[ -n "${oversized_files}" ]]; then
  fail "Files larger than 20 MiB found:\n${oversized_files}"
else
  pass "No oversized files"
fi

if [[ "${OUTPUT_MODE}" == "json" ]]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required for --json" >&2; exit 2; }
  failures_json='[]'
  if ((${#FAIL_MESSAGES[@]} > 0)); then
    failures_json="$(printf '%s\n' "${FAIL_MESSAGES[@]}" | jq -R . | jq -s .)"
  fi
  jq -n \
    --argjson total "${TOTAL_CHECKS}" \
    --argjson passed "${PASS_COUNT}" \
    --argjson failed "${FAIL_COUNT}" \
    --argjson failures "${failures_json}" \
    '{total_checks: $total, passed: $passed, failed: $failed, failures: $failures, status: (if $failed == 0 then "passed" else "failed" end)}'
else
  printf '[leak-check] %s/%s checks passed\n' "${PASS_COUNT}" "${TOTAL_CHECKS}"
fi

if ((FAIL_COUNT > 0)); then
  exit 1
fi
