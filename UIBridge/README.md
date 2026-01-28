# UIBridge

UIBridge is a runtime control plane for GNUstep applications, enabling developers and autonomous agents to inspect, manipulate, and automate GUI applications. By injecting a lightweight agent into the target process, UIBridge exposes the live Objective-C object graph through a Model Context Protocol (MCP) interface.

## Key Features

- **Non-Invasive Inspection**: Injects into running processes using `LD_PRELOAD`, requiring zero changes to the target application's source code or build process.
- **Dynamic Object Access**: Provides direct access to live AppKit objects, including windows, views, and menus, using a stable pointer-based identity system.
- **Remote Execution**: Supports invoking arbitrary selectors on remote objects, enabling sophisticated automation and state manipulation.
- **System Integration**: Combines high-level AppKit introspection with low-level X11 window management and LLDB-based process debugging.
- **Agent Ready**: Designed specifically for AI-driven workflows, providing a deterministic and semantic interface for LLMs.

## Components

The UIBridge architecture consists of three core layers:

- **UIBridge Agent**: A dynamic library (`libUIBridgeAgent.so`) that runs within the target application's memory space, providing access to the Objective-C runtime via Distributed Objects.
- **UIBridge Server**: An MCP-compliant coordinator that manages the lifecycle of target applications and proxies requests between clients and agents.
- **Common Interface**: A shared protocol definition that ensures type-safe communication and consistent serialization of Objective-C objects.

## Documentation

For detailed information on how UIBridge works and how to use it, see:

- [Architecture Guide](ARCHITECTURE.md): Deep dive into the injection mechanism, object registry, and communication protocols.
- [Usage Guide](USAGE.md): Instructions for installation, building, and interacting with the system using MCP tools.