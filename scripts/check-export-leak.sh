#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check-export-leak.sh — Public repo leak detector
#
# Run from HMG-public repo root.
# All checks must PASS before public release.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PASS=0
FAIL=0

TEXT_PATHS=(
  '*.rs' '*.ts' '*.py' '*.json' '*.yaml' '*.yml' '*.md' '*.sh' '*.html' '*.toml'
)

print_matches() {
  local matches="$1"
  local count=0
  local line
  while IFS= read -r line; do
    echo "     $line"
    count=$((count + 1))
    if [ "$count" -ge 10 ]; then
      break
    fi
  done <<<"$matches"
}

check_text() {
  local name="$1"; shift
  local pattern="$1"; shift
  local exclude="${1:-}"

  # Search tracked text files only. Build output and local dependency trees are
  # intentionally ignored unless somebody accidentally commits them.
  local matches
  local skip='(^|/)scripts/check-export-leak\.sh:|ADR-PUBLIC-RELEASE-HARDENING'
  if [ -n "$exclude" ]; then
    skip="${skip}|${exclude}"
  fi
  matches=$(git grep -n -I -E -e "$pattern" -- "${TEXT_PATHS[@]}" 2>/dev/null \
    | grep -vE "$skip" || true)

  if [ -z "$matches" ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $name"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $name"
    print_matches "$matches"
  fi
}

check_tracked_paths() {
  local name="$1"
  local pattern="$2"
  local matches
  matches=$(git ls-files | grep -E "$pattern" || true)

  if [ -z "$matches" ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $name"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $name"
    print_matches "$matches"
  fi
}

check_absent() {
  local name="$1"
  local path="$2"
  if [ ! -e "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $name"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $name — file exists: $path"
  fi
}

echo "=== HMG-public Export Leak Check ==="
echo ""

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ BLOCKED — run this gate from a Git worktree"
  exit 2
fi

# P1: No internal ADR files
echo "--- P1: Internal ADR files ---"
check_absent "No docs/adr/ directory" "docs/adr"
check_absent "No adr-classification.md" "docs/md/adr-classification.md"

# P2: No internal module/crate names
echo ""
echo "--- P2: Internal module names ---"
check_text "No private crate references" "hmg-core|hmg-llm|crates/hmg-"
check_text "No MemoryAtom type" "MemoryAtom"
check_text "No ContentEnvelope" "ContentEnvelope"
check_text "No Kant taxonomy" "Kant.*(CategoryCoord|taxonomy|enum)"
check_text "No CategoryCoord" "CategoryCoord"
check_text "No AgentQueryResultView" "AgentQueryResultView"

# P3: No internal storage engine names
echo ""
echo "--- P3: Internal storage/algorithm names ---"
check_text "No private storage implementation" "[Ff]jall|noise_gate|fingerprint_index"
check_text "No private index implementation" "semantic[ _-]?shard|shard[ _-]?manifest|HNSW|posting[ _-]?list"
check_text "No private write sequencing" "write-ahead|WAL recovery|commit_sequence|write[ _-]serialization"

# P4: No internal daemon name
echo ""
echo "--- P4: Internal process names ---"
check_text "No hmg-local-daemon" "hmg-local-daemon"

# P5: No consolidation algorithm names
echo ""
echo "--- P5: Internal algorithm names ---"
check_text "No private recall symbols" "one_shot_recall_engine|canonical_(ingest|marker)|recall_router|answer_materializer|intent_(embed|prototypes)|topic_key|fusion_weight|adaptive_recall"
check_text "No private ingest symbols" "memorize_admission|memorize_pipeline|domain_lens_(compiler|enhance)"
check_text "No private consolidation symbols" "biomimetic|consolidation_runtime|observation_scoring|episode_planner|promotion_scoring|consolidation.*architecture"
check_text "No proprietary internals prose" "proprietary.*internals"

# P6: No Private ADR inventory
echo ""
echo "--- P6: Private ADR inventory ---"
check_text "No Private ADR count" "Private.*11"
check_text "No Private ADR list" "\\*\\*Private\\*\\*.*Reveals"
check_text "No private monorepo references" "private monorepo"

# P7: No generated build artifacts in the published tree
echo ""
echo "--- P7: Generated build artifacts ---"
check_tracked_paths "No tracked build artifacts" '(^|/)(target|node_modules|__pycache__|dist|[^/]+\.egg-info)(/|$)|(^|/)[^/]+\.pyc$'

# P8: No credentials, internal endpoints, or developer-local paths
echo ""
echo "--- P8: Secrets and local-only references ---"
check_text "No private keys or live token shapes" "BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}"
check_text "No internal service addresses" "internal\\.hmg\\.com"
check_text "No developer-local source roots" "(/home|/Users)/[^/]+/(Documents|Projects|src)/"

echo ""
echo "=== Results: $PASS PASS, $FAIL FAIL ==="

if [ "$FAIL" -gt 0 ]; then
  echo "❌ BLOCKED — fix leaks before release"
  exit 1
else
  echo "✅ ALL CLEAR — safe for public release"
  exit 0
fi
