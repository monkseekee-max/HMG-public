#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

readonly api_version='2026-03-10'
readonly source_repository='HMG-AI/HMG'
readonly target_repository='HMG-AI/HMG-public'
readonly target_branch='main'
readonly expected_key_id='ed25519-spki-sha256-10a79fee35f78fbe9542c7a9b639e564dd6c99c7068c7fb3b230084dca670fe2'
readonly expected_key_fingerprint='10a79fee35f78fbe9542c7a9b639e564dd6c99c7068c7fb3b230084dca670fe2'
readonly public_key_path=".github/provenance-keys/${expected_key_id}.pem"

if [[ -z "${PROMOTION_WORKTREE:-}" || \
      "${PROMOTION_WORKTREE}" != /* || \
      ! -d "${PROMOTION_WORKTREE}/.git" ]]; then
  echo 'The promoted commit worktree is missing or invalid.' >&2
  exit 2
fi
cd "${PROMOTION_WORKTREE}"

api_json() {
  gh api \
    -H 'Accept: application/vnd.github+json' \
    -H "X-GitHub-Api-Version: ${api_version}" \
    "$@"
}

list_releases() {
  api_json --paginate \
    "repos/${target_repository}/releases?per_page=100" \
    | jq -s 'add // []'
}

select_releases_by_tag() {
  local releases_file="$1"
  local tag="$2"
  local output_file="$3"
  jq --arg tag "${tag}" \
    '[.[] | select(.tag_name == $tag)]' \
    "${releases_file}" > "${output_file}"
}

load_exact_tag_ref() {
  local tag="$1"
  local output_file="$2"
  local matching_file="${output_file}.matching"
  api_json "repos/${target_repository}/git/matching-refs/tags/${tag}" \
    > "${matching_file}"
  jq --arg ref "refs/tags/${tag}" \
    '[.[] | select(.ref == $ref)]' \
    "${matching_file}" > "${output_file}"
}

verify_lightweight_tag() {
  local tag="$1"
  local expected_sha="$2"
  local tag_refs_file="$3"
  local tag_count
  tag_count="$(jq 'length' "${tag_refs_file}")"
  if ((tag_count != 1)); then
    echo "Expected exactly one final tag ref for ${tag}; found ${tag_count}." >&2
    return 1
  fi
  jq -e \
    --arg ref "refs/tags/${tag}" \
    --arg sha "${expected_sha}" '
      .[0].ref == $ref and
      .[0].object.type == "commit" and
      .[0].object.sha == $sha
    ' "${tag_refs_file}" >/dev/null || {
      echo "Final tag ${tag} must be a lightweight ref at ${expected_sha}." >&2
      return 1
    }
}

write_expected_assets() {
  local version="$1"
  local output_file="$2"
  printf '%s\n' \
    SHA256SUMS.txt \
    "hmg-${version}-aarch64-apple-darwin.tar.gz" \
    "hmg-${version}-aarch64-pc-windows-msvc.zip" \
    "hmg-${version}-aarch64-unknown-linux-gnu.tar.gz" \
    "hmg-${version}-x86_64-apple-darwin.tar.gz" \
    "hmg-${version}-x86_64-pc-windows-msvc.zip" \
    "hmg-${version}-x86_64-unknown-linux-gnu.tar.gz" \
    install.ps1 \
    install.sh \
    version.json \
    | LC_ALL=C sort > "${output_file}"
}

snapshot_release() {
  local release_file="$1"
  local output_file="$2"
  jq -S '{
      id,
      tag_name,
      draft,
      prerelease,
      assets: ([.assets[] | {id, name, size, state, updated_at, digest}] | sort_by(.name))
    }' "${release_file}" > "${output_file}"
}

validate_release_asset_metadata() {
  local release_file="$1"
  local expected_assets_file="$2"
  local allow_incomplete="$3"
  local actual_names
  actual_names="${RUNNER_TEMP}/asset-names-$(basename "${release_file}")"

  jq -r '.assets[].name' "${release_file}" \
    | LC_ALL=C sort > "${actual_names}"
  if [[ "${allow_incomplete}" == 'false' ]]; then
    diff -u "${expected_assets_file}" "${actual_names}"
  else
    while IFS= read -r asset_name; do
      if ! grep -Fxq "${asset_name}" "${expected_assets_file}"; then
        echo "Unexpected release asset: ${asset_name}" >&2
        return 1
      fi
    done < "${actual_names}"
  fi

  jq -e \
    --argjson allow_incomplete "${allow_incomplete}" '
      (.assets | map(.name) | length) == (.assets | map(.name) | unique | length) and
      all(.assets[];
        (.id | type == "number") and
        (.size | type == "number") and
        .size > 0 and
        .state == "uploaded" and
        (.name | type == "string")
      ) and
      ($allow_incomplete or (.assets | length) == 10)
    ' "${release_file}" >/dev/null
}

validate_recoverable_asset_metadata() {
  local release_file="$1"
  local expected_assets_file="$2"
  local allow_missing="$3"
  local actual_names
  actual_names="${RUNNER_TEMP}/recoverable-asset-names-$(basename "${release_file}")"

  jq -r '.assets[].name' "${release_file}" \
    | LC_ALL=C sort > "${actual_names}"
  if [[ "${allow_missing}" == 'false' ]]; then
    diff -u "${expected_assets_file}" "${actual_names}"
  else
    while IFS= read -r asset_name; do
      if ! grep -Fxq "${asset_name}" "${expected_assets_file}"; then
        echo "Unexpected release asset: ${asset_name}" >&2
        return 1
      fi
    done < "${actual_names}"
  fi

  jq -e \
    --argjson allow_missing "${allow_missing}" '
      (.assets | map(.name) | length) == (.assets | map(.name) | unique | length) and
      all(.assets[];
        (.id | type == "number") and
        (.size | type == "number") and
        .size >= 0 and
        (.state == "uploaded" or .state == "starter") and
        (if .state == "uploaded" then .size > 0 else true end) and
        (.name | type == "string")
      ) and
      ($allow_missing or (.assets | length) == 10)
    ' "${release_file}" >/dev/null
}

delete_captured_starter_assets() {
  local release_file="$1"
  local starter_id starter_name
  while IFS=$'\t' read -r starter_id starter_name; do
    if [[ ! "${starter_id}" =~ ^[0-9]+$ || -z "${starter_name}" ]]; then
      echo 'Captured starter asset metadata is invalid.' >&2
      return 1
    fi
    api_json --method DELETE \
      "repos/${target_repository}/releases/assets/${starter_id}" \
      >/dev/null
    echo "Recovered incomplete release asset slot: ${starter_name}"
  done < <(
    jq -r '.assets[] | select(.state == "starter") | [.id, .name] | @tsv' \
      "${release_file}"
  )
}

download_assets_by_id() {
  local release_file="$1"
  local expected_assets_file="$2"
  local output_dir="$3"
  rm -rf "${output_dir}"
  mkdir -p "${output_dir}"

  while IFS= read -r asset_name; do
    local asset_count asset_id asset_state expected_size remote_digest actual_digest
    asset_count="$(
      jq --arg name "${asset_name}" \
        '[.assets[] | select(.name == $name)] | length' \
        "${release_file}"
    )"
    if ((asset_count != 1)); then
      echo "Expected exactly one captured asset named ${asset_name}." >&2
      return 1
    fi
    asset_id="$(
      jq -r --arg name "${asset_name}" \
        '.assets[] | select(.name == $name) | .id' \
        "${release_file}"
    )"
    expected_size="$(
      jq -r --arg name "${asset_name}" \
        '.assets[] | select(.name == $name) | .size' \
        "${release_file}"
    )"
    asset_state="$(
      jq -r --arg name "${asset_name}" \
        '.assets[] | select(.name == $name) | .state' \
        "${release_file}"
    )"
    remote_digest="$(
      jq -r --arg name "${asset_name}" \
        '.assets[] | select(.name == $name) | (.digest // "")' \
        "${release_file}"
    )"
    api_json \
      -H 'Accept: application/octet-stream' \
      "repos/${target_repository}/releases/assets/${asset_id}" \
      > "${output_dir}/${asset_name}"
    if [[ "${asset_state}" == 'uploaded' && \
          "$(stat -c '%s' "${output_dir}/${asset_name}")" != "${expected_size}" ]]; then
      echo "Downloaded asset size changed for ${asset_name}." >&2
      return 1
    fi
    actual_digest="$(sha256sum "${output_dir}/${asset_name}" | cut -d ' ' -f1)"
    if [[ -n "${remote_digest}" && \
          "${remote_digest}" != "sha256:${actual_digest}" ]]; then
      echo "GitHub asset digest disagrees with downloaded bytes for ${asset_name}." >&2
      return 1
    fi
  done < "${expected_assets_file}"
}

verify_local_asset_set() {
  local asset_dir="$1"
  local expected_assets_file="$2"
  local expected_digest="$3"
  local source_tag="$4"
  local output_manifest="$5"
  local version="${source_tag#v}"
  local actual_assets="${output_manifest}.names"
  local expected_packages="${output_manifest}.packages"
  local checksummed_packages="${output_manifest}.checksummed"
  local checksum_file="${asset_dir}/SHA256SUMS.txt"
  local entry_count last_byte computed_digest asset_name asset_digest
  local -r checksum_line_pattern='^[0-9a-f]{64}  ([A-Za-z0-9._-]+)$'

  entry_count="$(find "${asset_dir}" -mindepth 1 -maxdepth 1 | wc -l)"
  if ((entry_count != 10)); then
    echo 'Release asset directory must contain exactly 10 entries.' >&2
    return 1
  fi
  find "${asset_dir}" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' \
    | LC_ALL=C sort > "${actual_assets}"
  diff -u "${expected_assets_file}" "${actual_assets}"

  printf '%s\n' \
    "hmg-${version}-aarch64-apple-darwin.tar.gz" \
    "hmg-${version}-aarch64-pc-windows-msvc.zip" \
    "hmg-${version}-aarch64-unknown-linux-gnu.tar.gz" \
    "hmg-${version}-x86_64-apple-darwin.tar.gz" \
    "hmg-${version}-x86_64-pc-windows-msvc.zip" \
    "hmg-${version}-x86_64-unknown-linux-gnu.tar.gz" \
    | LC_ALL=C sort > "${expected_packages}"

  last_byte="$(tail -c 1 "${checksum_file}" | od -An -t u1 | tr -d '[:space:]')"
  if [[ "${last_byte}" != '10' ]]; then
    echo 'SHA256SUMS.txt must end with one newline.' >&2
    return 1
  fi
  mapfile -t checksum_lines < "${checksum_file}"
  if ((${#checksum_lines[@]} != 6)); then
    echo 'SHA256SUMS.txt must contain exactly six package checksums.' >&2
    return 1
  fi
  : > "${checksummed_packages}"
  for checksum_line in "${checksum_lines[@]}"; do
    if [[ ! "${checksum_line}" =~ ${checksum_line_pattern} ]]; then
      echo 'SHA256SUMS.txt is not canonical GNU sha256sum format.' >&2
      return 1
    fi
    printf '%s\n' "${BASH_REMATCH[1]}" >> "${checksummed_packages}"
  done
  LC_ALL=C sort -o "${checksummed_packages}" "${checksummed_packages}"
  diff -u "${expected_packages}" "${checksummed_packages}"
  (
    cd "${asset_dir}"
    sha256sum --strict --check SHA256SUMS.txt
  )

  jq -e -s --arg tag "${source_tag}" --arg version "${version}" '
    length == 1 and
    (.[0] | type == "object") and
    (.[0] | keys | sort) == ([
      "channel",
      "manifest_version",
      "message",
      "released_at",
      "severity",
      "sha256sums_url",
      "tag",
      "title",
      "update_command",
      "version"
    ] | sort) and
    .[0].manifest_version == 1 and
    .[0].version == $version and
    .[0].tag == $tag and
    (.[0].released_at | type == "string") and
    (.[0].released_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    .[0].channel == "stable" and
    .[0].severity == "normal" and
    .[0].title == ("HMG " + $tag + " available") and
    .[0].message == "Run hmg update to install the latest HMG release." and
    .[0].update_command == "hmg update" and
    .[0].sha256sums_url == "https://github.com/HMG-AI/HMG-public/releases/latest/download/SHA256SUMS.txt"
  ' "${asset_dir}/version.json" >/dev/null

  : > "${output_manifest}"
  while IFS= read -r asset_name; do
    asset_digest="$(sha256sum "${asset_dir}/${asset_name}" | cut -d ' ' -f1)"
    printf '%s  %s\n' "${asset_digest}" "${asset_name}" \
      >> "${output_manifest}"
  done < "${expected_assets_file}"
  computed_digest="$(sha256sum "${output_manifest}" | cut -d ' ' -f1)"
  if [[ "${computed_digest}" != "${expected_digest}" ]]; then
    echo 'The canonical 10-asset digest does not match signed provenance.' >&2
    return 1
  fi
}

verify_published_terminal() {
  local release_file="$1"
  local source_tag="$2"
  local promotion_commit="$3"
  local expected_assets_file="$4"
  local expected_digest="$5"
  local terminal_dir="$6"
  local require_latest="$7"
  local release_id tag_refs latest_file terminal_manifest

  jq -e --arg tag "${source_tag}" '
    .tag_name == $tag and
    .draft == false and
    .prerelease == false and
    .immutable == true and
    (.id | type == "number") and
    (.html_url | type == "string")
  ' "${release_file}" >/dev/null
  validate_release_asset_metadata "${release_file}" "${expected_assets_file}" false
  tag_refs="${RUNNER_TEMP}/terminal-tag-refs.json"
  load_exact_tag_ref "${source_tag}" "${tag_refs}"
  verify_lightweight_tag "${source_tag}" "${promotion_commit}" "${tag_refs}"
  download_assets_by_id \
    "${release_file}" "${expected_assets_file}" "${terminal_dir}"
  terminal_manifest="${RUNNER_TEMP}/terminal-assets.sha256"
  verify_local_asset_set \
    "${terminal_dir}" "${expected_assets_file}" "${expected_digest}" \
    "${source_tag}" "${terminal_manifest}"

  if [[ "${require_latest}" == 'true' ]]; then
    release_id="$(jq -r '.id' "${release_file}")"
    latest_file="${RUNNER_TEMP}/terminal-latest.json"
    api_json "repos/${target_repository}/releases/latest" > "${latest_file}"
    jq -e --argjson id "${release_id}" '.id == $id' \
      "${latest_file}" >/dev/null || {
        echo "Newly published terminal release ${source_tag} is not latest." >&2
        return 1
      }
  fi
}

semver_greater_or_equal() {
  local left="${1#v}"
  local right="${2#v}"
  local left_major left_minor left_patch right_major right_minor right_patch
  IFS=. read -r left_major left_minor left_patch <<< "${left}"
  IFS=. read -r right_major right_minor right_patch <<< "${right}"
  local left_part right_part
  for pair in \
    "${left_major}:${right_major}" \
    "${left_minor}:${right_minor}" \
    "${left_patch}:${right_patch}"; do
    left_part="${pair%%:*}"
    right_part="${pair#*:}"
    if [[ "${left_part}" == "${right_part}" ]]; then
      continue
    fi
    if ((${#left_part} > ${#right_part})); then
      return 0
    fi
    if ((${#left_part} < ${#right_part})); then
      return 1
    fi
    [[ "${left_part}" > "${right_part}" ]]
    return
  done
  return 0
}

reject_stale_promotion() {
  local releases_file="$1"
  local candidate_tag="$2"
  local published_tag
  while IFS= read -r published_tag; do
    if [[ ! "${published_tag}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
      continue
    fi
    if [[ "${published_tag}" != "${candidate_tag}" ]] && \
       semver_greater_or_equal "${published_tag}" "${candidate_tag}"; then
      echo "Published ${published_tag} is not older than ${candidate_tag}; refusing stale latest promotion." >&2
      return 1
    fi
  done < <(
    jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
      "${releases_file}"
  )
}

if [[ "${GITHUB_REPOSITORY:-}" != "${target_repository}" || \
      "${GITHUB_REF:-}" != 'refs/heads/main' || \
      ! "${PROMOTION_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Publisher runtime scope or promotion SHA is invalid.' >&2
  exit 2
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo 'The protected publisher token is unavailable.' >&2
  exit 2
fi

git fetch --no-tags origin \
  '+refs/heads/main:refs/remotes/origin/main'
resolved_commit="$(git rev-parse --verify "${PROMOTION_COMMIT}^{commit}")"
if [[ "${resolved_commit}" != "${PROMOTION_COMMIT}" ]] || \
   ! git merge-base --is-ancestor \
      "${PROMOTION_COMMIT}" refs/remotes/origin/main; then
  echo 'Promotion commit is not the exact protected-main commit requested.' >&2
  exit 2
fi

trailer_file="${RUNNER_TEMP}/promotion-trailers.txt"
git show -s --format=%B "${PROMOTION_COMMIT}" \
  | git interpret-trailers --parse > "${trailer_file}"
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
for trailer_key in "${trailer_keys[@]}"; do
  mapfile -t trailer_values < <(
    sed -nE "s/^${trailer_key}:[[:space:]]*//p" "${trailer_file}"
  )
  if ((${#trailer_values[@]} != 1)) || [[ -z "${trailer_values[0]}" ]]; then
    echo "Expected exactly one non-empty ${trailer_key} trailer." >&2
    exit 2
  fi
  case "${trailer_key}" in
    HMG-Source-Repository) promoted_source_repository="${trailer_values[0]}" ;;
    HMG-Source-Tag) source_tag="${trailer_values[0]}" ;;
    HMG-Source-SHA) source_sha="${trailer_values[0]}" ;;
    HMG-Workflow-Run) workflow_run="${trailer_values[0]}" ;;
    HMG-Asset-Set-SHA256) asset_set_digest="${trailer_values[0]}" ;;
    HMG-Candidate-Tree) candidate_tree="${trailer_values[0]}" ;;
    HMG-Provenance-Key-ID) provenance_key_id="${trailer_values[0]}" ;;
    HMG-Provenance-Signature-Ed25519) provenance_signature="${trailer_values[0]}" ;;
  esac
