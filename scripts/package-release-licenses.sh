#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly ROOT_DIR="${SCRIPT_DIR:h}"
readonly SRC_DIR="${ROOT_DIR}/src"
readonly OUT_DIR="${ROOT_DIR}/out"
readonly OUT_ROOT_DIR="${OUT_DIR}/root"
readonly BINARY_MANIFEST="${OUT_DIR}/binaries.tsv"
readonly PACKAGE_ROOT="${OUT_DIR}/release-package"
readonly LICENSE_BUNDLE_DIR="${PACKAGE_ROOT}/LICENSES"
readonly LICENSE_MANIFEST="${LICENSE_BUNDLE_DIR}/manifest.tsv"

usage() {
  cat <<'EOF'
Usage:
  scripts/package-release-licenses.sh

Notes:
  - Creates out/release-package from the current out/root tree.
  - Bundles top-level repository licensing files and upstream license files
    for repos that produced binaries in out/binaries.tsv.
EOF
}

die() {
  print -u2 -- "error: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

copy_license_files_for_repo() {
  local repo_name="$1"
  local repo_dir="${SRC_DIR}/${repo_name}"
  local dest_dir="${LICENSE_BUNDLE_DIR}/upstream/${repo_name}"
  local file
  local rel
  local copied=0

  [[ -d "${repo_dir}" ]] || return 0

  while IFS= read -r -d '' file; do
    rel="${file#${repo_dir}/}"
    mkdir -p "${dest_dir}/${rel:h}"
    cp "${file}" "${dest_dir}/${rel}"
    print -- "${repo_name}\t${rel}" >> "${LICENSE_MANIFEST}"
    copied=1
  done < <(
    find "${repo_dir}" -type f \
      \( -iname 'APPLE_LICENSE' \
      -o -iname 'LICENSE' \
      -o -iname 'LICENSE.*' \
      -o -iname 'COPYING' \
      -o -iname 'COPYING.*' \
      -o -iname 'NOTICE' \
      -o -iname 'NOTICE.*' \) \
      -print0
  )

  if (( copied == 0 )); then
    print -- "${repo_name}\t(no matching license files found)" >> "${LICENSE_MANIFEST}"
  fi
}

main() {
  local line
  local repo_name
  local -A repos=()

  need_cmd rsync
  [[ -d "${OUT_ROOT_DIR}" ]] || die "missing ${OUT_ROOT_DIR}; build a target first"
  [[ -f "${BINARY_MANIFEST}" ]] || die "missing ${BINARY_MANIFEST}; build a target first"
  [[ -f "${ROOT_DIR}/LICENSE" ]] || die "missing top-level LICENSE"
  [[ -f "${ROOT_DIR}/NOTICE.md" ]] || die "missing top-level NOTICE.md"

  rm -rf "${PACKAGE_ROOT}"
  mkdir -p "${LICENSE_BUNDLE_DIR}/upstream"

  rsync -a "${OUT_ROOT_DIR}/" "${PACKAGE_ROOT}/"
  cp "${ROOT_DIR}/LICENSE" "${PACKAGE_ROOT}/LICENSE"
  cp "${ROOT_DIR}/NOTICE.md" "${PACKAGE_ROOT}/NOTICE.md"

  {
    print -- "repo\trelpath"
  } > "${LICENSE_MANIFEST}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" != "repo"$'\t'* ]] || continue
    repo_name="${line%%$'\t'*}"
    repos["${repo_name}"]=1
  done < "${BINARY_MANIFEST}"

  for repo_name in "${(@k)repos}"; do
    copy_license_files_for_repo "${repo_name}"
  done
}

main "$@"
