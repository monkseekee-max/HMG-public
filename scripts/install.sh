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

HMG_REPO="${HMG_REPO:-HMG-AI/HMG-public}"
HMG_GITHUB="${HMG_GITHUB_URL:-https://github.com/${HMG_REPO}}"
RELEASE_BASE="${HMG_RELEASE_BASE_URL:-${HMG_GITHUB}/releases/latest/download}"
# Official mirrors tried after GitHub. hmg1ai.com first (international CDN),
# hmg2ai.com last (domestic fallback). See ADR 2026-06-13 (international site
# download service). Each mirror that returns HTML instead of a tarball is
# rejected by install_from_url, so the chain stays robust even before the
# hmg1ai.com download service (R2) is live.
MIRROR_BASES="${HMG_RELEASE_MIRROR_BASES-https://hmg1ai.com/releases/latest/download https://hmg2ai.com/releases/latest/download}"
BIN_DIR="${HMG_INSTALL_DIR:-$HOME/.local/bin}"
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t hmg-install)"
REQUESTED_VERSION=""
DRY_RUN=false
STAGED_DIR=""
BACKUP_DIR="$TMP_DIR/backup"
TARGET_STORE=""
OLD_INSTALL_PRESENT=false
OLD_DAEMON_WAS_RUNNING=false
OLD_DAEMON_STOPPED=false
REPLACEMENT_ATTEMPTED=false
INSTALL_COMMITTED=false
STORE_SETUP_STARTED=false
UPGRADE_BACKUP_FILE=""
UPGRADE_BACKUP_TMP=""
KEY_METADATA_BEFORE="$TMP_DIR/store-key-metadata.before"
ACTIVE_CHILD_PID=""

log() { printf '%s\n' "$*"; }
err() { log "ERROR: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1"; }

# Run an installer subprocess with a portable wall-clock bound. GNU timeout is
# not available by default on macOS, so keep this implementation POSIX-only.
run_bounded() {
  local timeout_secs="$1"
  shift
  "$@" &
  local child_pid=$!
  ACTIVE_CHILD_PID="$child_pid"
  local elapsed=0
  while kill -0 "$child_pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_secs" ]; then
      kill "$child_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
      ACTIVE_CHILD_PID=""
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if wait "$child_pid"; then
    ACTIVE_CHILD_PID=""
    return 0
  else
    local status=$?
    ACTIVE_CHILD_PID=""
    return "$status"
  fi
}

default_store_dir() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "${XDG_DATA_HOME}/hmg/stores/default"
  else
    printf '%s\n' "${HOME}/.local/share/hmg/stores/default"
  fi
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | sed 's/[[:space:]].*$//'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | sed 's/[[:space:]].*$//'
  else
    err "A SHA-256 tool is required (sha256sum or shasum)."
  fi
}

record_existing_store_key_metadata() {
  local output="$1"
  : >"$output"
  [ -d "$TARGET_STORE" ] || return 0
  find "$TARGET_STORE" -type f \
    \( -name storage.key -o -name server.key.json -o \
       -name approval.key -o -name observation.key \) -print \
    | LC_ALL=C sort \
    | while IFS= read -r key_path; do
        local relative size digest
        relative="${key_path#"$TARGET_STORE"/}"
        size="$(wc -c <"$key_path" | tr -d '[:space:]')"
        digest="$(sha256_file "$key_path")"
        printf '%s\t%s\t%s\n' "$relative" "$size" "$digest" >>"$output"
      done
}