done
recognized_count="$(
  grep -Ec '^HMG-(Source-Repository|Source-Tag|Source-SHA|Workflow-Run|Asset-Set-SHA256|Candidate-Tree|Provenance-Key-ID|Provenance-Signature-Ed25519):' \
    "${trailer_file}" || true
)"
hmg_trailer_count="$(
  grep -Ec '^HMG-[A-Za-z0-9-]+:' "${trailer_file}" || true
)"
if ((recognized_count != 8 || hmg_trailer_count != 8)); then
  echo 'Promotion contract must contain exactly eight recognized trailers.' >&2
  exit 2
fi

if [[ "${promoted_source_repository}" != "${source_repository}" || \
      ! "${source_tag}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ || \
      ! "${source_sha}" =~ ^[0-9a-f]{40}$ || \
      ! "${workflow_run}" =~ ^https://github\.com/HMG-AI/HMG/actions/runs/[1-9][0-9]*$ || \
      ! "${asset_set_digest}" =~ ^[0-9a-f]{64}$ || \
      ! "${candidate_tree}" =~ ^(sha1:[0-9a-f]{40}|sha256:[0-9a-f]{64})$ || \
      "${provenance_key_id}" != "${expected_key_id}" || \
      ! "${provenance_signature}" =~ ^[A-Za-z0-9+/]{86}==$ ]]; then
  echo 'Promotion contract values are invalid or outside the trusted policy.' >&2
  exit 2
fi

object_format="$(git rev-parse --show-object-format)"
promotion_tree="${object_format}:$(git rev-parse "${PROMOTION_COMMIT}^{tree}")"
if [[ "${promotion_tree}" != "${candidate_tree}" ]]; then
  echo 'The protected-main commit tree differs from the signed candidate tree.' >&2
  exit 2
fi
if [[ ! -f "${public_key_path}" ]]; then
  echo 'The reviewed promotion verification key is missing.' >&2
  exit 2
fi
public_key_fingerprint="$({
  /usr/bin/openssl pkey \
    -pubin \
    -in "${public_key_path}" \
    -outform DER
} | sha256sum | cut -d ' ' -f1)"
if [[ "${public_key_fingerprint}" != "${expected_key_fingerprint}" ]]; then
  echo 'The promotion public key does not match the reviewed fingerprint.' >&2
  exit 2
