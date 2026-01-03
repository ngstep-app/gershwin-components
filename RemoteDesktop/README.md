# RemoteDesktop

A GNUstep application that provides remote desktop connectivity to VNC and RDP services on the network.

## Features

- **Network Service Discovery**: Automatically discovers VNC (`_rfb._tcp`) and RDP (`_rdp._tcp`) services on the local network using mDNS/DNS-SD (Bonjour/Avahi)
- **VNC Client**: Connect to VNC servers using libvncclient
- **RDP Client**: Connect to RDP servers (Windows Remote Desktop) using FreeRDP
- **Manual Connection**: Enter hostname/IP, port, and credentials to connect to any remote desktop
- **Full Input Support**: Keyboard and mouse input forwarding to remote sessions
- **Multi-session**: Open multiple remote desktop connections simultaneously

## Requirements

### Build Dependencies

- GNUstep Make and Base/GUI frameworks
- libvncclient (from libvncserver package) - for VNC support
- FreeRDP 2 or 3 - for RDP support
- Avahi (libavahi-compat-libdnssd-dev) - for network service discovery

### Installing Dependencies

On Debian/Ubuntu:
```bash
sudo apt install libvncserver-dev freerdp2-dev libavahi-compat-libdnssd-dev
```

On FreeBSD:
```bash
sudo pkg install libvncserver freerdp avahi
```

## Building

```bash
. /Developer/Makefiles/GNUstep.sh
make
```

## Running

```bash
openapp ./RemoteDesktop.app
```

Or after installation:
```bash
RemoteDesktop
```

## Usage

### Automatic Discovery

When the application starts, it automatically begins scanning for VNC and RDP services advertised on the local network. Discovered services appear in the left panel.

- **Double-click** a service to connect
- Or select a service and click **Connect**

### Manual Connection

Use the right panel to manually connect to a remote host:

1. Select the **Protocol** (VNC or RDP)
2. Enter the **Host** (hostname or IP address)
3. Optionally enter the **Port** (defaults to 5900 for VNC, 3389 for RDP)
4. For RDP, optionally enter **Username** and **Password**
5. For VNC, optionally enter the **Password**
6. Click **Connect**

## Architecture

The application consists of several components:

- **RemoteDesktop**: Main application controller with service discovery and UI
- **VNCClient/VNCWindow**: VNC protocol implementation using libvncclient
- **RDPClient/RDPWindow**: RDP protocol implementation using FreeRDP
- **RemoteService**: Model class for discovered network services

## Protocol Notes

### Network Service Discovery

The application automatically discovers remote desktop services on the local network using mDNS/DNS-SD (Bonjour/Avahi). Services are discovered by their service type:

- **VNC Services**: Announced as `_rfb._tcp` (Remote Frame Buffer protocol)
- **RDP Services**: Announced as `_rdp._tcp` (Remote Desktop Protocol)

#### Duplicate Service Handling

The application automatically detects and removes duplicate service entries that may occur when:
- The same service is announced multiple times on the network
- Multiple service names resolve to the same hostname and port

Duplicate detection works by comparing the resolved hostname, port, and service type. This ensures a clean service list even when hosts are coming and going dynamically.

#### Windows RDP Service Discovery

By default, Windows computers **do not announce RDP services via mDNS/DNS-SD** on the network. However, the RemoteDesktop application can still discover and connect to Windows RDP services if:

1. **Third-party mDNS Announcer**: A tool running on the Windows machine announces RDP as `_rdp._tcp` service (e.g., Home2, Avahi on Windows, or similar)
2. **Manual Connection**: Enter the Windows hostname or IP address directly in the "Manual Connection" panel

If you have a Windows machine with a proper mDNS/DNS-SD announcer configured, it will appear automatically in the service list.

### VNC (Virtual Network Computing)

- Default port: 5900
- Supports password authentication
- Uses RFB (Remote Frame Buffer) protocol
- Works with any VNC server (TightVNC, RealVNC, TigerVNC, macOS Screen Sharing, etc.)

#### macOS VNC Password Configuration

To control a Mac over VNC, enable the "additional" VNC password in the Mac's system preferences. Interestingly, this password is never actually needed for the connection to work.

### RDP (Remote Desktop Protocol)

- Default port: 3389
- Supports username/password/domain authentication
- Microsoft's protocol for Windows Remote Desktop
- Works with Windows RDP servers and xrdp on Linux

## License

BSD-2-Clause

Copyright (c) 2025 Simon Peter
