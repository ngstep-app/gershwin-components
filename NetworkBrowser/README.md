# NetworkBrowser

A GUI application for discovering and browsing network services advertised via mDNS/DNS-SD (Bonjour).

## Features

- **Service Discovery**: Automatically discovers network services advertised via mDNS/DNS-SD
- **Service List**: Displays all discovered services in a table view (left pane)
- **Service Details**: Shows detailed information about selected services (right pane)
  - Service name, type, and domain
  - Port number
  - IP addresses (IPv4 and IPv6)
  - Host name
  - TXT record properties

## Platform Support

NetworkBrowser is designed to work on multiple platforms:

- **Linux**: Debian/Ubuntu, Fedora/RHEL, and other distributions
- **BSD**: FreeBSD, OpenBSD, and other BSD variants
- **macOS**: Native support through System Framework

## Requirements

### Debian/Ubuntu
```bash
sudo apt-get install libavahi-compat-libdnssd-dev
```

### Fedora/RHEL
```bash
sudo dnf install avahi-compat-libdns_sd-devel
```

### FreeBSD/OpenBSD
```bash
sudo pkg install mDNSResponder
```

## Building

### Prerequisites
- GNUstep Make and libraries installed
- libdns_sd development headers and libraries
- Objective-C compiler (clang or gcc)

## Running

```bash
openapp ./NetworkBrowser.app
# or
./NetworkBrowser.app/NetworkBrowser
```

## Architecture

### Components

1. **NetworkBrowser** (`NetworkBrowser.h/m`)
   - Main application controller
   - Manages the main window and split view
   - Implements NSNetServiceBrowserDelegate to discover services
   - Handles application lifecycle

2. **ServiceListView** (`ServiceListView.h/m`)
   - NSView subclass with embedded NSTableView
   - Displays discovered services in a table
   - Notifies details pane when user selects a service
   - Automatically updates when services appear/disappear

3. **ServiceDetailsView** (`ServiceDetailsView.h/m`)
   - NSView subclass with NSTextView
   - Shows formatted details of selected service
   - Displays addresses, port, hostname, and properties

4. **Main** (`Main.m`)
   - Application entry point
   - Creates NSApplication instance and delegates to NetworkBrowser

## Dependencies

- **Foundation Framework**: NSNetServices, NSNetServiceBrowser
- **AppKit Framework**: NSWindow, NSView, NSTableView, NSTextView, NSSplitView
- **libdns_sd**: Service discovery library (Avahi-compatible on Linux)

## Implementation Details

### Service Discovery
The application uses `NSNetServiceBrowser` to browse for services of type `_services._dns-sd._udp` in the `local` domain. This discovers HTTP services including web servers, embedded devices, and other network services.

### Service Resolution
When a service is discovered, it's automatically resolved to obtain:
- IP addresses (converted from raw socket addresses)
- Port numbers
- Host names
- TXT record properties

### Thread Safety
The application uses GNUstep's autorelease pool system for memory management and properly handles the NSView/NSWindow hierarchy.