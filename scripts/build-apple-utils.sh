#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly ROOT_DIR="${SCRIPT_DIR:h}"
readonly SRC_DIR="${ROOT_DIR}/src"
readonly BUILD_DIR="${ROOT_DIR}/build"
readonly OUT_DIR="${ROOT_DIR}/out"
readonly OUT_BIN_DIR="${OUT_DIR}/bin"
readonly OUT_ROOT_DIR="${OUT_DIR}/root"
readonly WORKTREE_DIR="${BUILD_DIR}/worktrees"
readonly APPLE_OSS_BASE="https://github.com/apple-oss-distributions"
readonly MANIFEST_REPO="${SRC_DIR}/distribution-macOS"
readonly COREOS_REPO="${SRC_DIR}/CoreOSMakefiles"
readonly BUILD_REPORT="${OUT_DIR}/build-report.tsv"
readonly BINARY_MANIFEST="${OUT_DIR}/binaries.tsv"
readonly TARGET_INVENTORY="${OUT_DIR}/targets.tsv"
readonly EXCLUDED_TARGETS="${OUT_DIR}/excluded-targets.tsv"

usage() {
  cat <<'EOF'
Usage:
  scripts/build-apple-utils.sh bootstrap
  scripts/build-apple-utils.sh list
  scripts/build-apple-utils.sh inventory
  scripts/build-apple-utils.sh inventory <repo>...
  scripts/build-apple-utils.sh build all
  scripts/build-apple-utils.sh build bash
  scripts/build-apple-utils.sh build sh
  scripts/build-apple-utils.sh build <repo>
  scripts/build-apple-utils.sh build <repo>:<target>

Notes:
  - Repos are checked out at their latest published tag when one matches <repo>-*.
  - If a repo has no matching tags, the wrapper falls back to the repo's default branch HEAD.
  - "all" means: discover tool targets from Apple OSS repos and build the ones that install into system binary paths.
  - Build results are recorded in out/build-report.tsv and out/binaries.tsv.
  - Inventory output is recorded in out/targets.tsv.
  - Filtered targets are recorded in out/excluded-targets.tsv.
EOF
}

die() {
  print -u2 -- "error: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

filter_lines_by_prefix() {
  local prefix="$1"

  awk -v prefix="${prefix}" 'index($0, prefix) == 1'
}

find_files_matching_pattern() {
  local root="$1"
  local pattern="$2"
  local glob="$3"

  if has_cmd rg; then
    rg -l "${pattern}" "${root}" -g "${glob}"
    return
  fi

  find "${root}" -type f -name "${glob}" -exec grep -l -E "${pattern}" {} + 2>/dev/null || true
}

ensure_dirs() {
  mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${OUT_DIR}" "${OUT_BIN_DIR}" "${OUT_ROOT_DIR}" "${WORKTREE_DIR}"
}

repo_url_for_name() {
  print -- "${APPLE_OSS_BASE}/$1.git"
}

repo_dir_for_name() {
  print -- "${SRC_DIR}/$1"
}

repo_tag_prefix() {
  case "$1" in
    distribution-macOS)
      print -- ""
      ;;
    *)
      print -- "$1-"
      ;;
  esac
}

latest_tag_for_remote() {
  local repo_url="$1"
  local prefix="$2"

  [[ -n "${prefix}" ]] || return 0

  git ls-remote --tags --refs "${repo_url}" \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | filter_lines_by_prefix "${prefix}" \
    | sort -V \
    | tail -n 1
}

