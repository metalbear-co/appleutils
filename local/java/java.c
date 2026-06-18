/*
 * Minimal /usr/bin/java shim, modeled on Apple's stub launcher.
 *
 * macOS ships /usr/bin/java as a tiny locator stub, not a JDK: it finds an
 * installed Java runtime and re-execs into it. This reproduces that behavior
 * from source so we can stage our own /usr/bin/java.
 *
 * Resolution order:
 *   1. $JAVA_HOME, if set and non-empty.
 *   2. /usr/libexec/java_home (the same helper Apple's stub relies on).
 *
 * It then execs <home>/bin/<tool>, forwarding every argument. The tool name is
 * taken from argv[0]'s basename, so the same binary can be linked as java,
 * javac, jar, etc. If no runtime is found, it prints guidance and exits 1
 * rather than crashing -- same spirit as the OS stub's install prompt.
 */

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char *resolve_java_home(void) {
    const char *env = getenv("JAVA_HOME");
    if (env && *env) {
        return strdup(env);
    }

    FILE *fp = popen("/usr/libexec/java_home 2>/dev/null", "r");
    if (!fp) {
        return NULL;
    }

    char buf[PATH_MAX];
    char *home = NULL;
    if (fgets(buf, sizeof(buf), fp)) {
        size_t len = strlen(buf);
        while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
            buf[--len] = '\0';
        }
        if (len > 0) {
            home = strdup(buf);
        }
    }
    pclose(fp);
    return home;
}

int main(int argc, char **argv) {
    const char *tool = "java";
    if (argc > 0 && argv[0]) {
        const char *slash = strrchr(argv[0], '/');
        tool = slash ? slash + 1 : argv[0];
    }

    char *home = resolve_java_home();
    if (!home) {
        fprintf(stderr,
                "Unable to locate a Java runtime.\n"
                "Set JAVA_HOME, or install a JDK and ensure /usr/libexec/java_home can find it.\n");
        return 1;
    }

    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/bin/%s", home, tool);
    free(home);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        fprintf(stderr, "%s: resolved launcher path too long\n", tool);
        return 1;
    }

    argv[0] = path;
    execv(path, argv);

    fprintf(stderr, "%s: failed to exec %s: %s\n", tool, path, strerror(errno));
    return 1;
}
