/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sharing Helper - Privileged operations for Sharing preference pane
 * 
 * This is a standalone C program that performs operations requiring root privileges.
 * It can be called via sudo/doas or installed as setuid root.
 * 
 * Supported platforms: Linux (systemd), FreeBSD, OpenBSD, NetBSD
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <syslog.h>
#include <ctype.h>

#define MAX_HOSTNAME_LEN 256

/* Platform detection */
#if defined(__linux__)
#define PLATFORM_LINUX 1
#elif defined(__FreeBSD__)
#define PLATFORM_FREEBSD 1
#elif defined(__OpenBSD__)
#define PLATFORM_OPENBSD 1
#elif defined(__NetBSD__)
#define PLATFORM_NETBSD 1
#endif

/* Validate hostname according to RFC 1123 */
static int validate_hostname(const char *hostname)
{
    size_t len = strlen(hostname);
    
    if (len == 0 || len > 63) {
        return 0;
    }
    
    /* Cannot start or end with hyphen */
    if (hostname[0] == '-' || hostname[len-1] == '-') {
        return 0;
    }
    
    /* Only alphanumeric and hyphen allowed */
    for (size_t i = 0; i < len; i++) {
        if (!isalnum(hostname[i]) && hostname[i] != '-') {
            return 0;
        }
    }
    
    return 1;
}

/* Get current hostname */
static void cmd_get_hostname(void)
{
    struct utsname buf;
    
    if (uname(&buf) == 0) {
        printf("%s\n", buf.nodename);
        exit(0);
    } else {
        fprintf(stderr, "Failed to get hostname\n");
        exit(1);
    }
}

/* Set hostname */
static void cmd_set_hostname(const char *hostname)
{
    if (!validate_hostname(hostname)) {
        fprintf(stderr, "Invalid hostname format\n");
        syslog(LOG_ERR, "sharing-helper: Invalid hostname format: %s", hostname);
        exit(1);
    }
    
    syslog(LOG_INFO, "sharing-helper: Setting hostname to: %s", hostname);
    
#ifdef PLATFORM_LINUX
    /* Set hostname using sethostname() */
    if (sethostname(hostname, strlen(hostname)) != 0) {
        perror("sethostname");
        syslog(LOG_ERR, "sharing-helper: Failed to set hostname");
        exit(1);
    }
    
    /* Update /etc/hostname */
    FILE *f = fopen("/etc/hostname", "w");
    if (f) {
        fprintf(f, "%s\n", hostname);
        fclose(f);
    }
    
    /* Try to update /etc/hosts */
    char cmd[512];
    snprintf(cmd, sizeof(cmd), 
             "sed -i 's/127.0.1.1.*/127.0.1.1\\t%s/' /etc/hosts 2>/dev/null || true", 
             hostname);
    system(cmd);
    
#elif defined(PLATFORM_FREEBSD) || defined(PLATFORM_NETBSD)
    /* Set hostname using sethostname() */
    if (sethostname(hostname, strlen(hostname)) != 0) {
        perror("sethostname");
        syslog(LOG_ERR, "sharing-helper: Failed to set hostname");
        exit(1);
    }
    
    /* Update /etc/rc.conf */
    char cmd[512];
    snprintf(cmd, sizeof(cmd), 
             "sysrc hostname=\"%s\" || "
             "(grep -v '^hostname=' /etc/rc.conf > /tmp/rc.conf.tmp && "
             "echo 'hostname=\"%s\"' >> /tmp/rc.conf.tmp && "
             "mv /tmp/rc.conf.tmp /etc/rc.conf)",
             hostname, hostname);
    system(cmd);
    
#elif defined(PLATFORM_OPENBSD)
    /* Set hostname using sethostname() */
    if (sethostname(hostname, strlen(hostname)) != 0) {
        perror("sethostname");
        syslog(LOG_ERR, "sharing-helper: Failed to set hostname");
        exit(1);
    }
    
    /* Update /etc/myname */
    FILE *f = fopen("/etc/myname", "w");
    if (f) {
        fprintf(f, "%s\n", hostname);
        fclose(f);
    }
#endif
    
    syslog(LOG_INFO, "sharing-helper: Hostname set to: %s", hostname);
    printf("Hostname set successfully\n");
    exit(0);
}