verify_original_store_keys_unchanged() {
  [ -f "$KEY_METADATA_BEFORE" ] || return 0
  local after="$TMP_DIR/store-key-metadata.after"
  record_existing_store_key_metadata "$after"

  # Ignore keys first created by setup, but require every pre-existing key to
  # retain exactly the same relative path, byte size, and SHA-256 digest.
  local failed=false
  while IFS="$(printf '\t')" read -r relative expected_size expected_digest; do
    [ -n "$relative" ] || continue
    local current="$TARGET_STORE/$relative"
    if [ ! -f "$current" ]; then
      log "ERROR: Existing HMG key disappeared during installation: $relative" >&2
      failed=true
      continue
    fi
    local current_size current_digest
    current_size="$(wc -c <"$current" | tr -d '[:space:]')"
    current_digest="$(sha256_file "$current")"
    if [ "$current_size" != "$expected_size" ] || \
       [ "$current_digest" != "$expected_digest" ]; then
      log "ERROR: Existing HMG key changed during installation: $relative" >&2
      failed=true
    fi
  done <"$KEY_METADATA_BEFORE"
  [ "$failed" = false ]
}

create_upgrade_store_snapshot() {
  [ -d "$TARGET_STORE" ] || return 0
  if [ "$DRY_RUN" = true ]; then
    log "  (dry-run) Would create a verified key-excluding upgrade snapshot for ${TARGET_STORE}."
    return 0
  fi

  # The daemon is already stopped, so this is a crash-consistent offline copy.
  # Keep it beside stores/, not inside the store being copied. Raw key files are
  # deliberately excluded; the original key files remain in place and are
  # guarded by before/after size + SHA-256 verification.
  local data_home backup_dir timestamp listing digest checksum_tmp
  data_home="$(dirname "$(dirname "$TARGET_STORE")")"
  backup_dir="$data_home/upgrade-backups"
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  UPGRADE_BACKUP_FILE="$backup_dir/hmg-store-before-v${VERSION}-${timestamp}-$$.tar.gz"
  UPGRADE_BACKUP_TMP="$backup_dir/.hmg-store-before-v${VERSION}-${timestamp}-$$.partial"
  listing="$TMP_DIR/upgrade-backup.files"
  checksum_tmp="$TMP_DIR/upgrade-backup.sha256"

  mkdir -p "$backup_dir"
  chmod 0700 "$backup_dir"
  record_existing_store_key_metadata "$KEY_METADATA_BEFORE"

  local unsafe_entry
  unsafe_entry="$(find "$TARGET_STORE" \
    -path "$TARGET_STORE/.runtime" -prune -o \
    \( -type l -o -type p -o -type s -o -type b -o -type c \) \
    -print -quit 2>/dev/null || true)"
  if [ -n "$unsafe_entry" ]; then
    err "HMG store snapshot input contains a symbolic link or special file outside .runtime: ${unsafe_entry}; existing binaries were not replaced."
  fi

  log "Creating offline upgrade snapshot: ${UPGRADE_BACKUP_FILE}"
  if ! tar -czf "$UPGRADE_BACKUP_TMP" \
      --exclude='./.runtime' --exclude='./.runtime/*' \
      --exclude='./storage.key' --exclude='*/storage.key' \
      --exclude='./server.key.json' --exclude='*/server.key.json' \
      --exclude='./approval.key' --exclude='*/approval.key' \
      --exclude='./observation.key' --exclude='*/observation.key' \
      -C "$TARGET_STORE" .; then
    rm -f "$UPGRADE_BACKUP_TMP"
    err "Could not create a consistent HMG store upgrade snapshot; existing binaries were not replaced."
  fi
  chmod 0600 "$UPGRADE_BACKUP_TMP"
  if ! tar -tzf "$UPGRADE_BACKUP_TMP" >"$listing" 2>/dev/null || \
     [ ! -s "$listing" ]; then
    rm -f "$UPGRADE_BACKUP_TMP"
    err "HMG store upgrade snapshot is unreadable or has no file inventory; existing binaries were not replaced."
  fi
  if grep -E '(^|/)(storage\.key|server\.key\.json|approval\.key|observation\.key)$' \
      "$listing" >/dev/null 2>&1; then
    rm -f "$UPGRADE_BACKUP_TMP"
    err "HMG store upgrade snapshot unexpectedly contains raw key material; existing binaries were not replaced."
  fi

  mv "$UPGRADE_BACKUP_TMP" "$UPGRADE_BACKUP_FILE"
  UPGRADE_BACKUP_TMP=""
  digest="$(sha256_file "$UPGRADE_BACKUP_FILE")"
  printf '%s  %s\n' "$digest" "$(basename "$UPGRADE_BACKUP_FILE")" >"$checksum_tmp"
  install -m 0600 "$checksum_tmp" "${UPGRADE_BACKUP_FILE}.sha256"
  # HMG_INSTALL_STORE_SNAPSHOT_VERIFIED
  log "Verified upgrade snapshot tar inventory; raw HMG keys remain only in the original store."
}