fi

statement_file="${RUNNER_TEMP}/hmg-public-provenance-v1.txt"
signature_file="${RUNNER_TEMP}/hmg-public-provenance-v1.sig"
printf '%s\n' \
  'HMG-PUBLIC-PROVENANCE-V1' \
  "source-repository=${source_repository}" \
  "source-tag=${source_tag}" \
  "source-sha=${source_sha}" \
  "workflow-run=${workflow_run}" \
  "asset-set-sha256=${asset_set_digest}" \
  "candidate-tree=${candidate_tree}" \
  "target-repository=${target_repository}" \
  "target-branch=${target_branch}" \
  "key-id=${provenance_key_id}" \
  > "${statement_file}"
if ! printf '%s' "${provenance_signature}" \
    | /usr/bin/openssl base64 -d -A -out "${signature_file}" || \
   [[ "$(wc -c < "${signature_file}")" != '64' ]]; then
  echo 'Promotion signature is not canonical Ed25519.' >&2
  exit 2
fi
if ! /usr/bin/openssl pkeyutl \
    -verify \
    -pubin \
    -inkey "${public_key_path}" \
    -rawin \
    -in "${statement_file}" \
    -sigfile "${signature_file}"; then
  echo 'The HMG promotion provenance signature is not trusted.' >&2
  exit 2
