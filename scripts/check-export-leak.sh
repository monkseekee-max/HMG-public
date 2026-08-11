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

TOTAL_CHECKS=0
PASS_COUNT=0
FAIL_COUNT=0
FAIL_MESSAGES=()

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

info "Checking ${CHECK_DIR}"

deny_regex='one_shot_recall_engine|canonical_ingest|canonical_marker|recall_router|answer_materializer|intent_embed|intent_prototypes|topic_key|noise_gate|fusion_weight|adaptive_recall|memorize_admission|memorize_pipeline|consolidation_runtime|observation_scoring|episode_planner|promotion_scoring|domain_lens_(compiler|enhance)|MemoryEngine|MemoryAtom|ContentEnvelope|CategoryCoord|Kant.*(CategoryCoord|taxonomy|enum)|AgentQueryResultView|TieredStore|FjallStore|[Ff]jall|fingerprint_index|semantic[ _-]?shard|shard[ _-]?manifest|HNSW|posting[ _-]?list|write-ahead|WAL recovery|commit_sequence|write[ _-]serialization|hmg-core|hmg-llm|crates/hmg-|hmg-local-daemon|biomimetic|consolidation.*architecture|proprietary.*internals|Private.*11|\*\*Private\*\*.*Reveals|private monorepo|internal\.hmg\.com|(/home|/Users)/[^/]+/(Documents|Projects|src)/'
deny_hits="$(grep -rnE "${deny_regex}" "${CHECK_DIR}" \
    --include='*.rs' --include='*.toml' --include='*.yaml' --include='*.yml' \
    --include='*.json' --include='*.ts' --include='*.py' --include='*.md' \
    --include='*.sh' --exclude='check-export-leak.sh' --exclude-dir='.git' \
    2>/dev/null || true)"
if [[ -n "${deny_hits}" ]]; then
    fail "Private implementation identifiers found:\n${deny_hits}"
else
    pass "No private implementation identifiers"
fi

secret_regex='sk-[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
secret_hits="$(grep -rnE "${secret_regex}" "${CHECK_DIR}" \
    --exclude='check-export-leak.sh' --exclude-dir='.git' 2>/dev/null || true)"
if [[ -n "${secret_hits}" ]]; then
    fail "Credential-like material found:\n${secret_hits}"
else
    pass "No credential-like material"
fi

forbidden_paths="$(
    find "${CHECK_DIR}" \
        -path "${CHECK_DIR}/.git" -prune -o \
        -path '*/crates/hmg-*' \
        -print 2>/dev/null || true
)"
if [[ -n "${forbidden_paths}" ]]; then
    fail "Internal-only paths found:\n${forbidden_paths}"
else
    pass "No internal-only paths"
fi

license_hits="$(grep -rnEi '\b(AGPL|GPL)(-[0-9.]+)?\b' "${CHECK_DIR}" \
    --include='*.toml' --include='*.rs' --include='*.md' \
    --exclude='check-export-leak.sh' --exclude-dir='.git' 2>/dev/null \
    | grep -vE 'NOT GPL|not GPL|dual license|is licensed' || true)"
if [[ -n "${license_hits}" ]]; then
    fail "GPL/AGPL references require license review:\n${license_hits}"
else
    pass "No unreviewed GPL/AGPL references"
fi

artifact_paths="$(find "${CHECK_DIR}" \
    -path "${CHECK_DIR}/.git" -prune -o \
    \( -type d \( -name target -o -name node_modules -o -name __pycache__ \
        -o -name dist -o -name '*.egg-info' \) -print -prune \) -o \
    \( -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name 'CACHEDIR.TAG' \) \
        -print \) 2>/dev/null || true)"
if [[ -n "${artifact_paths}" ]]; then
    fail "Generated build artifacts found:\n${artifact_paths}"
else
    pass "No generated build artifacts"
fi

email_hits="$(grep -rnE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${CHECK_DIR}" \
    --include='*.rs' --include='*.toml' --include='*.ts' --include='*.py' \
    --include='*.sh' --exclude='check-export-leak.sh' --exclude-dir='.git' \
    2>/dev/null \
    | grep -vE '@(example|test|localhost|noreply)|users\.noreply|@hmg\.ai|@apache\.org|@github\.com|@hmg1ai\.com|@hmg2ai\.com' \
    || true)"
if [[ -n "${email_hits}" ]]; then
    fail "Possible customer or personal email addresses found:\n${email_hits}"
else
    pass "No customer or personal email addresses"
fi

symlinks="$(find "${CHECK_DIR}" -path "${CHECK_DIR}/.git" -prune -o -type l -print)"
if [[ -n "${symlinks}" ]]; then
    fail "Symbolic links found:\n${symlinks}"
else
    pass "No symbolic links"
fi

oversized_files="$(find "${CHECK_DIR}" -path "${CHECK_DIR}/.git" -prune -o -type f -size +20M -print)"
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