# HMG_INSTALL_STORE_SCOPED_DAEMON_CONTROL
# Only the daemon owning TARGET_STORE is ever addressed. In particular, the
# installer never scans process tables or sends a signal to a process selected
# by name, so daemons for other stores and unrelated hmg-server processes are
# outside its stop/force-stop boundary.
old_daemon_status() {
  run_bounded 10 "$BIN_DIR/hmg" daemon status --store "$TARGET_STORE" \
    >/dev/null 2>&1
}

target_store_has_runtime_owner() {
  [ -f "$TARGET_STORE/.runtime/daemon.json" ] || \
    [ -f "$TARGET_STORE/.runtime/holder.pid" ]
}

inventory_existing_install() {
  local found=""
  local bin
  for bin in hmg hmg-server hmg-hook-worker; do
    if [ -e "$BIN_DIR/$bin" ]; then
      OLD_INSTALL_PRESENT=true
      found="${found}${found:+, }${bin}"
    fi
  done

  if [ "$OLD_INSTALL_PRESENT" = true ]; then
    log "Existing HMG install in ${BIN_DIR}: ${found}"
  else
    log "No existing HMG binaries found in ${BIN_DIR}."
  fi

  if [ -x "$BIN_DIR/hmg" ] && [ -x "$BIN_DIR/hmg-server" ]; then
    if old_daemon_status; then
      OLD_DAEMON_WAS_RUNNING=true
      log "Existing daemon is active for ${TARGET_STORE}."
    elif target_store_has_runtime_owner; then
      # A hung daemon can make status fail. The store-scoped CLI force path
      # validates the recorded lock holder before it terminates anything.
      OLD_DAEMON_WAS_RUNNING=true
      log "Existing daemon metadata/lock owner found for ${TARGET_STORE}."
    else
      log "No active daemon found for ${TARGET_STORE}."
    fi
  elif target_store_has_runtime_owner; then
    err "Daemon state exists for ${TARGET_STORE}, but ${BIN_DIR}/hmg and its sibling hmg-server are not both executable. Refusing an unsafe process-name kill. Repair the target installation directory and retry."
  fi
}

stop_existing_daemon() {
  inventory_existing_install
  if [ "$OLD_DAEMON_WAS_RUNNING" != true ]; then
    return 0
  fi
  if [ "$DRY_RUN" = true ]; then
    log "  (dry-run) Would gracefully stop the daemon for ${TARGET_STORE}, with a store-scoped force fallback."
    return 0
  fi

  log "Stopping existing daemon for ${TARGET_STORE}..."
  if run_bounded 45 "$BIN_DIR/hmg" daemon stop --store "$TARGET_STORE"; then
    if ! old_daemon_status; then
      OLD_DAEMON_STOPPED=true
      log "Existing daemon stopped gracefully."
      return 0
    fi
  fi

  log "Graceful stop did not complete; using store-scoped force fallback..."
  if ! run_bounded 60 "$BIN_DIR/hmg" daemon stop --force --store "$TARGET_STORE"; then
    err "Cannot safely stop the daemon for ${TARGET_STORE}; existing binaries were not replaced."
  fi
  if old_daemon_status; then
    err "Daemon for ${TARGET_STORE} is still running after force-stop; existing binaries were not replaced."
  fi
  OLD_DAEMON_STOPPED=true
  log "Existing daemon stopped with the store-scoped force fallback."
}