fi

associated_pulls="${RUNNER_TEMP}/associated-pulls.json"
expected_head="release/hmg-public/${source_tag}"
api_json \
  "repos/${target_repository}/commits/${PROMOTION_COMMIT}/pulls" \
  > "${associated_pulls}"
jq -e \
  --arg repository "${target_repository}" \
  --arg expected_head "${expected_head}" '
    length == 1 and
    .[0].state == "closed" and
    .[0].merged_at != null and
    .[0].base.ref == "main" and
    .[0].base.repo.full_name == $repository and
    .[0].head.repo.full_name == $repository and
    .[0].head.ref == $expected_head
  ' "${associated_pulls}" >/dev/null || {
    echo 'Promotion commit is not backed by one merged same-repository release PR.' >&2
    exit 2
  }
promotion_pr_url="$(jq -r '.[0].html_url' "${associated_pulls}")"

version="${source_tag#v}"
if ! cmp -s VERSION <(printf '%s\n' "${version}"); then
  echo "VERSION does not match ${source_tag}." >&2
  exit 2
fi
manifest_version="$(
  jq -er '.product.version | select(type == "string")' public-manifest.json
)"
if [[ "${manifest_version}" != "${version}" ]]; then
  echo "public-manifest.json product.version does not match ${source_tag}." >&2
  exit 2
