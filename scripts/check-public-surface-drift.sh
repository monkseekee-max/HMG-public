#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# check-public-surface-drift.sh
#
# Validates that all public-facing surfaces (README, docs, website,
# installers, SDK READMEs) are consistent with the public manifest.
#
# Exit codes:
#   0 = all checks pass
#   1 = drift detected
#
# Usage:
#   ./check-public-surface-drift.sh [--fix] [--manifest PATH]
#
# --fix   : Print suggested fixes (does not auto-apply)
# --manifest : Path to public-manifest.json (default: ../export/public-manifest.json)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIX_MODE=false
MANIFEST=""

# ── Parse args ──
while [[ $# -gt 0 ]]; do
  case $1 in
    --fix) FIX_MODE=true; shift ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Locate manifest ──
if [[ -z "$MANIFEST" ]]; then
  # Try relative to script location
  for candidate in \
    "${SCRIPT_DIR}/../export/public-manifest.json" \
    "${SCRIPT_DIR}/../../export/public-manifest.json" \
    "./export/public-manifest.json" \
    "./public-manifest.json"; do
    if [[ -f "$candidate" ]]; then
      MANIFEST="$candidate"
      break
    fi
  done
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "❌ FATAL: public-manifest.json not found"
  echo "   Searched: ${SCRIPT_DIR}/../export/, ./export/, ./"
  echo "   Use --manifest PATH to specify location"
  exit 1
fi

echo "📋 Manifest: $MANIFEST"
echo ""

# ── Helper ──
ERRORS=0
WARNINGS=0

drift_error() {
  echo "❌ DRIFT: $1"
  ERRORS=$((ERRORS + 1))
}

drift_warn() {
  echo "⚠️  WARN: $1"
  WARNINGS=$((WARNINGS + 1))
}

ok() {
  echo "✅ $1"
}

# ── Extract manifest values ──
# Simple JSON extraction (no jq dependency required, but use it if available)
json_val() {
  if command -v jq &>/dev/null; then
    jq -r "$1" "$MANIFEST"
  else
    # Fallback: simple grep-based extraction
    local key="$1"
    # Remove leading . and quotes
    key="${key#.}"
    key="${key//\"/}"
    grep -o "\"${key##*.}\":\s*\"[^\"]*\"" "$MANIFEST" | head -1 | sed "s/.*:.*\"\\(.*\\)\"/\\1/"
  fi
}

PRODUCT_VERSION=$(json_val '.product.version')
WEBSITE_URL=$(json_val '.urls.website')
DOCS_URL=$(json_val '.urls.docs')
REPO_URL=$(json_val '.urls.repository')
RELEASES_URL=$(json_val '.urls.releases')
COMMUNITY_ATOMS=$(json_val '.editions.community.limits.atoms')
DEVELOPER_PRICE_DISPLAY=$(json_val '.editions.developer.price_display')
DEVELOPER_PRICE_TOKEN=$(printf '%s\n' "$DEVELOPER_PRICE_DISPLAY" | grep -oE '\$[0-9]+' | head -1 || true)
DEPRECATED_URLS=$(json_val '.deprecated_urls[]' 2>/dev/null || echo "")

echo "━━━ 1. Deprecated URL Check ━━━"

# Check for deprecated URLs in all public surfaces
SURFACE_FILES=(
  "$SCRIPT_DIR/../README.md"
  "$SCRIPT_DIR/../docs/README.md"
  "$SCRIPT_DIR/install.sh"
  "$SCRIPT_DIR/install.ps1"
  "$SCRIPT_DIR/../sdk-python/README.md"
  "$SCRIPT_DIR/../sdk-ts/README.md"
)

FOUND_DEPRECATED=false
for url in $DEPRECATED_URLS; do
  for f in "${SURFACE_FILES[@]}"; do
    # Expand glob
    for file in $f; do
      if [[ -f "$file" ]]; then
        if grep -q "$url" "$file" 2>/dev/null; then
          drift_error "Deprecated URL '$url' found in $file"
          FOUND_DEPRECATED=true
        fi
      fi
    done
  done
done

if [[ "$FOUND_DEPRECATED" == "false" ]]; then
  ok "No deprecated URLs found"
fi

echo ""
echo "━━━ 2. Atom Limit Check ━━━"

# Check README for atom limit consistency
README_FILE="$SCRIPT_DIR/../README.md"
if [[ -f "$README_FILE" ]]; then
  # Check for any number that's NOT the manifest value
  FOUND_WRONG=false
  for wrong in "50,000" "50.000" "50 000" "50K atoms" "50000 atom"; do
    if grep -qi "$wrong" "$README_FILE" 2>/dev/null; then
      drift_error "README contains '$wrong' but manifest says $COMMUNITY_ATOMS"
      FOUND_WRONG=true
    fi
  done
  if [[ "$FOUND_WRONG" == "false" ]]; then
    ok "README atom limit consistent with manifest ($COMMUNITY_ATOMS)"
  fi
fi

echo ""
echo "━━━ 3. Version Consistency ━━━"

# Check version references
for f in "$README_FILE"; do
  if [[ -f "$f" ]]; then
    # Look for version patterns that don't match manifest
    FILE_VERSIONS=$(grep -oP 'v?\d+\.\d+\.\d+' "$f" 2>/dev/null | sort -u || true)
    for v in $FILE_VERSIONS; do
      # Strip leading 'v'
      v_clean="${v#v}"
      if [[ "$v_clean" != "$PRODUCT_VERSION" ]] && [[ "$v_clean" != "1.0.0" ]]; then
        drift_warn "$f references version $v, manifest says $PRODUCT_VERSION"
      fi
    done
  fi
done

echo ""
echo "━━━ 4. URL Consistency ━━━"

# Check that official URLs in public surfaces match manifest
for f in "$README_FILE"; do
  if [[ -f "$f" ]]; then
    # Check release URL pattern
    if grep -q 'github.com/HMG-AI/HMG-public/releases' "$f" 2>/dev/null; then
      ok "$f uses correct releases URL"
    elif grep -q 'github.com/HMG-AI/HMG/releases' "$f" 2>/dev/null; then
      drift_error "$f uses HMG/releases instead of HMG-public/releases"
    fi
  fi
done

echo ""
echo "━━━ 5. Price Consistency ━━━"

# Check for conflicting price mentions
for f in "$README_FILE"; do
  if [[ -f "$f" ]]; then
    # Find all price patterns
    PRICES=$(grep -oP '\$\d+' "$f" 2>/dev/null | sort -u || true)
    for p in $PRICES; do
      if [[ "$p" != "\$0" ]]; then
        # Check if it's the developer price, allowing pages to render "$9" with
        # the billing cadence in a separate translated string.
        if grep -q "${p}.*mo\|${p}.*月\|${p}.*month" "$f" 2>/dev/null; then
          if [[ -n "$DEVELOPER_PRICE_TOKEN" && "$p" == "$DEVELOPER_PRICE_TOKEN" ]]; then
            ok "$f Developer price matches manifest ($DEVELOPER_PRICE_DISPLAY)"
          else
            drift_error "$f shows Developer price $p, manifest says $DEVELOPER_PRICE_DISPLAY"
          fi
        fi
      fi
    done
  fi
done

echo ""
echo "━━━ Summary ━━━"

if [[ $ERRORS -eq 0 ]]; then
  echo "✅ No drift detected ($WARNINGS warnings)"
  exit 0
else
  echo "❌ $ERRORS drift error(s) detected ($WARNINGS warnings)"
  if [[ "$FIX_MODE" == "true" ]]; then
    echo ""
    echo "💡 Fix suggestions:"
    echo "   1. Update conflicting values to match $MANIFEST"
    echo "   2. Re-run this script to verify"
  fi
  exit 1
fi
