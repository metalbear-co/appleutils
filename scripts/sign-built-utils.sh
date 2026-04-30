#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly ROOT_DIR="${SCRIPT_DIR:h}"
readonly OUT_DIR="${ROOT_DIR}/out"
readonly OUT_ROOT_DIR="${OUT_DIR}/root"
readonly BINARY_MANIFEST="${OUT_DIR}/binaries.tsv"
readonly SIGNED_REPORT="${OUT_DIR}/signed-binaries.tsv"
readonly DEFAULT_BUNDLE_PREFIX="com.metalbear"
readonly ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-0}"

usage() {
  cat <<'EOF'
Usage:
  scripts/sign-built-utils.sh <application-identity> [bundle-prefix]

Notes:
  - Signs Mach-O binaries staged under out/root from the current build.
  - Bundle IDs are generated as <bundle-prefix>.<utilname>.
  - Hardened Runtime is disabled by default so DYLD_INSERT_LIBRARIES keeps working.
  - Set ENABLE_HARDENED_RUNTIME=1 to add the runtime option back.
  - Non-Mach-O files are skipped and recorded in out/signed-binaries.tsv.
EOF
}

die() {
  print -u2 -- "error: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

main() {
  local identity="${1:-}"
  local bundle_prefix="${2:-${DEFAULT_BUNDLE_PREFIX}}"
  local line
  local relpath
  local link_name
  local target_path
  local util_name
  local bundle_id
  local file_desc
  local signed_count=0
  local -a codesign_args
  local -A seen_paths=()

  [[ -n "${identity}" ]] || {
    usage
    die "missing application identity"
  }

  need_cmd codesign
  need_cmd file
  [[ -f "${BINARY_MANIFEST}" ]] || die "missing ${BINARY_MANIFEST}; build a target first"

  codesign_args=(
    --force
    --timestamp
    --sign "${identity}"
  )
  if [[ "${ENABLE_HARDENED_RUNTIME}" == "1" ]]; then
    codesign_args+=(--options runtime)
  fi

  {
    print -- "relpath\tlink_name\tbundle_id\tstatus\tdetail"
  } > "${SIGNED_REPORT}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" != "repo"$'\t'* ]] || continue

    IFS=$'\t' read -r _repo _ref _project _target relpath link_name <<< "${line}"
    [[ -n "${relpath}" ]] || continue

    if [[ -n "${seen_paths[${relpath}]:-}" ]]; then
      continue
    fi
    seen_paths["${relpath}"]=1

    target_path="${OUT_ROOT_DIR}/${relpath}"
    [[ -f "${target_path}" ]] || continue

    file_desc="$(file -b "${target_path}")"
    util_name="${${relpath:t}:l}"
    bundle_id="${bundle_prefix}.${util_name}"

    if [[ "${file_desc}" != *Mach-O* ]]; then
      print -- "${relpath}\t${link_name}\t${bundle_id}\tSKIP\tnon-Mach-O (${file_desc})" >> "${SIGNED_REPORT}"
      continue
    fi

    codesign \
      "${codesign_args[@]}" \
      --identifier "mirrord" \
      "${target_path}"

    codesign --verify --verbose=2 "${target_path}"
    print -- "${relpath}\t${link_name}\t${bundle_id}\tOK\tsigned" >> "${SIGNED_REPORT}"
    signed_count=$((signed_count + 1))
  done < "${BINARY_MANIFEST}"

  (( signed_count > 0 )) || die "no Mach-O binaries were signed"
}

main "$@"
