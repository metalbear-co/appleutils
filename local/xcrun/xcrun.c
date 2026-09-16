/*
 * Minimal /usr/bin/xcrun shim, modeled on Apple's xcode-select tool shims.
 *
 * macOS ships xcrun and developer tools such as make, git, clang and python3
 * in /usr/bin as identical tiny launchers. Each one hands its argv to
 * libxcselect's xcselect_invoke_xcrun, which resolves the active developer
 * directory (DEVELOPER_DIR, the xcode-select setting, Xcode.app, then
 * CommandLineTools) and execs the real tool from there, or offers to install
 * the command line tools when none are present.
 *
 * The system launchers carry only x86_64 and arm64e slices, so a copy without
 * SIP restrictions can only run under Rosetta, where it fails to load the
 * arm64-only libxcrun.dylib from CommandLineTools. This builds the same
 * launcher with a plain arm64 slice, calling the same libxcselect entry point
 * so resolution matches the OS exactly.
 *
 * The tool name comes from getprogname(), so one binary is staged under every
 * shim name: invoked as xcrun it behaves like xcrun, invoked as make it runs
 * make.
 */

#include <stdlib.h>
#include <string.h>

/* Exported by /usr/lib/libxcselect.dylib but not declared in the SDK header. */
extern int xcselect_invoke_xcrun(const char *tool_name, int argc, char *const *argv,
                                 int flags);

int main(int argc, char *argv[]) {
    const char *name = getprogname();
    /* Login shells prefix argv[0] with '-'. */
    if (name[0] == '-') {
        name++;
    }

    /* A NULL tool name makes libxcselect behave as xcrun itself. */
    const char *tool_name = strcasecmp(name, "xcrun") == 0 ? NULL : name;
    return xcselect_invoke_xcrun(tool_name, argc - 1, argv + 1, 0);
}