fi

expected_assets="${RUNNER_TEMP}/expected-assets.txt"
write_expected_assets "${version}" "${expected_assets}"
releases_file="${RUNNER_TEMP}/releases-before.json"
final_matches="${RUNNER_TEMP}/final-matches.json"
list_releases > "${releases_file}"
select_releases_by_tag "${releases_file}" "${source_tag}" "${final_matches}"
final_count="$(jq 'length' "${final_matches}")"
if ((final_count > 1)); then
  echo "More than one release uses final tag ${source_tag}." >&2
  exit 2
fi
if ((final_count == 1)); then
  jq '.[0]' "${final_matches}" > "${RUNNER_TEMP}/final-existing.json"
  final_existing="${RUNNER_TEMP}/final-existing.json"
  if [[ "$(jq -r '.draft' "${final_existing}")" == 'false' ]]; then
    verify_published_terminal \
      "${final_existing}" "${source_tag}" "${PROMOTION_COMMIT}" \
      "${expected_assets}" "${asset_set_digest}" \
      "${RUNNER_TEMP}/terminal-assets" false
    release_url="$(jq -r '.html_url' "${final_existing}")"
    {
      echo '### Promoted release already published'
      echo
      echo "- Release: [${source_tag}](${release_url})"
      echo "- Promotion commit: ${PROMOTION_COMMIT}"
      echo "- Signed candidate tree: ${candidate_tree}"
      echo "- 10-asset digest: ${asset_set_digest}"
      echo '- Result: exact immutable terminal state; no write was performed.'
    } >> "${GITHUB_STEP_SUMMARY}"
    exit 0
  fi
  jq -e --arg tag "${source_tag}" '
    .tag_name == $tag and
    .draft == true and
    .prerelease == false and
    (.id | type == "number")
  ' "${final_existing}" >/dev/null || {
    echo 'Existing final release is not a retryable final draft.' >&2
    exit 2
  }
