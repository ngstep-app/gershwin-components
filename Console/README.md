# Console

Console is a comprehensive system log viewer application that allows users to search, monitor, and filter system and application logs. It provides real-time log viewing with powerful query capabilities.

## Features

### Core Functionality
- **Real-time Log Viewing**: Monitor system and application logs as they are generated
- **Log List Sidebar**: Unified view of all system logs from various sources
- **System Log Queries**: Pre-configured queries for common log monitoring tasks
- **Custom Queries**: Create filtered views with user-defined criteria
- **Search and Filter**: Advanced search capabilities across all log sources
- **Alert System**: Notifications when specific log patterns are detected
- **Detailed Reports**: Expandable log entries with full details

### Log Format
All logs are displayed with uniform formatting:
- **Timestamp**: When the event occurred
- **Process/Application**: Source of the log message
- **Message**: The actual log content
- **Details**: Expandable full reports (indicated by paperclip icon)

## Cross-Platform Support

Console works seamlessly across multiple platforms:

### Linux
- **systemd-based**: Reads from journald via `journalctl`
- **Non-systemd**: Reads traditional log files from `/var/log/`
- Supports syslog, rsyslog, and other logging systems

### BSD Systems
- FreeBSD, OpenBSD, NetBSD support
- Reads from `/var/log/` and system logging facilities
- Compatible with BSD syslogd

## Architecture

### Components

#### LogSource
Abstract interface for different log sources. Implementations include:
- `SystemdLogSource`: journald integration for systemd systems
- `SyslogLogSource`: Traditional syslog file parsing
- `ApplicationLogSource`: Application-specific log files
- `KernelLogSource`: Kernel ring buffer (dmesg)

#### LogEntry
Represents a single log message with:
- Timestamp
- Process/application name
- Priority/severity level
- Message content
- Optional detailed report

#### LogQuery
Defines filtering criteria:
- Process name patterns
- Time ranges
- Priority levels
- Custom regex patterns
- Boolean combinations

#### ConsoleController
Main application controller managing:
- Log source management
- UI coordination
- Query execution
- Alert monitoring

### Log Sources by Platform

#### Linux with systemd
- `journalctl --follow --all --output=json`
- Unified journal for system and user services
- Structured logging with metadata

#### Linux without systemd
- `/var/log/syslog` or `/var/log/messages`: System logs
- `/var/log/auth.log`: Authentication logs
- `/var/log/kern.log`: Kernel logs
- `/var/log/*.log`: Various application logs
- `dmesg`: Kernel ring buffer

#### BSD Systems
- `/var/log/messages`: Main system log
- `/var/log/auth.log`: Authentication
- `/var/log/daemon.log`: System daemons
- `/var/log/debug.log`: Debug messages
- `/var/log/console.log`: Console messages

## Usage

### Viewing Logs

1. Launch Console
2. Select "Show Log List" from toolbar to display the sidebar
3. Choose a log category from the list
4. Logs are displayed in the main view with live updates

### Creating Custom Queries

1. Select **File > New System Log Query**
2. Define filter criteria:
   - Process name or pattern
   - Time range
   - Priority level (Emergency, Alert, Critical, Error, Warning, Notice, Info, Debug)
   - Custom regex pattern
3. Name your query
4. Query appears in the Log List sidebar

### Setting Up Alerts

1. Create a custom query with desired filter criteria
2. Enable "Alert on Match" option
3. Configure notification method (badge, sound, notification center)

### Searching Logs

- Use the search field in the toolbar for quick filtering
- Search applies to currently selected log view
- Supports regex patterns when enabled in preferences

## Implementation Details

### Thread Safety
- Log reading occurs on background threads
- UI updates dispatched to main thread
- Thread-safe log entry queue

### Performance Optimizations
- Circular buffer for log entries (prevents unbounded memory growth)
- Lazy loading of detailed reports
- Indexed search for large log files
- Efficient tail -f style file watching

### Platform Detection
Runtime detection determines available log sources:
- Check for `/run/systemd/system` → systemd present
- Check for `/var/run/dmesg.boot` → BSD system
- Fallback to traditional syslog files

## File Structure

```
Console/
├── README.md
├── GNUmakefile
├── ConsoleController.h
├── ConsoleController.m
├── LogSource.h
├── LogSource.m
├── LogEntry.h
├── LogEntry.m
├── LogQuery.h
├── LogQuery.m
├── ConsoleWindowController.h
├── ConsoleWindowController.m
├── main.m
└── Resources/
```