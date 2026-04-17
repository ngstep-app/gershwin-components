/*
 * Copyright (c) 2026
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "CrashHandler.h"

#import <execinfo.h>
#import <fcntl.h>
#import <signal.h>
#import <stdarg.h>
#import <stdbool.h>
#import <stdio.h>
#import <string.h>
#import <sys/resource.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <time.h>
#import <unistd.h>

#ifdef __linux__
#import <sys/prctl.h>
#endif

static int gCrashLogFD = -1;
static volatile sig_atomic_t gHandlingFatalSignal = 0;
static stack_t gSignalAltStack;

static void menuSafeWriteString(const char *s)
{
    if (!s) {
        return;
    }

    size_t len = strlen(s);
    while (len > 0) {
        ssize_t written = write(gCrashLogFD >= 0 ? gCrashLogFD : STDERR_FILENO, s, len);
        if (written <= 0) {
            break;
        }
        s += written;
        len -= (size_t)written;
    }
}

static void menuSafeWriteUInt(unsigned int value)
{
    char buf[32];
    unsigned int i = 0;

    if (value == 0) {
        menuSafeWriteString("0");
        return;
    }

    while (value > 0 && i < sizeof(buf)) {
        buf[i++] = (char)('0' + (value % 10U));
        value /= 10U;
    }

    while (i > 0) {
        char c = buf[--i];
        (void)write(gCrashLogFD >= 0 ? gCrashLogFD : STDERR_FILENO, &c, 1);
    }
}

static void menuWriteTimestampPrefix(void)
{
    char ts[128];
    time_t now = time(NULL);
    struct tm tmNow;

    if (now == (time_t)-1) {
        return;
    }
    if (localtime_r(&now, &tmNow) == NULL) {
        return;
    }
    if (strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S %z", &tmNow) == 0) {
        return;
    }

    menuSafeWriteString("[");
    menuSafeWriteString(ts);
    menuSafeWriteString("] ");
}

static void menuLogLine(const char *fmt, ...)
{
    char line[1024];
    va_list args;
    int n;

    va_start(args, fmt);
    n = vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);

    if (n <= 0) {
        return;
    }

    menuWriteTimestampPrefix();
    menuSafeWriteString(line);
    menuSafeWriteString("\n");
}

static void menuFatalSignalHandler(int sig, siginfo_t *info, void *context)
{
    (void)context;

    if (gHandlingFatalSignal) {
        _exit(128 + sig);
    }
    gHandlingFatalSignal = 1;

    menuSafeWriteString("\n=== Menu.app fatal signal ===\n");
    menuSafeWriteString("signal=");
    menuSafeWriteUInt((unsigned int)sig);
    if (info) {
        menuSafeWriteString(" code=");
        menuSafeWriteUInt((unsigned int)info->si_code);
        menuSafeWriteString(" pid=");
        menuSafeWriteUInt((unsigned int)info->si_pid);
    }
    menuSafeWriteString("\n");

    void *frames[64];
    int count = backtrace(frames, (int)(sizeof(frames) / sizeof(frames[0])));
    if (count > 0) {
        backtrace_symbols_fd(frames, count, gCrashLogFD >= 0 ? gCrashLogFD : STDERR_FILENO);
    }

    menuSafeWriteString("=== End fatal signal report ===\n");

    signal(sig, SIG_DFL);
    raise(sig);
    _exit(128 + sig);
}

static void menuUncaughtExceptionHandler(NSException *exception)
{
    @autoreleasepool {
        menuLogLine("=== Menu.app uncaught exception ===");
        menuLogLine("name=%s", [[exception name] UTF8String]);
        menuLogLine("reason=%s", [[exception reason] UTF8String]);

        NSArray *stack = [exception callStackSymbols];
        NSUInteger i;
        for (i = 0; i < [stack count]; i++) {
            NSString *line = [stack objectAtIndex:i];
            menuLogLine("stack[%u]=%s", (unsigned int)i, [line UTF8String]);
        }

        menuLogLine("Aborting after uncaught exception to preserve core dump.");
    }

    abort();
}

static void menuEnableCoreDumps(void)
{
    struct rlimit rl;

    if (getrlimit(RLIMIT_CORE, &rl) == 0) {
        rl.rlim_cur = rl.rlim_max;
        if (rl.rlim_cur == RLIM_INFINITY || rl.rlim_cur > 0) {
            if (setrlimit(RLIMIT_CORE, &rl) == 0) {
                menuLogLine("Core dumps enabled (RLIMIT_CORE=%llu)", (unsigned long long)rl.rlim_cur);
            } else {
                menuLogLine("Warning: failed to set RLIMIT_CORE");
            }
        }
    } else {
        menuLogLine("Warning: failed to read RLIMIT_CORE");
    }

#ifdef __linux__
    if (prctl(PR_SET_DUMPABLE, 1, 0, 0, 0) != 0) {
        menuLogLine("Warning: prctl(PR_SET_DUMPABLE) failed");
    }
#endif
}

static void menuInstallFatalSignalHandlers(void)
{
    static const int fatalSignals[] = {SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP};
    struct sigaction action;
    size_t i;

    memset(&action, 0, sizeof(action));
    action.sa_sigaction = menuFatalSignalHandler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK;

    // Use an alternate stack so stack-overflow crashes can still be logged.
    memset(&gSignalAltStack, 0, sizeof(gSignalAltStack));
    gSignalAltStack.ss_sp = malloc(SIGSTKSZ * 2U);
    gSignalAltStack.ss_size = (size_t)SIGSTKSZ * 2U;
    gSignalAltStack.ss_flags = 0;
    if (gSignalAltStack.ss_sp != NULL) {
        if (sigaltstack(&gSignalAltStack, NULL) != 0) {
            menuLogLine("Warning: sigaltstack installation failed");
        }
    } else {
        menuLogLine("Warning: failed to allocate alternate signal stack");
    }

    for (i = 0; i < sizeof(fatalSignals) / sizeof(fatalSignals[0]); i++) {
        if (sigaction(fatalSignals[i], &action, NULL) != 0) {
            menuLogLine("Warning: failed to install handler for signal %u", (unsigned int)fatalSignals[i]);
        }
    }
}

void MenuInstallCrashHandlers(void)
{
    const char *path = getenv("MENU_CRASH_LOG");

    if (!path || path[0] == '\0') {
        path = "/tmp/Menu.app.crash.log";
    }

    gCrashLogFD = open(path, O_CREAT | O_APPEND | O_WRONLY, 0644);
    if (gCrashLogFD < 0) {
        gCrashLogFD = STDERR_FILENO;
    }

    menuLogLine("Installing crash handlers (log=%s)", path);

    menuEnableCoreDumps();
    NSSetUncaughtExceptionHandler(menuUncaughtExceptionHandler);
    menuInstallFatalSignalHandlers();
}