best_effort_stop_target_daemon() {
  [ -x "$BIN_DIR/hmg" ] || return 0
  if run_bounded 20 "$BIN_DIR/hmg" daemon stop --store "$TARGET_STORE" \
      >/dev/null 2>&1; then
    return 0
  fi
  run_bounded 30 "$BIN_DIR/hmg" daemon stop --force --store "$TARGET_STORE" \
    >/dev/null 2>&1 || true
}

restore_old_binaries() {
  [ "$REPLACEMENT_ATTEMPTED" = true ] || return 0
  log "Restoring the previous HMG binary bundle..."
  best_effort_stop_target_daemon
  local bin
  for bin in hmg hmg-server hmg-hook-worker; do
    rm -f "$BIN_DIR/.${bin}.hmg-install-new" "$BIN_DIR/.${bin}.hmg-install-rollback"
    if [ -d "$BACKUP_DIR/.present-${bin}" ] && [ -f "$BACKUP_DIR/$bin" ]; then
      install -m 0755 "$BACKUP_DIR/$bin" "$BIN_DIR/.${bin}.hmg-install-rollback"
      mv -f "$BIN_DIR/.${bin}.hmg-install-rollback" "$BIN_DIR/$bin"
    else
      rm -f "$BIN_DIR/$bin"
    fi
  done
}

cleanup_target_temps() {
  [ -d "$BIN_DIR" ] || return 0
  local bin
  for bin in hmg hmg-server hmg-hook-worker; do
    rm -f "$BIN_DIR/.${bin}.hmg-install-new" "$BIN_DIR/.${bin}.hmg-install-rollback"
  done
}

restart_old_daemon_after_failure() {
  [ "$OLD_DAEMON_WAS_RUNNING" = true ] || return 0
  [ "$OLD_DAEMON_STOPPED" = true ] || return 0
  if [ -x "$BIN_DIR/hmg" ] && [ -x "$BIN_DIR/hmg-server" ]; then
    log "Restarting the previous daemon after installation failure..."
    if ! run_bounded 60 "$BIN_DIR/hmg" daemon start --store "$TARGET_STORE"; then
      log "ERROR: Previous binaries were restored, but their daemon could not be restarted." >&2
    fi
  fi
}

cleanup() {
  local status=$?
  trap - 0 INT TERM HUP
  if [ -n "$ACTIVE_CHILD_PID" ]; then
    kill "$ACTIVE_CHILD_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$ACTIVE_CHILD_PID" 2>/dev/null || true
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || true
    ACTIVE_CHILD_PID=""
  fi
  if [ "$status" -ne 0 ] && [ "$INSTALL_COMMITTED" != true ]; then
    if [ "$STORE_SETUP_STARTED" = true ] && \
       ! verify_original_store_keys_unchanged; then
      log "ERROR: Store key integrity check failed during rollback; the installer did not delete or overwrite the store." >&2
    fi
    restore_old_binaries || true
    restart_old_daemon_after_failure || true
  fi
  cleanup_target_temps || true
  if [ -n "$UPGRADE_BACKUP_TMP" ]; then
    rm -f "$UPGRADE_BACKUP_TMP"
  fi
  rm -rf "$TMP_DIR"
  exit "$status"
}

trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

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
need_cmd install
need_cmd find

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
  case "$VERSION" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*)
      err "Invalid release version: $VERSION"
      ;;
  esac
  log "Installing HMG v${VERSION} (Community Edition)"
}

