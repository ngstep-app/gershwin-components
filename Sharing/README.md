# Sharing Preferences Pane

A GNUstep preferences pane for managing remote access services, hostname configuration, and network service discovery (mDNS/DNS-SD).

## Features

- **Hostname Management**: View and modify the system hostname
- **SSH Remote Login**: Enable/disable SSH daemon for remote shell access
- **VNC Screen Sharing**: Enable/disable VNC server for remote desktop access
- **mDNS Service Discovery**: Automatic network service announcement via Bonjour/mDNS
- **Real-time Status**: Automatic status updates showing which services are running
- **Connection Information**: Display IP addresses and connection instructions
- **Reboot Persistence**: Services and announcements restored automatically after reboot (WIP)

## mDNS Service Discovery

Services enabled through the Sharing pane are automatically announced on the local network via mDNS (Multicast DNS / Bonjour), making them discoverable by other devices.

### Service Types Announced
- SSH: `_ssh._tcp.` on port 22
- VNC: `_rfb._tcp.` on port 5900
- SFTP: `_sftp-ssh._tcp.` on port 22

## Architecture

```
SharingPane (NSPreferencePane)
    └── SharingController
            └── sharing-helper (C program with elevated privileges)
```

## Security

- All privileged operations are handled by the separate `sharing-helper` program
- The helper validates all inputs to prevent injection attacks
- Hostname changes follow RFC 1123 naming conventions
- All operations are logged to syslog
- Service control is limited to specific daemons (sshd, VNC)

## Logging

Important events are logged using NSLog and syslog:
- Service start/stop operations
- Hostname changes
- Error conditions
- Permission issues

View logs with:
```bash
# System logs
journalctl -t sharing-helper  # Linux
tail -f /var/log/messages      # BSD

# Application logs
journalctl -t GNUstep          # Linux
```

## Troubleshooting

### Services won't start/stop
- Verify sudo configuration in `/etc/sudoers`
- Check if services are installed (`which sshd`, `which x11vnc`)
- Review system logs for errors
- Ensure you're in the wheel group: `groups`

### Hostname changes don't persist
- On Linux: Check `/etc/hostname` permissions
- On FreeBSD: Check `/etc/rc.conf` permissions
- On OpenBSD: Check `/etc/myname` permissions
- Ensure helper has root privileges

### VNC not starting
VNC requires:
- X11 display server running
- VNC server installed (x11vnc, tigervnc, or tightvnc)
- Proper DISPLAY environment variable

Install VNC server:
```bash
# Debian/Ubuntu
sudo apt install x11vnc

# FreeBSD
sudo pkg install x11vnc

# OpenBSD
sudo pkg_add x11vnc
```

## Files

- `SharingPane.h/m` - Preference pane bundle entry point
- `SharingController.h/m` - UI and service control logic
- `sharing-helper.c` - Privileged operations helper
- `SharingInfo.plist` - Bundle metadata
- `GNUmakefile` - Build configuration
- `Sharing.png` - Icon (128x128 recommended)