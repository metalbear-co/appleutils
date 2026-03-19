#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly ROOT_DIR="${SCRIPT_DIR:h}"
readonly OUT_DIR="${ROOT_DIR}/out"
readonly OUT_ROOT_DIR="${OUT_DIR}/root"
readonly BINARY_MANIFEST="${OUT_DIR}/binaries.tsv"
readonly SIGNED_REPORT="${OUT_DIR}/signed-binaries.tsv"
readonly PACKAGE_ROOT="${OUT_DIR}/release-package"
readonly ALLOWED_RELATIVE_ROOTS_REGEX='^(bin|sbin|usr/bin|usr/sbin)/'

usage() {
  cat <<'EOF'
Usage:
  scripts/package-release-licenses.sh

Notes:
  - Creates out/release-package from the current out/root tree.
  - Only includes signed Mach-O binaries under /bin, /sbin, /usr/bin, and /usr/sbin.
  - Keeps top-level LICENSE and NOTICE.md.
  - Excludes docs, tests, plists, libexec helpers, and all other non-binary files.
EOF
}

die() {
  print -u2 -- "error: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

copy_release_entry() {
  local relpath="$1"
  local src_path="${OUT_ROOT_DIR}/${relpath}"
  local dest_path="${PACKAGE_ROOT}/${relpath}"

  [[ -e "${src_path}" ]] || return 0
  mkdir -p "${dest_path:h}"
  cp -a "${src_path}" "${dest_path}"
}

main() {
  local line
  local relpath
  local sign_status
  local file_desc
  local copied_count=0
  local -A seen_paths=()

  need_cmd cp
  need_cmd file
  [[ -d "${OUT_ROOT_DIR}" ]] || die "missing ${OUT_ROOT_DIR}; build a target first"
  [[ -f "${BINARY_MANIFEST}" ]] || die "missing ${BINARY_MANIFEST}; build a target first"
  [[ -f "${ROOT_DIR}/LICENSE" ]] || die "missing top-level LICENSE"
  [[ -f "${ROOT_DIR}/NOTICE.md" ]] || die "missing top-level NOTICE.md"

  rm -rf "${PACKAGE_ROOT}"
  mkdir -p "${PACKAGE_ROOT}"
  cp "${ROOT_DIR}/LICENSE" "${PACKAGE_ROOT}/LICENSE"
  cp "${ROOT_DIR}/NOTICE.md" "${PACKAGE_ROOT}/NOTICE.md"

  if [[ -f "${SIGNED_REPORT}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      [[ "${line}" != "relpath"$'\t'* ]] || continue

      IFS=$'\t' read -r relpath _link_name _bundle_id sign_status _detail <<< "${line}"
      [[ "${sign_status}" == "OK" ]] || continue
      [[ "${relpath}" =~ ${ALLOWED_RELATIVE_ROOTS_REGEX} ]] || continue
      [[ "${relpath}" != *$'\n'* ]] || continue
      [[ -z "${seen_paths[${relpath}]:-}" ]] || continue

      seen_paths["${relpath}"]=1
      copy_release_entry "${relpath}"
      copied_count=$((copied_count + 1))
    done < "${SIGNED_REPORT}"
  else
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      [[ "${line}" != "repo"$'\t'* ]] || continue

      IFS=$'\t' read -r _repo _ref _project _target relpath _link_name <<< "${line}"
      [[ -n "${relpath}" ]] || continue
      [[ "${relpath}" =~ ${ALLOWED_RELATIVE_ROOTS_REGEX} ]] || continue
      [[ "${relpath}" != *$'\n'* ]] || continue
      [[ -z "${seen_paths[${relpath}]:-}" ]] || continue
      [[ -f "${OUT_ROOT_DIR}/${relpath}" ]] || continue

      file_desc="$(file -Lb "${OUT_ROOT_DIR}/${relpath}")"
      [[ "${file_desc}" == *Mach-O* ]] || continue

      seen_paths["${relpath}"]=1
      copy_release_entry "${relpath}"
      copied_count=$((copied_count + 1))
    done < "${BINARY_MANIFEST}"
  fi

  (( copied_count > 0 )) || die "no release binaries were packaged"
}

main "$@"
