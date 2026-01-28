# Phone (WIP)

A SIP-based VoIP phone application built with GNUstep and Baresip.

## Description

Phone is a simple SIP phone client that allows making and receiving VoIP calls over SIP networks. It integrates with Asterisk PBX and other SIP servers.

**Note:** This is a work-in-progress project. Features may be incomplete or unstable.

## Features

- SIP registration and authentication
- Making outgoing calls
- Receiving incoming calls
- Audio input/output via ALSA
- Preferences panel for SIP configuration
- Real-time logging and SIP trace output

## Dependencies

- GNUstep (Base, GUI)
- Baresip SIP stack
- Libre (networking library)
- ALSA (for audio)

## Build Instructions

1. Ensure GNUstep is installed and configured.
2. Navigate to the Phone directory:
   ```
   cd /home/pi/gershwin-build/repos/gershwin-components/Phone
   ```
3. Build the application:
   ```
   gmake
   ```

## Usage

1. Run the application:
   ```
   ./Phone.app/Phone
   ```
2. Configure SIP settings in Preferences:
   - Server: SIP server address (e.g., 192.168.0.10)
   - Username: SIP extension (e.g., 201)
   - Password: SIP password
3. The app will attempt to register with the SIP server.
4. Use the UI to make calls or answer incoming ones.

## Configuration

Settings are stored in NSUserDefaults. Key settings include:
- SIPServer
- SIPUsername
- SIPPassword
- AudioInput (default: alsa)
- AudioOutput (default: alsa)

## Known Issues

- Threading issues.

## Contributing

This is an active development project. Report issues or contribute via the Gershwin project.