# ── Download, stage, and verify ────────────────────────────────────────────
verify_staged_bundle() {
  local pkg_dir="$1"
  local bin
  for bin in hmg hmg-server hmg-hook-worker; do
    if [ ! -f "$pkg_dir/$bin" ] || [ ! -s "$pkg_dir/$bin" ]; then
      log "  Staged package has an empty or missing binary: $bin"
      return 1
    fi
    chmod 0755 "$pkg_dir/$bin"
  done

  # The hook worker has no side-effect-free version command, so its regular,
  # non-empty executable check above is its package identity check. Validate
  # the two command binaries by executing their side-effect-free version paths.
  if ! run_bounded 15 "$pkg_dir/hmg" version \
      >"$TMP_DIR/staged-hmg-version.txt" 2>&1; then
    log "  Staged hmg binary cannot report its version"
    return 1
  fi
  if ! grep -F "$VERSION" "$TMP_DIR/staged-hmg-version.txt" >/dev/null 2>&1; then
    log "  Staged hmg version does not match requested v${VERSION}"
    return 1
  fi
  if ! run_bounded 15 "$pkg_dir/hmg-server" --version \
      >"$TMP_DIR/staged-server-version.txt" 2>&1; then
    log "  Staged hmg-server binary cannot report its version"
    return 1
  fi
  if ! grep -F "$VERSION" "$TMP_DIR/staged-server-version.txt" >/dev/null 2>&1; then
    log "  Staged hmg-server version does not match requested v${VERSION}"
    return 1
  fi

  # HMG_INSTALL_STAGED_BUNDLE_VERIFIED
  log "  Verified staged hmg, hmg-server, and hmg-hook-worker bundle."
  return 0
}

install_from_url() {
  local url="$1"
  local archive="$2"
  local pkg_dir="$TMP_DIR/package"
  local archive_path="$TMP_DIR/$archive"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"

  log "  Downloading: $url"
  if ! curl -fL --retry 3 --retry-delay 1 --connect-timeout 20 "$url" -o "$archive_path" 2>/dev/null; then
    return 1
  fi

  # Reject absolute and parent-traversal paths before extraction. The staging
  # tree is disposable, but an archive must never be able to escape it.
  if tar -tzf "$archive_path" 2>/dev/null \
      | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null 2>&1; then
    log "  Package contains an unsafe archive path"
    return 1
  fi
  if ! tar -xzf "$archive_path" -C "$pkg_dir" 2>/dev/null; then
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

  verify_staged_bundle "$pkg_dir" || return 1
  STAGED_DIR="$pkg_dir"
  return 0
}

