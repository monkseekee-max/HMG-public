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
  '== 1''0'
  'exactly 1''0 entries'
  'canonical 1''0-asset digest'
  'all t''en release assets'
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
  'expected_asset_count=17'
  "HMG-Desktop-\${version}-aarch64-setup.exe"
  "HMG-Desktop-\${version}-aarch64.dmg"
  "HMG-Desktop-\${version}-x86_64-setup.exe"
  "HMG-Desktop-\${version}-x86_64.AppImage"
  "HMG-Desktop-\${version}-x86_64.deb"
  "HMG-Desktop-\${version}-x86_64.dmg"
  'HMG-Desktop-SHA256SUMS.txt'
  'SHA256SUMS.txt'
  "hmg-\${version}-aarch64-apple-darwin.tar.gz"
  "hmg-\${version}-aarch64-pc-windows-msvc.zip"
  "hmg-\${version}-aarch64-unknown-linux-gnu.tar.gz"
  "hmg-\${version}-x86_64-apple-darwin.tar.gz"
  "hmg-\${version}-x86_64-pc-windows-msvc.zip"
  "hmg-\${version}-x86_64-unknown-linux-gnu.tar.gz"
  'install.ps1'
  'install.sh'
  'version.json'
  'canonical 17-asset digest'
  ".[0].source_sha == \$source_sha"
  "releases/download/\" + \$tag + \"/SHA256SUMS.txt"
)
for required in "${required_literals[@]}"; do
  if ! grep -Fq -- "${required}" "${workflow}" "${publisher}"; then
    echo "Required publisher policy literal is missing: ${required}" >&2
    exit 1
  fi
done

publisher_asset_function="$(
  sed -n '/^write_expected_assets() {$/,/^}$/p' "${publisher}"
)"
if [[ -z "${publisher_asset_function}" ]]; then
  echo 'Publisher asset contract function is missing.' >&2
  exit 1
fi
eval "${publisher_asset_function}"

write_frozen_release_assets() {
  printf '%s\n' \
    HMG-Desktop-1.7.7-aarch64-setup.exe \
    HMG-Desktop-1.7.7-aarch64.dmg \
    HMG-Desktop-1.7.7-x86_64-setup.exe \
    HMG-Desktop-1.7.7-x86_64.AppImage \
    HMG-Desktop-1.7.7-x86_64.deb \
    HMG-Desktop-1.7.7-x86_64.dmg \
    HMG-Desktop-SHA256SUMS.txt \
    SHA256SUMS.txt \
    hmg-1.7.7-aarch64-apple-darwin.tar.gz \
    hmg-1.7.7-aarch64-pc-windows-msvc.zip \
    hmg-1.7.7-aarch64-unknown-linux-gnu.tar.gz \
    hmg-1.7.7-x86_64-apple-darwin.tar.gz \
    hmg-1.7.7-x86_64-pc-windows-msvc.zip \
    hmg-1.7.7-x86_64-unknown-linux-gnu.tar.gz \
    install.ps1 \
    install.sh \
    version.json \
    | LC_ALL=C sort
}
diff -u \
  <(write_frozen_release_assets) \
  <(write_expected_assets 1.7.7 /dev/stdout)

echo 'publish-promoted-release static policy checks passed'
