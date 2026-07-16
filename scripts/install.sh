#!/usr/bin/env sh
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — One-command installer for HMG Community Edition
#
# Usage:
#   curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
#   curl -fsSL ... | sh -s -- v0.9.2
#   curl -fsSL ... | sh -s -- --prefix ~/bin
#
# Download sources (tried in order):
#   1. GitHub Releases (default, canonical)
#   2. Official website mirror — hmg1ai.com (international CDN)
#   3. Official website mirror — hmg2ai.com (domestic fallback)
# ─────────────────────────────────────────────────────────────────────────────
set -eu

HMG_REPO="HMG-AI/HMG-public"
HMG_GITHUB="https://github.com/${HMG_REPO}"
RELEASE_BASE="${HMG_GITHUB}/releases/latest/download"
# Official mirrors tried after GitHub. hmg1ai.com first (international CDN),
# hmg2ai.com last (domestic fallback). See ADR 2026-06-13 (international site
# download service). Each mirror that returns HTML instead of a tarball is
# rejected by install_from_url, so the chain stays robust even before the
# hmg1ai.com download service (R2) is live.
MIRROR_BASES="https://hmg1ai.com/releases/latest/download https://hmg2ai.com/releases/latest/download"
BIN_DIR="${HMG_INSTALL_DIR:-$HOME/.local/bin}"
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t hmg-install)"
REQUESTED_VERSION=""
DRY_RUN=false

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

log() { printf '%s\n' "$*"; }
err() { log "ERROR: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1"; }

# ── Parse args ─────────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)  BIN_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      log "HMG Community Edition Installer"
      log ""
      log "Usage: curl -fsSL ${HMG_GITHUB}/releases/latest/download/install.sh | sh -s -- [options] [version]"
      log ""
      log "Options:"
      log "  [version]     Version to install (default: latest)"
      log "  --prefix DIR  Installation directory (default: \$HOME/.local/bin)"
      log "  --dry-run     Show what would happen without installing"
      log "  -h, --help    Show this help"
      exit 0
      ;;
    v*) REQUESTED_VERSION="${1#v}"; shift ;;
    *) err "Unknown option: $1" ;;
  esac
done

need_cmd curl
need_cmd tar

# ── Detect platform ────────────────────────────────────────────────────────
target_triple() {
  os="$(uname -s 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$os:$arch" in
    Linux:x86_64|Linux:amd64)  echo "x86_64-unknown-linux-gnu" ;;
    Linux:aarch64|Linux:arm64) echo "aarch64-unknown-linux-gnu" ;;
    Darwin:x86_64)             echo "x86_64-apple-darwin" ;;
    Darwin:arm64|Darwin:aarch64) echo "aarch64-apple-darwin" ;;
    *) echo "" ;;
  esac
}

# ── Resolve version ────────────────────────────────────────────────────────
extract_json_version() {
  sed -n 's/.*"\(tag\|version\)"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\2/p' | head -1
}

resolve_latest_version() {
  for base in "$RELEASE_BASE" $MIRROR_BASES; do
    latest="$(curl -fsSL "$base/version.json" 2>/dev/null | extract_json_version)" || true
    if [ -n "$latest" ]; then
      printf '%s\n' "$latest"
      return 0
    fi
  done

  curl -fsSL "https://api.github.com/repos/${HMG_REPO}/releases/latest" 2>/dev/null \
    | grep '"tag_name"' \
    | head -1 \
    | sed 's/.*"v\([^"]*\)".*/\1/'
}

resolve_version() {
  if [ -n "$REQUESTED_VERSION" ]; then
    VERSION="$REQUESTED_VERSION"
  else
    log "Detecting latest version..."
    latest="$(resolve_latest_version)" || true
    if [ -z "$latest" ]; then
      err "Cannot detect latest version. Specify explicitly: sh -s -- v1.6.6"
    fi
    VERSION="$latest"
  fi
  log "Installing HMG v${VERSION} (Community Edition)"
}

# ── Download and install ───────────────────────────────────────────────────
install_from_url() {
  local url="$1"
  local archive="$2"
  local pkg_dir="$TMP_DIR/package"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"

  log "  Downloading: $url"
  if ! curl -fL --retry 3 --retry-delay 1 --connect-timeout 20 "$url" -o "$TMP_DIR/$archive" 2>/dev/null; then
    return 1
  fi

  if ! tar -xzf "$TMP_DIR/$archive" -C "$pkg_dir" 2>/dev/null; then
    log "  Downloaded file is not a valid tar.gz"
    return 1
  fi

  # Find binaries (may be in a subdirectory from tar packaging)
  for bin in hmg hmg-server hmg-hook-worker; do
    found="$(find "$pkg_dir" -name "$bin" -type f | head -1)"
    if [ -z "$found" ]; then
      log "  Package missing binary: $bin"
      return 1
    fi
    if [ "$found" != "$pkg_dir/$bin" ]; then
      mv "$found" "$pkg_dir/$bin"
    fi
  done

  if [ "$DRY_RUN" = true ]; then
    log "  (dry-run) Would install hmg, hmg-server, hmg-hook-worker to $BIN_DIR"
    return 0
  fi

  mkdir -p "$BIN_DIR"
  for bin in hmg hmg-server hmg-hook-worker; do
    install -m 0755 "$pkg_dir/$bin" "$BIN_DIR/$bin"
  done
  return 0
}