checkout_latest_revision() {
  local repo_name="$1"
  local repo_url
  local dest_dir
  local prefix
  local latest_tag
  local resolved_commit

  repo_url="$(repo_url_for_name "${repo_name}")"
  dest_dir="$(repo_dir_for_name "${repo_name}")"
  prefix="$(repo_tag_prefix "${repo_name}")"
  latest_tag="$(latest_tag_for_remote "${repo_url}" "${prefix}" || true)"

  if [[ ! -d "${dest_dir}/.git" ]]; then
    if [[ -n "${latest_tag}" ]]; then
      git clone --depth 1 --branch "${latest_tag}" --single-branch "${repo_url}" "${dest_dir}"
    else
      git clone --depth 1 "${repo_url}" "${dest_dir}"
    fi
  fi

  if [[ -n "${latest_tag}" ]]; then
    git -C "${dest_dir}" fetch --force --depth 1 origin "refs/tags/${latest_tag}:refs/tags/${latest_tag}"
    resolved_commit="$(git -C "${dest_dir}" rev-parse "${latest_tag}^{}")"
  else
    git -C "${dest_dir}" fetch origin --force --depth 1
    git -C "${dest_dir}" remote set-head origin -a >/dev/null 2>&1 || true
    resolved_commit="$(git -C "${dest_dir}" rev-parse origin/HEAD)"
  fi

  git -C "${dest_dir}" checkout --detach "${resolved_commit}" >/dev/null
}

current_repo_ref() {
  git -C "$1" describe --tags --always
}

bootstrap() {
  need_cmd git
  need_cmd plutil
  need_cmd ruby
  ensure_dirs

  checkout_latest_revision "distribution-macOS"
  checkout_latest_revision "CoreOSMakefiles"
}

reset_output_tree() {
  rm -rf "${OUT_BIN_DIR}" "${OUT_ROOT_DIR}"
  mkdir -p "${OUT_BIN_DIR}" "${OUT_ROOT_DIR}"

  {
    print -- "repo\tref\tproject\ttarget\tstatus\tdetail"
  } > "${BUILD_REPORT}"

  {
    print -- "repo\tref\tproject\ttarget\trelpath\tlink_name"
  } > "${BINARY_MANIFEST}"

  {
    print -- "repo\tref\tproject\ttarget\treason"
  } > "${EXCLUDED_TARGETS}"
}

reset_target_inventory() {
  mkdir -p "${OUT_DIR}"
  {
    print -- "repo\tref\tproject\ttarget\tproduct_name\tinstall_path\tfull_product_name"
  } > "${TARGET_INVENTORY}"
  {
    print -- "repo\tref\tproject\ttarget\treason"
  } > "${EXCLUDED_TARGETS}"
}

record_build_status() {
  local repo_name="$1"
  local project_label="$2"
  local target_name="$3"
  local build_status="$4"
  local detail="$5"
  local repo_dir
  local repo_ref

  repo_dir="$(repo_dir_for_name "${repo_name}")"
  repo_ref="$(current_repo_ref "${repo_dir}")"
  print -- "${repo_name}\t${repo_ref}\t${project_label}\t${target_name}\t${build_status}\t${detail}" >> "${BUILD_REPORT}"
}

record_target_exclusion() {
  local repo_name="$1"
  local project_label="$2"
  local target_name="$3"
  local reason="$4"
  local repo_dir
  local repo_ref

  repo_dir="$(repo_dir_for_name "${repo_name}")"
  repo_ref="$(current_repo_ref "${repo_dir}")"
  print -- "${repo_name}\t${repo_ref}\t${project_label}\t${target_name}\t${reason}" >> "${EXCLUDED_TARGETS}"
}

list_targets() {
  cat <<'EOF'
Primary entrypoints:

  make all      -> build all discovered Apple OSS system tool targets
  make inventory -> discover all buildable Apple OSS system tool targets
  make bash     -> build bash only
  make sh       -> build sh only
  make list     -> show this summary

Target selection rules:

  - Repos come from Apple's distribution-macOS manifest.
  - Revisions track the latest published tag for each repo when available.
  - Only PBXNativeTarget command-line tools with non-skipped install paths under /bin, /sbin, /usr/bin, /usr/sbin, or /usr/libexec are included in "all".

Outputs:

  - out/root          staged install tree
  - out/bin           convenience links to staged binaries
  - out/targets.tsv   discovered installable targets across Apple OSS
  - out/excluded-targets.tsv targets filtered for private SDK/internal dependencies
  - out/build-report.tsv
  - out/binaries.tsv
EOF
}

copy_worktree() {
  local name="$1"
  local src="$2"
  local dest="${WORKTREE_DIR}/${name}"

  rm -rf "${dest}"
  mkdir -p "${dest}"
  rsync -a --delete --exclude .git "${src}/" "${dest}/"
  print -- "${dest}"
}

