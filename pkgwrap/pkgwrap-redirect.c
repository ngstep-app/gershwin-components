/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * pkgwrap-redirect.so — LD_PRELOAD library that transparently redirects
 * filesystem paths from system locations (/usr/share/, /usr/lib/, etc.)
 * into a pkgwrap .app bundle's Contents/ directory.
 *
 * Environment: BUNDLE_CONTENTS must point to the bundle's Contents/ dir.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/syscall.h>
#include <limits.h>
#include <stdarg.h>

/* Bundle contents prefix, read once at load time */
static char   g_bundle[PATH_MAX];
static size_t g_bundle_len;

/* Real libc function pointers */
static int     (*real_open)(const char *, int, ...);
static int     (*real_openat)(int, const char *, int, ...);
static FILE   *(*real_fopen)(const char *, const char *);
static DIR    *(*real_opendir)(const char *);
static void   *(*real_dlopen)(const char *, int);

__attribute__((constructor))
static void pkgwrap_init(void)
{
    const char *env = getenv("BUNDLE_CONTENTS");
    if (!env || !env[0]) {
        g_bundle_len = 0;
        return;
    }
    g_bundle_len = strlen(env);
    if (g_bundle_len >= PATH_MAX - 1) {
        g_bundle_len = 0;
        return;
    }
    memcpy(g_bundle, env, g_bundle_len);
    /* Strip trailing slash */
    while (g_bundle_len > 1 && g_bundle[g_bundle_len - 1] == '/')
        g_bundle_len--;
    g_bundle[g_bundle_len] = '\0';

    real_open    = dlsym(RTLD_NEXT, "open");
    real_openat  = dlsym(RTLD_NEXT, "openat");
    real_fopen   = dlsym(RTLD_NEXT, "fopen");
    real_opendir = dlsym(RTLD_NEXT, "opendir");
    real_dlopen  = dlsym(RTLD_NEXT, "dlopen");
}

/*
 * Try to redirect |path| into the bundle.  Returns a pointer to |buf|
 * on success, or NULL if the path should not be redirected.
 *
 * Redirect rules:
 *   - Only absolute paths starting with /usr/share/, /usr/lib/,
 *     /usr/libexec/, or /etc/ are candidates.
 *   - Paths already under BUNDLE_CONTENTS are skipped.
 *   - The redirect is only applied if the target exists in the bundle
 *     (checked with raw faccessat syscall to avoid interception).
 */
static const char *
redirect(const char *path, char *buf, size_t bufsz)
{
    if (!g_bundle_len || !path || path[0] != '/')
        return NULL;

    /* Skip paths already inside the bundle */
    if (strncmp(path, g_bundle, g_bundle_len) == 0)
        return NULL;

    /* Check for redirectable prefixes */
    int match = 0;
    if      (strncmp(path, "/usr/share/",   11) == 0) match = 1;
    else if (strncmp(path, "/usr/lib/",      9) == 0) match = 1;
    else if (strncmp(path, "/usr/libexec/", 13) == 0) match = 1;
    else if (strncmp(path, "/etc/",          5) == 0) match = 1;
    if (!match)
        return NULL;

    /* Build candidate: ${BUNDLE_CONTENTS}${path} */
    size_t plen = strlen(path);
    if (g_bundle_len + plen + 1 > bufsz)
        return NULL;

    memcpy(buf, g_bundle, g_bundle_len);
    memcpy(buf + g_bundle_len, path, plen + 1);

    /* Only redirect if the file actually exists in the bundle.
     * Use raw syscall to avoid any glibc wrapper interception issues. */
    int exists = syscall(SYS_faccessat, AT_FDCWD, buf, F_OK, 0);

    return (exists == 0) ? buf : NULL;
}

/* ── Intercepted functions ────────────────────────────────────────── */

int open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT
#ifdef O_TMPFILE
                 | O_TMPFILE
#endif
                )) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, unsigned int);
        va_end(ap);
    }
    char buf[PATH_MAX];
    const char *rp = redirect(path, buf, sizeof(buf));

    return real_open(rp ? rp : path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT
#ifdef O_TMPFILE
                 | O_TMPFILE
#endif
                )) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, unsigned int);
        va_end(ap);
    }
    char buf[PATH_MAX];
    const char *rp = redirect(path, buf, sizeof(buf));

    return real_openat(dirfd, rp ? rp : path, flags, mode);
}

FILE *fopen(const char *path, const char *mode)
{
    char buf[PATH_MAX];
    const char *rp = redirect(path, buf, sizeof(buf));

    return real_fopen(rp ? rp : path, mode);
}


DIR *opendir(const char *path)
{
    char buf[PATH_MAX];
    const char *rp = redirect(path, buf, sizeof(buf));
    return real_opendir(rp ? rp : path);
}

void *dlopen(const char *path, int flags)
{
    char buf[PATH_MAX];
    const char *rp = NULL;
    if (path)
        rp = redirect(path, buf, sizeof(buf));
    return real_dlopen(rp ? rp : path, flags);
}