backup_and_replace_bundle() {
  if [ "$DRY_RUN" = true ]; then
    log "  (dry-run) Would atomically replace hmg, hmg-server, and hmg-hook-worker in $BIN_DIR"
    return 0
  fi

  mkdir -p "$BIN_DIR" "$BACKUP_DIR"
  local bin
  for bin in hmg hmg-server hmg-hook-worker; do
    if [ -e "$BIN_DIR/$bin" ]; then
      if [ ! -f "$BIN_DIR/$bin" ] || [ -L "$BIN_DIR/$bin" ]; then
        err "Refusing to replace non-regular target: $BIN_DIR/$bin"
      fi
      cp -p "$BIN_DIR/$bin" "$BACKUP_DIR/$bin"
      mkdir -p "$BACKUP_DIR/.present-${bin}"
    fi
    install -m 0755 "$STAGED_DIR/$bin" "$BIN_DIR/.${bin}.hmg-install-new"
  done

  # Each rename is atomic on the target filesystem. The backup above plus the
  # EXIT rollback makes the three-file bundle transactional across failures.
  REPLACEMENT_ATTEMPTED=true
  for bin in hmg hmg-server hmg-hook-worker; do
    mv -f "$BIN_DIR/.${bin}.hmg-install-new" "$BIN_DIR/$bin"
  done
  # HMG_INSTALL_BINARY_BUNDLE_REPLACED
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

initialize_and_start_daemon() {
  # Test-only transaction seam used by the exact-package native lifecycle gate.
  # It deliberately fails after the candidate bundle has replaced the old
  # binaries so the EXIT trap must restore the previous three-file bundle and
  # restart its store-scoped daemon. It is never set by normal installation.
  if [ "${HMG_INSTALL_TEST_FAIL_AFTER_BINARY_SWITCH:-0}" = "1" ]; then
    err "Injected post-switch installer failure for rollback verification."
  fi
  # HMG_INSTALL_DATA_SAFETY: setup may create or migrate the default store, but
  # the installer itself never removes, recreates, or replaces TARGET_STORE.
  # Staging/binary rollback stay in TMP_DIR/BIN_DIR; the verified offline
  # upgrade snapshot is retained beside stores/ and the store is never deleted.
  log ""
  log "Running hmg setup --no-daemon..."
  STORE_SETUP_STARTED=true
  local setup_model_args=""
  local setup_agent_args=""
  if [ "${HMG_INSTALL_SKIP_MODEL:-0}" = "1" ]; then
    setup_model_args="--no-model"
  fi
  if [ "${HMG_INSTALL_SKIP_AGENT_ADAPTERS:-0}" = "1" ]; then
    setup_agent_args="--no-agent-adapters"
  fi
  if ! run_bounded 600 "$BIN_DIR/hmg" setup --no-daemon $setup_model_args $setup_agent_args; then
    err "hmg setup --no-daemon failed; restoring the previous binary bundle."
  fi
  log "✅ hmg setup --no-daemon completed."

  local daemon_action="start"
  if [ "$OLD_DAEMON_WAS_RUNNING" = true ]; then
    daemon_action="restart"
  fi
  log "Running hmg daemon ${daemon_action} for ${TARGET_STORE}..."
  if ! run_bounded 180 "$BIN_DIR/hmg" daemon "$daemon_action" --store "$TARGET_STORE"; then
    err "hmg daemon ${daemon_action} failed; installation is not ready and will be rolled back."
  fi
  if ! old_daemon_status; then
    err "The installed daemon did not pass its readiness check; installation will be rolled back."
  fi
  if ! verify_original_store_keys_unchanged; then
    err "A pre-existing HMG key changed during installation; refusing to report success."
  fi
  # HMG_INSTALL_DAEMON_READY
  log "✅ HMG daemon is ready for ${TARGET_STORE}."
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
  TARGET_STORE="$(default_store_dir)"
  resolve_version

  # Network work is read-only and may retry mirrors, so keep the current daemon
  # serving until the complete candidate bundle has been staged and verified.
  # A download failure therefore has zero effect on the existing runtime.
  do_install

  # The bounded unavailable window starts here: inventory/stop, offline store
  # snapshot, binary switch, setup, and target-daemon readiness. Every failure
  # after stop restores the previous bundle and daemon where possible.
  stop_existing_daemon
  create_upgrade_store_snapshot
  backup_and_replace_bundle

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

  initialize_and_start_daemon

  # Persist PATH only after the target bundle and daemon are ready. A profile
  # write failure still triggers binary rollback rather than reporting success.
  persist_path_if_needed

  INSTALL_COMMITTED=true
  log ""
  log "✅ HMG v${VERSION} installed and running from ${BIN_DIR}"

  log ""
  log "Quick commands:"
  log "  hmg doctor           # Check system readiness"
  log "  hmg daemon status    # Confirm the daemon remains ready"
  log "  hmg tui              # Open terminal UI"
  log ""
  log "Slow/blocked model downloads (mainland China)?"
  log "  The daemon is already running; the optional embedding model can be fetched on demand."
  log "  If HuggingFace is slow or blocked, set a mirror before an on-demand download:"
  log "    export HF_ENDPOINT=https://hf-mirror.com"
  log "    HMG_EMBEDDING_ENDPOINT=https://hf-mirror.com hmg model embedding download"
  log ""
  log "Update: hmg update"
  log "Docs:   https://hmg-ai.github.io/HMG-public/"
  log "Web:    https://hmg1ai.com/"
  log "GitHub: ${HMG_GITHUB}"
}

# HMG_INSTALL_SOURCE_ONLY makes the shell functions available to isolated
# installer contract tests without downloading, stopping a daemon, or writing
# user state. It is intentionally undocumented as an end-user option.
if [ "${HMG_INSTALL_SOURCE_ONLY:-0}" = "1" ]; then
  trap - 0 INT TERM HUP
  rm -rf "$TMP_DIR"
  return 0 2>/dev/null || exit 0
fi

main