patch_coreos_xcconfigs() {
  local worktree="$1"
  local include_path="${COREOS_REPO}/Xcode/BSD.xcconfig"
  local file

  [[ -f "${include_path}" ]] || die "missing public CoreOS xcconfig at ${include_path}"

  while IFS= read -r file; do
    perl -0pi -e 's{#include "<DEVELOPER_DIR>/Makefiles/CoreOS/Xcode/BSD\.xcconfig"}{#include "'"${include_path}"'"}g' "${file}"
    perl -0pi -e 's{#include "/Makefiles/CoreOS/Xcode/BSD\.xcconfig"}{#include "'"${include_path}"'"}g' "${file}"
  done < <(find_files_matching_pattern "${worktree}" '<DEVELOPER_DIR>/Makefiles/CoreOS/Xcode/BSD\.xcconfig|/Makefiles/CoreOS/Xcode/BSD\.xcconfig' '*.xcconfig')
}

patch_bash_public_sdk_compat() {
  local bash_root="$1"
  local conftypes_h="${bash_root}/bash-3.2/conftypes.h"
  local shell_c="${bash_root}/bash-3.2/shell.c"

  [[ -f "${shell_c}" ]] || die "missing shell.c at ${shell_c}"
  [[ -f "${conftypes_h}" ]] || die "missing conftypes.h at ${conftypes_h}"

  perl -0pi -e 's@#  elif defined\(__arm__\)\n#    define HOSTTYPE "arm"@#  elif defined(__arm64__) || defined(__aarch64__)\n#    define HOSTTYPE "arm64"\n#  elif defined(__arm__)\n#    define HOSTTYPE "arm"@s' "${conftypes_h}"

  perl -0pi -e 's|#if defined\(__APPLE__\)\n#include <get_compat\.h>\n#include <TargetConditionals\.h>\n#include <stdint\.h>\n#include <System/sys/codesign\.h>\n#endif /\* __APPLE__ \*/|#if defined(__APPLE__)\n#include <get_compat.h>\n#include <TargetConditionals.h>\n#include <stdint.h>\n#if __has_include(<System/sys/codesign.h>)\n#include <System/sys/codesign.h>\n#define HAVE_APPLE_CODESIGN_H 1\n#endif\n#endif /* __APPLE__ */|s' "${shell_c}"

  perl -0pi -e 's|#ifdef __APPLE__\nstatic int\nis_rootless_restricted_environment\(void\)\n\{\n\tuint32_t flags;\n\n\tif \(getenv\("APPLE_PKGKIT_ESCALATING_ROOT"\)\)\n\t\treturn 1;\n\tif \(csops\(0, CS_OPS_STATUS, &flags, sizeof\(flags\)\)\)\n\t\treturn -1;\n\treturn \(flags & CS_INSTALLER\) \? 1 : 0;\n\}\n#endif /\* __APPLE__ \*/|#ifdef __APPLE__\nstatic int\nis_rootless_restricted_environment(void)\n{\n#if !defined(HAVE_APPLE_CODESIGN_H)\n\tif (getenv("APPLE_PKGKIT_ESCALATING_ROOT"))\n\t\treturn 1;\n\treturn -1;\n#else\n\tuint32_t flags;\n\n\tif (getenv("APPLE_PKGKIT_ESCALATING_ROOT"))\n\t\treturn 1;\n\tif (csops(0, CS_OPS_STATUS, &flags, sizeof(flags)))\n\t\treturn -1;\n\treturn (flags & CS_INSTALLER) ? 1 : 0;\n#endif\n}\n#endif /* __APPLE__ */|s' "${shell_c}"
}

patch_repo_compat() {
  local repo_name="$1"
  local worktree="$2"

  patch_coreos_xcconfigs "${worktree}"

  case "${repo_name}" in
    bash)
      patch_bash_public_sdk_compat "${worktree}"
      ;;
  esac
}