do_install() {
  local target
  target="$(target_triple)"
  if [ -z "$target" ]; then
    err "Unsupported platform. Prebuilt binaries available for Linux (x64/ARM64) and macOS (Intel/Apple Silicon)."
  fi

  local archive="hmg-${VERSION}-${target}.tar.gz"
  log "Platform: $target"

  # Source 1: GitHub's current release. Trying the latest-release URL first
  # also supports immutable-release recovery tags whose asset filenames keep
  # the product version (for example hmg-1.7.6-...). Older explicitly
  # requested versions naturally miss here and fall through to their tag.
  if install_from_url "${RELEASE_BASE}/${archive}" "$archive"; then
    return 0
  fi

  # Source 2: Exact GitHub version tag.
  local gh_url="${HMG_GITHUB}/releases/download/v${VERSION}/${archive}"
  if install_from_url "$gh_url" "$archive"; then
    return 0
  fi

  # Source 3..N: Official website mirrors (hmg1ai.com CDN, then hmg2ai.com fallback)
  for base in $MIRROR_BASES; do
    if install_from_url "${base}/${archive}" "$archive"; then
      return 0
    fi
  done

  err "Download failed from all sources.

Platform $target may not yet have a prebuilt binary.
Currently available: Linux x64/ARM64, macOS Intel/Apple Silicon, Windows x64.

Windows users: use install.ps1 instead:
  irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex

Build from source: https://github.com/HMG-AI/HMG-public
Request a platform: https://github.com/HMG-AI/HMG-public/issues"
}

# ── Persist PATH in shell config ──────────────────────────────────────────
persist_path_if_needed() {
  # Check if BIN_DIR is already in persistent PATH (login profile)
  # by checking common shell config files
  local already_persisted=false
  local rc_file=""

  # Determine which rc file to use
  if [ -n "${ZSH_VERSION:-}" ]; then
    rc_file="$HOME/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ]; then
    # Prefer .bashrc for interactive, .profile for login
    if [ -f "$HOME/.bashrc" ]; then
      rc_file="$HOME/.bashrc"
    else
      rc_file="$HOME/.profile"
    fi
  else
    rc_file="$HOME/.profile"
  fi

  # Check if already in the rc file
  if [ -f "$rc_file" ] && grep -qF "$BIN_DIR" "$rc_file" 2>/dev/null; then
    already_persisted=true
  fi

  # Also check .profile as fallback for all shells
  if [ -f "$HOME/.profile" ] && grep -qF "$BIN_DIR" "$HOME/.profile" 2>/dev/null; then
    already_persisted=true
  fi

  if [ "$already_persisted" = true ]; then
    return 0
  fi

  # Add export line to the rc file
  log "  Adding $BIN_DIR to $rc_file"
  printf '\n# HMG\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$rc_file"
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
  resolve_version
  do_install

  if [ "$DRY_RUN" = true ]; then
    log ""
    log "(dry-run) Skipping PATH persistence and hmg setup."
    return 0
  fi

  # Ensure hmg is on PATH for this script and the user
  case ":${PATH}:" in
    *"${BIN_DIR}"*) ;;
    *) export PATH="${BIN_DIR}:${PATH}" ;;
  esac

  # Persist PATH in user shell config if not already there
  persist_path_if_needed

  log ""
  log "✅ HMG v${VERSION} installed to ${BIN_DIR}"

  # Auto-run hmg setup so the default store exists and the local daemon is ready.
  log ""
  log "Running hmg setup..."
  if command -v hmg >/dev/null 2>&1; then
    if hmg setup; then
      log "✅ hmg setup completed."
    else
      log "⚠ hmg setup exited with error (non-fatal). Run manually: hmg setup"
    fi
  else
    log "⚠ hmg not on PATH yet. Run manually after adding to PATH:"
    log "  export PATH=\"${BIN_DIR}:\$PATH\""
    log "  hmg setup"
  fi

  log ""
  log "Quick commands:"
  log "  hmg doctor           # Check system readiness"
  log "  hmg daemon start     # Start background daemon"
  log "  hmg tui              # Open terminal UI"
  log ""
  log "Slow/blocked model downloads (mainland China)?"
  log "  HMG downloads a small embedding model from HuggingFace on first use."
  log "  If that is slow or blocked, set a mirror first, then start the daemon:"
  log "    export HF_ENDPOINT=https://hf-mirror.com"
  log "    HMG_EMBEDDING_ENDPOINT=https://hf-mirror.com hmg model embedding download"
  log ""
  log "Update: hmg update"
  log "Docs:   https://hmg-ai.github.io/HMG-public/"
  log "Web:    https://hmg1ai.com/"
  log "GitHub: ${HMG_GITHUB}"
}

main