fi
reject_stale_promotion "${releases_file}" "${source_tag}"
early_final_tag_refs="${RUNNER_TEMP}/early-final-tag-refs.json"
load_exact_tag_ref "${source_tag}" "${early_final_tag_refs}"
early_final_tag_count="$(jq 'length' "${early_final_tag_refs}")"
if ((early_final_tag_count > 1)); then
  echo "More than one exact final tag ref was returned for ${source_tag}." >&2
  exit 2
fi
if ((early_final_tag_count == 1)); then
  verify_lightweight_tag \
    "${source_tag}" "${PROMOTION_COMMIT}" "${early_final_tag_refs}"
elif ((final_count == 1)); then
  echo 'A retryable final draft exists without its exact immutable tag target.' >&2
  exit 2
fi

readonly staging_tag="hmg-public-staging-${source_tag}-${source_sha}"
staging_matches="${RUNNER_TEMP}/staging-matches.json"
select_releases_by_tag "${releases_file}" "${staging_tag}" "${staging_matches}"
staging_count="$(jq 'length' "${staging_matches}")"
if ((staging_count != 1)); then
  echo "Expected exactly one deterministic staging release ${staging_tag}." >&2
  exit 2
fi
staging_release="${RUNNER_TEMP}/staging-release.json"
jq '.[0]' "${staging_matches}" > "${staging_release}"
jq -e --arg tag "${staging_tag}" '
  .tag_name == $tag and
  .draft == true and
  .prerelease == true and
  (.id | type == "number")
' "${staging_release}" >/dev/null || {
  echo 'Staging release state is not the signed transport contract.' >&2
  exit 2
}
validate_recoverable_asset_metadata \
  "${staging_release}" "${expected_assets}" false
staging_snapshot="${RUNNER_TEMP}/staging-snapshot.json"
snapshot_release "${staging_release}" "${staging_snapshot}"
staging_asset_dir="${RUNNER_TEMP}/staging-assets"
staging_manifest="${RUNNER_TEMP}/staging-assets.sha256"
download_assets_by_id \
  "${staging_release}" "${expected_assets}" "${staging_asset_dir}"
verify_local_asset_set \
  "${staging_asset_dir}" "${expected_assets}" "${asset_set_digest}" \
  "${source_tag}" "${staging_manifest}"

staging_release_id="$(jq -r '.id' "${staging_release}")"
staging_current="${RUNNER_TEMP}/staging-current.json"
staging_current_snapshot="${RUNNER_TEMP}/staging-current-snapshot.json"
staging_starter_names="${RUNNER_TEMP}/staging-starter-names.txt"
jq -r '.assets[] | select(.state == "starter") | .name' \
  "${staging_release}" > "${staging_starter_names}"
if [[ -s "${staging_starter_names}" ]]; then
  # A captured starter can be repaired only after its downloaded bytes and
  # every other asset have already matched the signed aggregate. The delete is
  # by captured asset ID; uploaded assets are never deleted or overwritten.
  api_json "repos/${target_repository}/releases/${staging_release_id}" \
    > "${staging_current}"
  snapshot_release "${staging_current}" "${staging_current_snapshot}"
  diff -u "${staging_snapshot}" "${staging_current_snapshot}" || {
    echo 'Staging release changed before starter recovery.' >&2
    exit 2
  }
  delete_captured_starter_assets "${staging_release}"
  while IFS= read -r starter_name; do
    gh release upload \
      "${staging_tag}" "${staging_asset_dir}/${starter_name}" \
      --repo "${target_repository}"
  done < "${staging_starter_names}"
  api_json "repos/${target_repository}/releases/${staging_release_id}" \
    > "${staging_current}"
  validate_release_asset_metadata \
    "${staging_current}" "${expected_assets}" false
  download_assets_by_id \
    "${staging_current}" "${expected_assets}" "${staging_asset_dir}"
  verify_local_asset_set \
    "${staging_asset_dir}" "${expected_assets}" "${asset_set_digest}" \
    "${source_tag}" "${staging_manifest}"
else
  api_json "repos/${target_repository}/releases/${staging_release_id}" \
    > "${staging_current}"
  snapshot_release "${staging_current}" "${staging_current_snapshot}"
  diff -u "${staging_snapshot}" "${staging_current_snapshot}" || {
    echo 'Staging release changed while its assets were being verified.' >&2
    exit 2
  }