target_extra_args() {
  local repo_name="$1"
  local target_name="$2"
  local -a args=()

  case "${repo_name}:${target_name}" in
    shell_cmds:sh)
      args+=(SH_INSTALL_PATH=/bin SH_PRODUCT_NAME=sh SH_MAN_PREFIX=/usr)
      ;;
  esac

  print -r -- "${(j:\n:)args}"
}

sanitize_name() {
  print -- "$1" | tr '/ :' '---'
}

run_xcodebuild() {
  local name="$1"
  shift

  local safe_name
  local dstroot
  local symroot
  local objroot
  local module_cache
  local xcode_home

  safe_name="$(sanitize_name "${name}")"
  dstroot="${BUILD_DIR}/dst/${safe_name}"
  symroot="${BUILD_DIR}/sym/${safe_name}"
  objroot="${BUILD_DIR}/obj/${safe_name}"
  module_cache="${BUILD_DIR}/modulecache/${safe_name}"
  xcode_home="${BUILD_DIR}/home/${safe_name}"

  rm -rf "${dstroot}" "${symroot}" "${objroot}" "${module_cache}" "${xcode_home}"
  mkdir -p "${dstroot}" "${symroot}" "${objroot}" "${module_cache}" "${xcode_home}"
  mkdir -p "${xcode_home}/Library/Developer/Xcode/DerivedData"
  mkdir -p "${xcode_home}/Library/Developer/Xcode/Logs"
  mkdir -p "${xcode_home}/Library/Logs/CoreSimulator"

  HOME="${xcode_home}" \
  CFFIXED_USER_HOME="${xcode_home}" \
  xcodebuild \
    "$@" \
    -configuration Release \
    SYMROOT="${symroot}" \
    OBJROOT="${objroot}" \
    DSTROOT="${dstroot}" \
    ARCHS="arm64 x86_64" \
    VALID_ARCHS="arm64 x86_64" \
    CLANG_MODULE_CACHE_PATH="${module_cache}" \
    RC_ProjectSourceVersion="$(date +%Y%m%d%H%M%S)" \
    SDKROOT=macosx
}

manifest_repo_names() {
  [[ -f "${MANIFEST_REPO}/.gitmodules" ]] || die "missing manifest .gitmodules; run bootstrap first"
  sed -n 's/^[[:space:]]*path = //p' "${MANIFEST_REPO}/.gitmodules"
}

project_files_for_repo() {
  local repo_root="$1"
  find "${repo_root}" -type d -name '*.xcodeproj' | sort
}

tool_targets_for_project() {
  local project_file="$1"

  plutil -convert json -o - "${project_file}/project.pbxproj" \
    | ruby -rjson -e 'j = JSON.parse(STDIN.read); j["objects"].each_value { |o| next unless o["isa"] == "PBXNativeTarget" && o["productType"] == "com.apple.product-type.tool"; puts o["name"] }' \
    | sort -u
}

