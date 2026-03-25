# Apple OSS utility builder

This workspace wraps Apple's public OSS repos into a manifest-driven build flow for Apple-published command-line binaries.
It tracks the latest published tag for each repo when one matches the repo name, instead of Apple's manifest-pinned submodule commits.

What the wrapper does:

- clones `distribution-macOS` and uses its repo list as the source of truth
- checks out the latest published tag for each repo where possible
- discovers Xcode command-line tool targets automatically
- builds only targets that install into system binary locations like `/bin`, `/usr/bin`, `/usr/sbin`, and `/usr/libexec`
- can inventory those installable targets without building them all first

Direct shortcuts:

- `bash`: Apple-shipped, GPLv2, built from the latest `bash-*` tag
- `sh`: Apple-shipped, but BSD-derived and built from the latest `shell_cmds-*` tag

## Usage

```sh
make bootstrap
make inventory
make all
make bash
make sh
make list
```

Artifacts land in:

- `out/bin`
- `out/fail-logs`
- `out/root`
- `out/release-package`
- `out/targets.tsv`
- `out/excluded-targets.tsv`
- `out/build-report.tsv`
- `out/binaries.tsv`

`make inventory` resolves the manifest at latest tags and writes the full discovered installable target list to `out/targets.tsv`.
Targets that are filtered out because they include private SDK/internal dependencies, or match the checked-in CI exclusion seed in `config/excluded-target-patterns.tsv`, are written to `out/excluded-targets.tsv`.
`make all` is best-effort across the manifest, prints one `OK` or `FAIL` line per attempted target, and records per-target success or failure in `out/build-report.tsv`.
Failed target logs are written to `out/fail-logs`.
`make bash` and `make sh` remain explicit shortcuts for the shell binaries you started with.

## GitHub Releases

One manual GitHub Actions workflow is included:

- `.github/workflows/release-all.yml`

The workflow:

- runs `make all`
- uploads `out/fail-logs` and the TSV reports as a workflow artifact even if the build step fails
- signs each built Mach-O output with `Developer ID Application: METALBEAR TECH LTD (8W42TQ6PFA)`
- signs without Hardened Runtime by default, so loader-based injection like `DYLD_INSERT_LIBRARIES` remains available
- uses bundle IDs in the form `com.metalbear.UTILNAME`
- publishes a GitHub release asset as `apple-utils-<tag>.tar.gz` containing only signed binaries under `/bin`, `/sbin`, `/usr/bin`, and `/usr/sbin`, plus the top-level `LICENSE` and `NOTICE.md`

Note:

- `/usr/libexec` is another common system executable location on macOS, but it is intentionally excluded from the release tarball right now.

Required repository secrets:

- `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`
- `APPLE_DEVELOPER_CERTIFICATE_PASSWORD`

For a narrower scan while you are iterating, you can inventory specific repos:

```sh
./scripts/build-apple-utils.sh inventory shell_cmds text_cmds awk
```

You can also build all discovered system-tool targets from a single repo with:

```sh
./scripts/build-apple-utils.sh build text_cmds
./scripts/build-apple-utils.sh build shell_cmds
./scripts/build-apple-utils.sh build awk
```

## Prerequisites

- Xcode with a working `xcodebuild`
- `git`
- `rsync`
- `ruby`
- `plutil`

Notes:

- The wrapper patches `CoreOSMakefiles` includes in temporary worktrees so original checkouts stay clean.
- `bash` also gets two temporary public-SDK compatibility fixes for current Xcode: missing public `codesign.h` handling and modern `arm64` host-type detection.
- Set `ENABLE_HARDENED_RUNTIME=1` when invoking `scripts/sign-built-utils.sh` if you need to restore the previous runtime-signing behavior.