fi

# No final tag or final release write occurs above this line. A mutable staging
# starter may have been recovered only after all ten captured bytes passed the
# signed digest. Refresh final state and prevent an older retry becoming latest.
prewrite_releases="${RUNNER_TEMP}/releases-prewrite.json"
list_releases > "${prewrite_releases}"
reject_stale_promotion "${prewrite_releases}" "${source_tag}"

final_tag_refs="${RUNNER_TEMP}/final-tag-refs.json"
load_exact_tag_ref "${source_tag}" "${final_tag_refs}"
final_tag_count="$(jq 'length' "${final_tag_refs}")"
if ((final_tag_count == 0)); then
  api_json --method POST \
    "repos/${target_repository}/git/refs" \
    -f "ref=refs/tags/${source_tag}" \
    -f "sha=${PROMOTION_COMMIT}" \
    > "${RUNNER_TEMP}/created-final-tag.json"
  load_exact_tag_ref "${source_tag}" "${final_tag_refs}"
elif ((final_tag_count != 1)); then
  echo "More than one exact final tag ref was returned for ${source_tag}." >&2
  exit 2
fi
verify_lightweight_tag \
  "${source_tag}" "${PROMOTION_COMMIT}" "${final_tag_refs}"

select_releases_by_tag \
  "${prewrite_releases}" "${source_tag}" "${RUNNER_TEMP}/prewrite-final-matches.json"
prewrite_final_count="$(jq 'length' "${RUNNER_TEMP}/prewrite-final-matches.json")"
if ((prewrite_final_count == 0)); then
  api_json --method POST \
    "repos/${target_repository}/releases" \
    -f "tag_name=${source_tag}" \
    -f "target_commitish=${PROMOTION_COMMIT}" \
    -f "name=HMG ${source_tag}" \
    -f "body=Protected HMG public release from ${source_sha}. Promotion PR: ${promotion_pr_url}. Source workflow: ${workflow_run}." \
    -F draft=true \
    -F prerelease=false \
    > "${RUNNER_TEMP}/final-draft.json"
elif ((prewrite_final_count == 1)); then
  jq '.[0]' "${RUNNER_TEMP}/prewrite-final-matches.json" \
    > "${RUNNER_TEMP}/final-draft.json"
else
  echo "More than one final release uses ${source_tag}." >&2
  exit 2
fi
final_draft="${RUNNER_TEMP}/final-draft.json"
jq -e --arg tag "${source_tag}" '
  .tag_name == $tag and
  .draft == true and
  .prerelease == false and
  (.id | type == "number")
' "${final_draft}" >/dev/null || {
  echo 'Final release is not a retryable draft.' >&2
  exit 2
}
final_release_id="$(jq -r '.id' "${final_draft}")"
initial_final_draft_snapshot="${RUNNER_TEMP}/initial-final-draft-snapshot.json"
current_final_draft_snapshot="${RUNNER_TEMP}/current-final-draft-snapshot.json"
snapshot_release "${final_draft}" "${initial_final_draft_snapshot}"
api_json "repos/${target_repository}/releases/${final_release_id}" \
  > "${RUNNER_TEMP}/final-draft-before-recovery.json"
snapshot_release \
  "${RUNNER_TEMP}/final-draft-before-recovery.json" \
  "${current_final_draft_snapshot}"
diff -u "${initial_final_draft_snapshot}" "${current_final_draft_snapshot}" || {
  echo 'Final draft changed before asset reconciliation.' >&2
  exit 2
}
final_draft="${RUNNER_TEMP}/final-draft-before-recovery.json"
validate_recoverable_asset_metadata \
  "${final_draft}" "${expected_assets}" true
final_starter_count="$(
  jq '[.assets[] | select(.state == "starter")] | length' "${final_draft}"
)"
if ((final_starter_count > 0)); then
  # Signed staging bytes are already locked locally, so only incomplete
  # starter IDs are deleted. Uploaded mismatches remain fail-closed below.
  delete_captured_starter_assets "${final_draft}"
  api_json "repos/${target_repository}/releases/${final_release_id}" \
    > "${RUNNER_TEMP}/final-draft-recovered.json"
  final_draft="${RUNNER_TEMP}/final-draft-recovered.json"
fi
validate_release_asset_metadata "${final_draft}" "${expected_assets}" true

while IFS= read -r asset_name; do
  remote_count="$(
    jq --arg name "${asset_name}" \
      '[.assets[] | select(.name == $name)] | length' \
      "${final_draft}"
  )"
  if ((remote_count == 0)); then
    gh release upload "${source_tag}" "${staging_asset_dir}/${asset_name}" \
      --repo "${target_repository}"
    continue
  fi
  if ((remote_count != 1)); then
    echo "Duplicate final draft asset: ${asset_name}." >&2
    exit 2
  fi
  existing_asset_id="$(
    jq -r --arg name "${asset_name}" \
      '.assets[] | select(.name == $name) | .id' \
      "${final_draft}"
  )"
  existing_asset="${RUNNER_TEMP}/existing-final-${existing_asset_id}"
  api_json \
    -H 'Accept: application/octet-stream' \
    "repos/${target_repository}/releases/assets/${existing_asset_id}" \
    > "${existing_asset}"
  if ! cmp -s "${staging_asset_dir}/${asset_name}" "${existing_asset}"; then
    echo "Existing final draft asset conflicts with signed bytes: ${asset_name}." >&2
    exit 2
  fi