target_private_dependency_reason() {
  local project_file="$1"
  local target_name="$2"
  local repo_root="$3"

  plutil -convert json -o - "${project_file}/project.pbxproj" \
    | ruby -rjson -rset -e '
        project_file, target_name, repo_root = ARGV
        project_dir = File.dirname(project_file)
        data = JSON.parse(STDIN.read)
        objects = data.fetch("objects")
        parents = {}

        objects.each do |id, obj|
          children = obj["children"] || obj["files"] || []
          children.each { |child| parents[child] ||= id }
        end

        def object_path(objects, parents, id)
          obj = objects[id]
          return nil unless obj

          source_tree = obj["sourceTree"] || "<group>"
          path = obj["path"] || obj["name"]

          case source_tree
          when "<group>"
            parent = parents[id]
            parent_path = parent ? object_path(objects, parents, parent) : nil
            return path if parent_path.nil? || parent_path.empty?
            return parent_path if path.nil? || path.empty?
            File.join(parent_path, path)
          when "SOURCE_ROOT"
            path
          else
            path
          end
        end

        target = objects.values.find { |obj| obj["isa"] == "PBXNativeTarget" && obj["name"] == target_name }
        exit 0 unless target

        source_files = []
        (target["buildPhases"] || []).each do |phase_id|
          phase = objects[phase_id]
          next unless phase && phase["isa"] == "PBXSourcesBuildPhase"

          (phase["files"] || []).each do |build_file_id|
            build_file = objects[build_file_id]
            next unless build_file
            file_ref = objects[build_file["fileRef"]]
            next unless file_ref

            rel = file_ref["path"] || object_path(objects, parents, build_file["fileRef"])
            next if rel.nil? || rel.empty?
            next if rel.include?("$(")

            full = File.expand_path(rel, project_dir)
            source_files << full if File.file?(full)
          end
        end

        seen = Set.new
        queue = source_files.dup
        private_header = /^\s*#\s*(?:include|import)\s+[<"]((?:[^">]*\/private(?:\.h|\/[^">]*\.h))|(?:[^">]*Private[^">]*\.h))[">]/
        private_path = %r{/System/Library/PrivateFrameworks/|/AppleInternal/|PrivateHeaders}

        until queue.empty?
          path = queue.shift
          next if seen.include?(path)
          seen << path

          text = File.read(path)

          text.each_line do |line|
            if (match = private_header.match(line))
              puts "includes #{match[1]}"
              exit 0
            end
          end

          if text.match?(private_path)
            puts "references private SDK paths"
            exit 0
          end

          text.scan(/^\s*#\s*(?:include|import)\s+"([^"]+)"/).flatten.each do |include_name|
            next if include_name.empty?
            child = File.expand_path(include_name, File.dirname(path))
            next unless child.start_with?(repo_root + "/")
            next unless File.file?(child)
            queue << child
          end
        end
      ' "${project_file}" "${target_name}" "${repo_root}"
}

resolved_target_info() {
  local repo_name="$1"
  local project_file="$2"
  local target_name="$3"
  local extra_args_text
  local -a extra_args=()
  local output
  local install_path
  local skip_install
  local product_name
  local full_product_name

  extra_args_text="$(target_extra_args "${repo_name}" "${target_name}")"
  if [[ -n "${extra_args_text}" ]]; then
    extra_args=("${(@f)extra_args_text}")
  fi

  if ! output="$(run_xcodebuild "settings-${repo_name}-${target_name}" -project "${project_file}" -target "${target_name}" "${extra_args[@]}" -showBuildSettings 2>/dev/null)"; then
    return 1
  fi

  install_path="$(print -- "${output}" | sed -n 's/^[[:space:]]*INSTALL_PATH = //p' | tail -n 1)"
  skip_install="$(print -- "${output}" | sed -n 's/^[[:space:]]*SKIP_INSTALL = //p' | tail -n 1)"
  product_name="$(print -- "${output}" | sed -n 's/^[[:space:]]*PRODUCT_NAME = //p' | tail -n 1)"
  full_product_name="$(print -- "${output}" | sed -n 's/^[[:space:]]*FULL_PRODUCT_NAME = //p' | tail -n 1)"

  print -- "${install_path}\t${skip_install}\t${product_name}\t${full_product_name}"
}

target_is_system_install() {
  local install_path="$1"
  local skip_install="$2"

  [[ "${skip_install}" != "YES" ]] || return 1
  [[ "${install_path}" =~ '^/(bin|sbin|usr/bin|usr/sbin|usr/libexec)(/|$)' ]]
}

discover_installable_targets_in_repo() {
  local repo_name="$1"
  local worktree="$2"
  local project_file
  local target_name
  local info
  local install_path
  local skip_install
  local product_name
  local full_product_name
  local private_reason
  local project_label

  while IFS= read -r project_file; do
    while IFS= read -r target_name; do
      [[ -n "${target_name}" ]] || continue

      if ! info="$(resolved_target_info "${repo_name}" "${project_file}" "${target_name}")"; then
        continue
      fi

      IFS=$'\t' read -r install_path skip_install product_name full_product_name <<< "${info}"
      if target_is_system_install "${install_path}" "${skip_install}"; then
        project_label="${project_file#$worktree/}"
        private_reason="$(target_private_dependency_reason "${project_file}" "${target_name}" "${worktree}" || true)"
        if [[ -n "${private_reason}" ]]; then
          record_target_exclusion "${repo_name}" "${project_label}" "${target_name}" "${private_reason}"
          continue
        fi

        print -- "${project_file}\t${target_name}\t${product_name}\t${install_path}\t${full_product_name}"
      fi
    done < <(tool_targets_for_project "${project_file}")
  done < <(project_files_for_repo "${worktree}")
}

inventory_repo_targets() {
  local repo_name="$1"
  local repo_dir
  local worktree
  local line
  local project_file
  local target_name
  local product_name
  local install_path
  local full_product_name
  local project_label
  local repo_ref

  checkout_latest_revision "${repo_name}"
  repo_dir="$(repo_dir_for_name "${repo_name}")"
  repo_ref="$(current_repo_ref "${repo_dir}")"
  worktree="$(copy_worktree "inventory-${repo_name}" "${repo_dir}")"
  patch_repo_compat "${repo_name}" "${worktree}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    IFS=$'\t' read -r project_file target_name product_name install_path full_product_name <<< "${line}"
    project_label="${project_file#$worktree/}"
    print -- "${repo_name}\t${repo_ref}\t${project_label}\t${target_name}\t${product_name}\t${install_path}\t${full_product_name}" >> "${TARGET_INVENTORY}"
  done < <(discover_installable_targets_in_repo "${repo_name}" "${worktree}")
}

inventory_all_targets() {
  local -a requested_repos=("$@")
  local repo_name

  need_cmd git
  need_cmd rsync
  need_cmd plutil
  need_cmd ruby
  need_cmd xcodebuild
  ensure_dirs
  bootstrap
  reset_target_inventory

  if [[ "${#requested_repos[@]}" -gt 0 ]]; then
    for repo_name in "${requested_repos[@]}"; do
      inventory_repo_targets "${repo_name}"
    done
    return 0
  fi

  while IFS= read -r repo_name; do
    [[ -n "${repo_name}" ]] || continue
    inventory_repo_targets "${repo_name}"
  done < <(manifest_repo_names)
}

choose_output_link_name() {
  local rel_path="$1"
  local base_name="${rel_path:t}"
  local expected="../root/${rel_path}"
  local existing_path="${OUT_BIN_DIR}/${base_name}"

  if [[ -L "${existing_path}" ]] && [[ "$(readlink "${existing_path}")" == "${expected}" ]]; then
    print -- "${base_name}"
    return
  fi

  if [[ ! -e "${existing_path}" ]]; then
    print -- "${base_name}"
    return
  fi

  print -- "${${rel_path//\//__}// /_}"
}

stage_installed_root() {
  local repo_name="$1"
  local project_label="$2"
  local target_name="$3"
  local installed_root="$4"
  local repo_dir
  local repo_ref
  local search_dir
  local link_name
  local rel_path

  repo_dir="$(repo_dir_for_name "${repo_name}")"
  repo_ref="$(current_repo_ref "${repo_dir}")"

  rsync -a "${installed_root}/" "${OUT_ROOT_DIR}/"

  for search_dir in bin sbin usr/bin usr/sbin usr/libexec; do
    [[ -d "${installed_root}/${search_dir}" ]] || continue

    while IFS= read -r -d '' rel_path; do
      link_name="$(choose_output_link_name "${rel_path}")"
      rm -f "${OUT_BIN_DIR}/${link_name}"
      ln -s "../root/${rel_path}" "${OUT_BIN_DIR}/${link_name}"
      print -- "${repo_name}\t${repo_ref}\t${project_label}\t${target_name}\t${rel_path}\t${link_name}" >> "${BINARY_MANIFEST}"
    done < <(cd "${installed_root}" && find "${search_dir}" \( -type f -o -type l \) -print0)
  done
}

build_one_target() {
  local repo_name="$1"
  local worktree="$2"
  local project_file="$3"
  local target_name="$4"
  local project_label="$5"
  local extra_args_text
  local -a extra_args=()
  local build_key
  local dstroot

  extra_args_text="$(target_extra_args "${repo_name}" "${target_name}")"
  if [[ -n "${extra_args_text}" ]]; then
    extra_args=("${(@f)extra_args_text}")
  fi

  build_key="${repo_name}-${target_name}"
  dstroot="${BUILD_DIR}/dst/$(sanitize_name "${build_key}")"

  if run_xcodebuild "${build_key}" -project "${project_file}" -target "${target_name}" "${extra_args[@]}" install; then
    stage_installed_root "${repo_name}" "${project_label}" "${target_name}" "${dstroot}"
    record_build_status "${repo_name}" "${project_label}" "${target_name}" "OK" "built and staged"
    return 0
  fi

  record_build_status "${repo_name}" "${project_label}" "${target_name}" "FAIL" "xcodebuild install failed"
  return 1
}

build_repo_targets() {
  local repo_name="$1"
  shift || true

  local repo_dir
  local worktree
  local project_file
  local target_name
  local product_name
  local install_path
  local full_product_name
  local project_label
  local line
  local -a requested_targets=("$@")
  local -a discovered=()
  local include_target
  local failures=0

  checkout_latest_revision "${repo_name}"
  repo_dir="$(repo_dir_for_name "${repo_name}")"
  worktree="$(copy_worktree "${repo_name}" "${repo_dir}")"
  patch_repo_compat "${repo_name}" "${worktree}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    discovered+=("${line}")
  done < <(discover_installable_targets_in_repo "${repo_name}" "${worktree}")

  if [[ "${#discovered[@]}" -eq 0 ]]; then
    record_build_status "${repo_name}" "-" "-" "SKIP" "no buildable public-SDK system tool targets discovered"
    return 0
  fi

  for line in "${discovered[@]}"; do
    IFS=$'\t' read -r project_file target_name product_name install_path full_product_name <<< "${line}"
    project_label="${project_file#$worktree/}"
    include_target=1

    if [[ "${#requested_targets[@]}" -gt 0 ]]; then
      include_target=0
      if (( ${requested_targets[(Ie)${target_name}]} )); then
        include_target=1
      fi
    fi

    (( include_target )) || continue

    if ! build_one_target "${repo_name}" "${worktree}" "${project_file}" "${target_name}" "${project_label}"; then
      failures=$((failures + 1))
    fi
  done

  return "${failures}"
}

build_all_targets() {
  local repo_name
  local failures=0

  while IFS= read -r repo_name; do
    [[ -n "${repo_name}" ]] || continue

    if ! build_repo_targets "${repo_name}"; then
      failures=$((failures + 1))
    fi
  done < <(manifest_repo_names)

  return "${failures}"
}

build_targets() {
  local spec
  local repo_name
  local target_name
  local failures=0

  need_cmd git
  need_cmd rsync
  need_cmd plutil
  need_cmd ruby
  need_cmd xcodebuild
  ensure_dirs
  reset_output_tree
  bootstrap

  if [[ "$#" -eq 0 ]]; then
    set -- all
  fi

  for spec in "$@"; do
    case "${spec}" in
      all)
        if ! build_all_targets; then
          failures=$((failures + 1))
        fi
        ;;
      bash)
        if ! build_repo_targets "bash" "bash"; then
          failures=$((failures + 1))
        fi
        ;;
      sh)
        if ! build_repo_targets "shell_cmds" "sh"; then
          failures=$((failures + 1))
        fi
        ;;
      *:*)
        repo_name="${spec%%:*}"
        target_name="${spec#*:}"
        if ! build_repo_targets "${repo_name}" "${target_name}"; then
          failures=$((failures + 1))
        fi
        ;;
      *)
        if ! build_repo_targets "${spec}"; then
          failures=$((failures + 1))
        fi
        ;;
    esac
  done

  if [[ "${failures}" -ne 0 ]]; then
    die "one or more repo builds failed; see ${BUILD_REPORT}"
  fi
}

main() {
  local action="${1:-}"
  shift || true

  case "${action}" in
    bootstrap)
      bootstrap
      ;;
    list)
      list_targets
      ;;
    inventory)
      inventory_all_targets "$@"
      ;;
    build)
      build_targets "$@"
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      usage
      die "unknown action: ${action}"
      ;;
  esac
}

main "$@"
