# UIBridge Usage Guide

This guide provides instructions for building, running, and interacting with UIBridge in a GNUstep environment.

## Prerequisites

Before using UIBridge, ensure your system has the following installed:
- **GNUstep Core**: `gnustep-base`, `gnustep-gui`, and `gnustep-make`.
- **System Libraries**: `libX11-dev`, `libXext-dev`.
- **Debugging Tools**: `lldb` (required for `lldb_exec`).

## Installation

UIBridge consists of two main targets: the Agent and the Server. They should be built in the following order:

### 1. Build the Agent
The Agent is the component injected into target applications.
```bash
cd Agent
make
```
Successful build produces `obj/libUIBridgeAgent.so`.

### 2. Build the Server
The Server coordinates the agent and provides the MCP interface.
```bash
cd ../Server
make
```
Successful build produces `obj/UIBridgeServer`.

### Installing to system locations (optional)

You can install the agent and server to a chosen GNUstep domain (requires root for system domains):

```bash
sudo make install -C Agent
sudo make install -C Server
```

The server will be installed to `Library/Tools/UIBridgeServer` of the chosen domain and the agent will be installed to `Library/Libraries/libUIBridgeAgent.so` of the chosen domain (for example: `/System`, `/Local`, or a user domain like `~`). The Makefiles respect `GNUSTEP_SYSTEM_TOOLS` for the Tools directory and `GNUSTEP_SYSTEM_LIBRARIES` for the libraries directory when these are set in your GNUstep environment; otherwise they fall back to `/System/Library/Tools` and `/System/Library/Libraries` respectively. Installing to the domain's `Library/Tools` directory ensures `UIBridgeServer` is available on the user PATH.

## Running UIBridge

UIBridge is designed to be used as a Model Context Protocol (MCP) server. It can be integrated into AI agent environments or run manually for diagnostic purposes.

### Manual Execution
To start the server manually:
```bash
./obj/UIBridgeServer
```

### VSCode integration

In the project's `.vscode/mcp.json` add the `uibridge` MCP server like this:

```
{
  "servers": {
    "uibridge": {
      "type": "stdio",
      "command": "/System/Library/Tools/UIBridgeServer",
      "args": []
    }
  }
}
```

Then you should have `uibridge` available under Tools in the Chat panel.

### Logging
All internal diagnostic logs are written to `/tmp/uibridge.log` to prevent polluting the MCP `stdout` stream. You can monitor the logs in real-time:
```bash
tail -f /tmp/uibridge.log
```

## Core Tool Reference

UIBridge exposes several tools via its MCP interface for application lifecycle management and UI introspection.

### Application Lifecycle

#### `launch_app`
Launches a GNUstep application with the UIBridge Agent automatically injected.
- **Arguments**: `app_path` (Absolute path to the `.app` bundle or executable).
- **Returns**: PID and launch status.

#### `list_apps`
Lists all available GNUstep applications found in standard system directories.

### UI Introspection

#### `get_root`
Retrieves the root objects of the target application.
- **Returns**: `object_id` for `NSApp` and a list of open windows.

#### `get_object_details`
Fetches detailed state for a specific object.
- **Arguments**: `object_id` (e.g., `objc:0x123456`).
- **Returns**: Class name, frame (if view), titles, and child objects.

#### `list_menus`
Retrieves the entire menu hierarchy of the application.

### Interaction & Control

#### `invoke_selector`
Invokes a specific Objective-C selector on a remote object.
- **Arguments**: `object_id`, `selector` (e.g., `setTitle:`), `args` (optional array of arguments).

#### `invoke_menu_item`
Triggers the action associated with an `NSMenuItem`.
- **Arguments**: `object_id`.

### System-Level Tools

#### `x11_list_windows` / `x11_window_info`
Query low-level X11 window tree and geometry.

#### `x11_mouse_move` / `x11_click` / `x11_type`
Simulate hardware input events directly via the X server.

#### `lldb_exec`
Executes an arbitrary command via LLDB attached to the target process. Use this for deep state analysis or memory inspection.