/* Check if a service is running */
static int check_service_running(const char *service)
{
#ifdef PLATFORM_LINUX
    char cmd[256];
    
    /* Try systemctl first (systemd) */
    snprintf(cmd, sizeof(cmd), "systemctl is-active %s >/dev/null 2>&1", service);
    if (system(cmd) == 0) {
        return 1;
    }
    
    /* Fall back to service command (sysvinit/upstart) */
    snprintf(cmd, sizeof(cmd), "service %s status >/dev/null 2>&1", service);
    if (system(cmd) == 0) {
        return 1;
    }
    
    /* Check if init script exists and try it directly */
    snprintf(cmd, sizeof(cmd), "/etc/init.d/%s status >/dev/null 2>&1", service);
    return (system(cmd) == 0);
    
#elif defined(PLATFORM_FREEBSD) || defined(PLATFORM_NETBSD)
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "service %s status >/dev/null 2>&1", service);
    return (system(cmd) == 0);
    
#elif defined(PLATFORM_OPENBSD)
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "rcctl check %s >/dev/null 2>&1", service);
    return (system(cmd) == 0);
#endif
    return 0;
}

/* SSH status */
static void cmd_ssh_status(void)
{
#ifdef PLATFORM_LINUX
    /* Check both systemd service names and sysvinit service names */
    if (check_service_running("sshd.service") || 
        check_service_running("ssh.service") ||
        check_service_running("sshd") || 
        check_service_running("ssh")) {
        printf("running\n");
    } else {
        printf("stopped\n");
    }
#else
    if (check_service_running("sshd")) {
        printf("running\n");
    } else {
        printf("stopped\n");
    }
#endif
    exit(0);
}

/* Start SSH */
static void cmd_ssh_start(void)
{
    syslog(LOG_INFO, "sharing-helper: Starting SSH service");
    
#ifdef PLATFORM_LINUX
    /* Try systemctl first (systemd) */
    if (system("which systemctl >/dev/null 2>&1") == 0) {
        if (system("systemctl start sshd.service >/dev/null 2>&1") != 0) {
            system("systemctl start ssh.service >/dev/null 2>&1");
        }
        system("systemctl enable sshd.service >/dev/null 2>&1 || systemctl enable ssh.service >/dev/null 2>&1");
    } else {
        /* Fall back to service command (sysvinit/upstart) */
        if (system("service sshd start >/dev/null 2>&1") != 0) {
            system("service ssh start >/dev/null 2>&1");
        }
        /* Or try init scripts directly */
        if (system("test -x /etc/init.d/sshd") == 0) {
            system("/etc/init.d/sshd start >/dev/null 2>&1");
        } else if (system("test -x /etc/init.d/ssh") == 0) {
            system("/etc/init.d/ssh start >/dev/null 2>&1");
        }
    }
    
#elif defined(PLATFORM_FREEBSD) || defined(PLATFORM_NETBSD)
    system("sysrc sshd_enable=YES");
    system("service sshd start");
    
#elif defined(PLATFORM_OPENBSD)
    system("rcctl enable sshd");
    system("rcctl start sshd");
#endif
    
    syslog(LOG_INFO, "sharing-helper: SSH service started");
    exit(0);
}

/* Stop SSH */
static void cmd_ssh_stop(void)
{
    syslog(LOG_INFO, "sharing-helper: Stopping SSH service");
    
#ifdef PLATFORM_LINUX
    /* Try systemctl first (systemd) */
    if (system("which systemctl >/dev/null 2>&1") == 0) {
        system("systemctl stop sshd.service >/dev/null 2>&1 || systemctl stop ssh.service >/dev/null 2>&1");
    } else {
        /* Fall back to service command (sysvinit/upstart) */
        if (system("service sshd stop >/dev/null 2>&1") != 0) {
            system("service ssh stop >/dev/null 2>&1");
        }
        /* Or try init scripts directly */
        if (system("test -x /etc/init.d/sshd") == 0) {
            system("/etc/init.d/sshd stop >/dev/null 2>&1");
        } else if (system("test -x /etc/init.d/ssh") == 0) {
            system("/etc/init.d/ssh stop >/dev/null 2>&1");
        }
    }
    
#elif defined(PLATFORM_FREEBSD) || defined(PLATFORM_NETBSD)
    system("service sshd stop");
    
#elif defined(PLATFORM_OPENBSD)
    system("rcctl stop sshd");
#endif
    
    syslog(LOG_INFO, "sharing-helper: SSH service stopped");
    exit(0);
}

/* VNC status - checks for various VNC servers */
static void cmd_vnc_status(void)
{
    int running = 0;
    
#ifdef PLATFORM_LINUX
    /* Check for various VNC services */
    running = check_service_running("vncserver@:1.service") ||
              check_service_running("x11vnc.service") ||
              check_service_running("tigervncserver@:1.service") ||
              check_service_running("tightvncserver@:1.service");
    
    /* Also check for running VNC processes */
    if (!running) {
        running = (system("pgrep -x Xvnc >/dev/null 2>&1") == 0) ||
                  (system("pgrep -x x11vnc >/dev/null 2>&1") == 0);
    }
#else
    /* Check for VNC processes on BSD systems */
    running = (system("pgrep -x Xvnc >/dev/null 2>&1") == 0) ||
              (system("pgrep -x x11vnc >/dev/null 2>&1") == 0);
#endif
    
    if (running) {
        printf("running\n");
    } else {
        printf("stopped\n");
    }
    exit(0);
}