done < "${expected_assets}"

final_draft_current="${RUNNER_TEMP}/final-draft-current.json"
api_json "repos/${target_repository}/releases/${final_release_id}" \
  > "${final_draft_current}"
jq -e --arg tag "${source_tag}" '
  .tag_name == $tag and
  .draft == true and
  .prerelease == false
' "${final_draft_current}" >/dev/null
validate_release_asset_metadata \
  "${final_draft_current}" "${expected_assets}" false
final_draft_snapshot="${RUNNER_TEMP}/final-draft-snapshot.json"
snapshot_release "${final_draft_current}" "${final_draft_snapshot}"
final_verify_dir="${RUNNER_TEMP}/final-draft-assets"
final_verify_manifest="${RUNNER_TEMP}/final-draft-assets.sha256"
download_assets_by_id \
  "${final_draft_current}" "${expected_assets}" "${final_verify_dir}"
verify_local_asset_set \
  "${final_verify_dir}" "${expected_assets}" "${asset_set_digest}" \
  "${source_tag}" "${final_verify_manifest}"
diff -u "${staging_manifest}" "${final_verify_manifest}"

final_draft_pre_publish="${RUNNER_TEMP}/final-draft-pre-publish.json"
final_draft_pre_publish_snapshot="${RUNNER_TEMP}/final-draft-pre-publish-snapshot.json"
api_json "repos/${target_repository}/releases/${final_release_id}" \
  > "${final_draft_pre_publish}"
snapshot_release \
  "${final_draft_pre_publish}" "${final_draft_pre_publish_snapshot}"
diff -u "${final_draft_snapshot}" "${final_draft_pre_publish_snapshot}" || {
  echo 'Final draft changed while its assets were being verified.' >&2
  exit 2
}

api_json --method PATCH \
  "repos/${target_repository}/releases/${final_release_id}" \
  -F draft=false \
  -F prerelease=false \
  -f make_latest=true \
  > "${RUNNER_TEMP}/publish-response.json"

published_release="${RUNNER_TEMP}/published-release.json"
for attempt in 1 2 3 4 5; do
  api_json "repos/${target_repository}/releases/${final_release_id}" \
    > "${published_release}"
  if jq -e '.draft == false and .immutable == true' \
      "${published_release}" >/dev/null; then
    break
  fi
  if ((attempt == 5)); then
    echo 'Published release did not enter immutable terminal state.' >&2
    exit 2
  fi
  sleep 2
done
verify_published_terminal \
  "${published_release}" "${source_tag}" "${PROMOTION_COMMIT}" \
  "${expected_assets}" "${asset_set_digest}" \
  "${RUNNER_TEMP}/published-assets" true

# Cleanup is intentionally after the exact immutable terminal proof. Failure
# cannot roll back or weaken the final release, so it is reported as a warning.
cleanup_release="${RUNNER_TEMP}/staging-cleanup.json"
if api_json "repos/${target_repository}/releases/${staging_release_id}" \
    > "${cleanup_release}" 2>/dev/null && \
   jq -e --arg tag "${staging_tag}" '
     .tag_name == $tag and .draft == true and .prerelease == true
   ' "${cleanup_release}" >/dev/null; then
  if api_json --method DELETE \
      "repos/${target_repository}/releases/${staging_release_id}" \
      >/dev/null; then
    if ! api_json --method DELETE \
        "repos/${target_repository}/git/refs/tags/${staging_tag}" \
        >/dev/null; then
      echo "::warning::Published release is exact, but staging tag ${staging_tag} remains"
    fi
  else
    echo "::warning::Published release is exact, but staging release ${staging_release_id} remains"
  fi
else
  echo '::warning::Published release is exact, but staging state changed before cleanup'
fi

release_url="$(jq -r '.html_url' "${published_release}")"
{
  echo '### Promoted release published'
  echo
  echo "- Release: [${source_tag}](${release_url})"
  echo "- Promotion PR: [reviewed source-tree change](${promotion_pr_url})"
  echo "- Promotion commit: ${PROMOTION_COMMIT}"
  echo "- Source commit: ${source_sha}"
  echo "- Source workflow: [trusted run](${workflow_run})"
  echo "- Signed candidate tree: ${candidate_tree}"
  echo "- Provenance key: ${provenance_key_id}"
  echo "- 10-asset digest: ${asset_set_digest}"
  echo '- Final release: immutable, latest, and byte-for-byte reverified'
} >> "${GITHUB_STEP_SUMMARY}"
