/*
 * Minimal /usr/bin/make shim, modeled on Apple's xcode-select tool shim.
 *
 * macOS ships /usr/bin/make as a tiny launcher (libxcselect's tool-shim), not
 * GNU make: it finds the active developer directory and re-execs the real make
 * from Xcode or the Command Line Tools. This reproduces that behavior from
 * source so we can stage our own /usr/bin/make.
 *
 * Developer directory resolution order, matching libxcselect:
 *   1. $DEVELOPER_DIR, if set and non-empty (an .app bundle gets
 *      Contents/Developer appended).
 *   2. The xcode-select setting: /var/select/developer_dir,
 *      /var/db/xcode_select_link, /usr/share/xcode-select/xcode_dir_link
 *      (symlinks) or /usr/share/xcode-select/xcode_dir_path (file holding a path).
 *   3. /Applications/Xcode.app/Contents/Developer, if it exists.
 *   4. /Library/Developer/CommandLineTools, if it exists.
 *
 * The tool is looked up in <dir>/usr/bin, then in the default toolchain, and
 * exec'd with every argument forwarded. The tool name is taken from argv[0]'s
 * basename, so the same binary can be linked under other shimmed names. A
 * candidate that resolves back to this executable is skipped to avoid exec
 * loops. If no tool is found, it prints guidance and exits 1 rather than
 * triggering the OS install prompt.
 */

#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *const SELECT_LINKS[] = {
    "/var/select/developer_dir",
    "/var/db/xcode_select_link",
    "/usr/share/xcode-select/xcode_dir_link",
};

static const char *const DEFAULT_DIRS[] = {
    "/Applications/Xcode.app/Contents/Developer",
    "/Library/Developer/CommandLineTools",
};

static const char *const TOOL_SUBDIRS[] = {
    "usr/bin",
    "Toolchains/XcodeDefault.xctoolchain/usr/bin",
};

static int is_dir(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int ends_with(const char *s, const char *suffix) {
    size_t ls = strlen(s);
    size_t lf = strlen(suffix);
    return ls >= lf && strcmp(s + ls - lf, suffix) == 0;
}

/* Copies `path` into `out`, appending Contents/Developer for .app bundles. */
static int normalize_dir(const char *path, char *out, size_t out_len) {
    char trimmed[PATH_MAX];
    size_t len = strlen(path);

    if (len == 0 || len >= sizeof(trimmed)) {
        return 0;
    }
    memcpy(trimmed, path, len + 1);
    while (len > 1 && trimmed[len - 1] == '/') {
        trimmed[--len] = '\0';
    }

    int n = ends_with(trimmed, ".app")
                ? snprintf(out, out_len, "%s/Contents/Developer", trimmed)
                : snprintf(out, out_len, "%s", trimmed);
    return n > 0 && (size_t)n < out_len;
}

static int read_select_path_file(const char *file, char *out, size_t out_len) {
    FILE *fp = fopen(file, "r");
    if (!fp) {
        return 0;
    }

    char buf[PATH_MAX];
    int ok = 0;
    if (fgets(buf, sizeof(buf), fp)) {
        size_t len = strlen(buf);
        while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
            buf[--len] = '\0';
        }
        ok = normalize_dir(buf, out, out_len);
    }
    fclose(fp);
    return ok;
}

static int resolve_developer_dir(char *out, size_t out_len) {
    const char *env = getenv("DEVELOPER_DIR");
    if (env && *env) {
        return normalize_dir(env, out, out_len);
    }

    for (size_t i = 0; i < sizeof(SELECT_LINKS) / sizeof(SELECT_LINKS[0]); i++) {
        char target[PATH_MAX];
        ssize_t n = readlink(SELECT_LINKS[i], target, sizeof(target) - 1);
        if (n > 0) {
            target[n] = '\0';
            if (normalize_dir(target, out, out_len)) {
                return 1;
            }
        }
    }

    if (read_select_path_file("/usr/share/xcode-select/xcode_dir_path", out, out_len)) {
        return 1;
    }

    for (size_t i = 0; i < sizeof(DEFAULT_DIRS) / sizeof(DEFAULT_DIRS[0]); i++) {
        if (is_dir(DEFAULT_DIRS[i])) {
            return normalize_dir(DEFAULT_DIRS[i], out, out_len);
        }
    }

    return 0;
}

static int is_self(const char *candidate, const char *self_real) {
    char candidate_real[PATH_MAX];
    return self_real[0] != '\0' && realpath(candidate, candidate_real) &&
           strcmp(candidate_real, self_real) == 0;
}

int main(int argc, char **argv) {
    const char *tool = "make";
    if (argc > 0 && argv[0]) {
        const char *slash = strrchr(argv[0], '/');
        tool = slash ? slash + 1 : argv[0];
    }

    char self_real[PATH_MAX] = "";
    char self[PATH_MAX];
    uint32_t self_len = sizeof(self);
    if (_NSGetExecutablePath(self, &self_len) != 0 || !realpath(self, self_real)) {
        self_real[0] = '\0';
    }

    char dev_dir[PATH_MAX];
    if (!resolve_developer_dir(dev_dir, sizeof(dev_dir))) {
        fprintf(stderr,
                "%s: error: unable to find a developer directory.\n"
                "Install the Command Line Tools with `xcode-select --install`, or set DEVELOPER_DIR.\n",
                tool);
        return 1;
    }

    for (size_t i = 0; i < sizeof(TOOL_SUBDIRS) / sizeof(TOOL_SUBDIRS[0]); i++) {
        char path[PATH_MAX];
        int n = snprintf(path, sizeof(path), "%s/%s/%s", dev_dir, TOOL_SUBDIRS[i], tool);
        if (n < 0 || (size_t)n >= sizeof(path)) {
            continue;
        }
        if (access(path, X_OK) != 0 || is_self(path, self_real)) {
            continue;
        }

        argv[0] = path;
        execv(path, argv);
        fprintf(stderr, "%s: failed to exec %s: %s\n", tool, path, strerror(errno));
        return 1;
    }

    fprintf(stderr,
            "%s: error: unable to find utility \"%s\", not a developer tool or in PATH\n"
            "Developer directory: %s\n",
            tool, tool, dev_dir);
    return 1;
}