/* Start VNC */
static void cmd_vnc_start(void)
{
    syslog(LOG_INFO, "sharing-helper: Starting VNC service");
    
#ifdef PLATFORM_LINUX
    /* Try systemctl first (systemd) */
    if (system("which systemctl >/dev/null 2>&1") == 0) {
        /* Try common VNC service names */
        if (system("systemctl start x11vnc.service >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
        if (system("systemctl start vncserver@:1.service >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
        if (system("systemctl start tigervncserver@:1.service >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    }
    
    /* Try service command (sysvinit/OpenRC/upstart) */
    if (system("service x11vnc start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    if (system("service vncserver start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    
    /* Try init scripts directly */
    if (system("test -x /etc/init.d/x11vnc && /etc/init.d/x11vnc start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    if (system("test -x /etc/init.d/vncserver && /etc/init.d/vncserver start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    
    /* Fall back to starting x11vnc directly if available */
    if (system("which x11vnc >/dev/null 2>&1") == 0) {
        syslog(LOG_WARNING, "sharing-helper: No VNC service found, starting x11vnc directly");
        /* Try various auth locations */
        if (system("x11vnc -display :0 -auth /var/run/xauth -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
        if (system("x11vnc -display :0 -auth /var/run/lightdm/root/:0 -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
        if (system("x11vnc -display :0 -auth /run/user/$(id -u)/gdm/Xauthority -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
        if (system("x11vnc -display :0 -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
        if (system("x11vnc -display :0 -auth guess -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    } else if (system("which vncserver >/dev/null 2>&1") == 0) {
        /* Try TigerVNC or TightVNC server */
        if (system("vncserver :1 >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    }
    
    fprintf(stderr, "Failed to start VNC server\n");
    syslog(LOG_ERR, "sharing-helper: Failed to start VNC server");
    exit(1);
    
#elif defined(PLATFORM_FREEBSD) || defined(PLATFORM_NETBSD)
    /* Try service command */
    if (system("service x11vnc start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    if (system("service vncserver start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    
    /* Try rc.d scripts directly */
    if (system("test -x /usr/local/etc/rc.d/x11vnc && /usr/local/etc/rc.d/x11vnc start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    if (system("test -x /etc/rc.d/vncserver && /etc/rc.d/vncserver start >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    
    /* Fall back to direct start */
    if (system("which x11vnc >/dev/null 2>&1") == 0) {
        syslog(LOG_WARNING, "sharing-helper: No VNC service found, starting x11vnc directly");
        if (system("x11vnc -display :0 -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    } else if (system("which vncserver >/dev/null 2>&1") == 0) {
        if (system("vncserver :1 >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    }
    
    fprintf(stderr, "Failed to start VNC server\n");
    syslog(LOG_ERR, "sharing-helper: Failed to start VNC server");
    exit(1);
    
#elif defined(PLATFORM_OPENBSD)
    /* Try rcctl */
    if (system("rcctl start x11vnc >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    if (system("rcctl start vncserver >/dev/null 2>&1") == 0) {
        goto vnc_started;
    }
    
    /* Fall back to direct start */
    if (system("which x11vnc >/dev/null 2>&1") == 0) {
        syslog(LOG_WARNING, "sharing-helper: No VNC service found, starting x11vnc directly");
        if (system("x11vnc -display :0 -forever -bg -rfbport 5900 -nopw >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    } else if (system("which vncserver >/dev/null 2>&1") == 0) {
        if (system("vncserver :1 >/dev/null 2>&1") == 0) {
            goto vnc_started;
        }
    }
    
    fprintf(stderr, "Failed to start VNC server\n");
    syslog(LOG_ERR, "sharing-helper: Failed to start VNC server");
    exit(1);
#endif

vnc_started:
    syslog(LOG_INFO, "sharing-helper: VNC service started");
    exit(0);
}

/* Stop VNC */
static void cmd_vnc_stop(void)
{
    syslog(LOG_INFO, "sharing-helper: Stopping VNC service");
    
#ifdef PLATFORM_LINUX
    /* Try systemctl first (systemd) */
    if (system("which systemctl >/dev/null 2>&1") == 0) {
        system("systemctl stop x11vnc.service >/dev/null 2>&1");
        system("systemctl stop vncserver@:1.service >/dev/null 2>&1");
        system("systemctl stop tigervncserver@:1.service >/dev/null 2>&1");
    }
    
    /* Try service command (sysvinit/OpenRC/upstart) */
    system("service x11vnc stop >/dev/null 2>&1");
    system("service vncserver stop >/dev/null 2>&1");
    
    /* Try init scripts directly */
    system("test -x /etc/init.d/x11vnc && /etc/init.d/x11vnc stop >/dev/null 2>&1");
    system("test -x /etc/init.d/vncserver && /etc/init.d/vncserver stop >/dev/null 2>&1");
    
    /* Kill any remaining VNC processes */
    system("pkill -x x11vnc >/dev/null 2>&1");
    system("pkill -x Xvnc >/dev/null 2>&1");
    
#elif defined(PLATFORM_FREEBSD) || defined(PLATFORM_NETBSD)
    /* Try service command */
    system("service x11vnc stop >/dev/null 2>&1");
    system("service vncserver stop >/dev/null 2>&1");
    
    /* Try rc.d scripts directly */
    system("test -x /usr/local/etc/rc.d/x11vnc && /usr/local/etc/rc.d/x11vnc stop >/dev/null 2>&1");
    system("test -x /etc/rc.d/vncserver && /etc/rc.d/vncserver stop >/dev/null 2>&1");
    
    /* Kill any remaining processes */
    system("pkill -x x11vnc >/dev/null 2>&1");
    system("pkill -x Xvnc >/dev/null 2>&1");
    system("vncserver -kill :1 >/dev/null 2>&1");
    
#elif defined(PLATFORM_OPENBSD)
    /* Try rcctl */
    system("rcctl stop x11vnc >/dev/null 2>&1");
    system("rcctl stop vncserver >/dev/null 2>&1");
    
    /* Kill any remaining processes */
    system("pkill -x x11vnc >/dev/null 2>&1");
    system("pkill -x Xvnc >/dev/null 2>&1");
    system("vncserver -kill :1 >/dev/null 2>&1");
#endif
    
    syslog(LOG_INFO, "sharing-helper: VNC service stopped");
    exit(0);
}

/* Usage */
static void usage(const char *progname)
{
    fprintf(stderr, "Usage: %s <command> [args]\n", progname);
    fprintf(stderr, "\nCommands:\n");
    fprintf(stderr, "  get-hostname          Get system hostname\n");
    fprintf(stderr, "  set-hostname <name>   Set system hostname\n");
    fprintf(stderr, "  ssh-status            Check SSH daemon status\n");
    fprintf(stderr, "  ssh-start             Start SSH daemon\n");
    fprintf(stderr, "  ssh-stop              Stop SSH daemon\n");
    fprintf(stderr, "  vnc-status            Check VNC server status\n");
    fprintf(stderr, "  vnc-start             Start VNC server\n");
    fprintf(stderr, "  vnc-stop              Stop VNC server\n");
    exit(1);
}

int main(int argc, char *argv[])
{
    openlog("sharing-helper", LOG_PID | LOG_CONS, LOG_USER);
    
    if (argc < 2) {
        usage(argv[0]);
    }
    
    const char *cmd = argv[1];
    
    /* Commands that don't require root */
    if (strcmp(cmd, "get-hostname") == 0) {
        cmd_get_hostname();
    } else if (strcmp(cmd, "ssh-status") == 0) {
        cmd_ssh_status();
    } else if (strcmp(cmd, "vnc-status") == 0) {
        cmd_vnc_status();
    }
    
    /* Commands that require root */
    if (geteuid() != 0) {
        fprintf(stderr, "Error: This operation requires root privileges\n");
        fprintf(stderr, "Please run with sudo: sudo %s %s\n", argv[0], cmd);
        syslog(LOG_ERR, "sharing-helper: Attempted privileged operation without root: %s", cmd);
        exit(1);
    }
    
    if (strcmp(cmd, "set-hostname") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: set-hostname requires a hostname argument\n");
            exit(1);
        }
        cmd_set_hostname(argv[2]);
    } else if (strcmp(cmd, "ssh-start") == 0) {
        cmd_ssh_start();
    } else if (strcmp(cmd, "ssh-stop") == 0) {
        cmd_ssh_stop();
    } else if (strcmp(cmd, "vnc-start") == 0) {
        cmd_vnc_start();
    } else if (strcmp(cmd, "vnc-stop") == 0) {
        cmd_vnc_stop();
    } else {
        fprintf(stderr, "Error: Unknown command: %s\n", cmd);
        usage(argv[0]);
    }
    
    closelog();
    return 0;
}
