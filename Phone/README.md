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

Phone depends on a number of system libraries and build tools. Below are **tested** install commands for Debian-based systems and FreeBSD (pkg). If your distribution does not provide `libre`/`baresip` packages, build them from source (instructions below).

### Debian / Ubuntu (example)

Run as root or via sudo:

```sh
sudo -E apt update && sudo -E apt -y install \
    build-essential clang cmake pkg-config gdb g++ \
    gnustep-make libgnustep-base-dev \
    libdispatch-dev libasound2-dev portaudio19-dev libjack-jackd2-dev \
    libssl-dev libpng-dev libx11-dev libxext-dev \
    libavcodec-dev libavformat-dev libavutil-dev libopus-dev libvpx-dev libaom-dev \
    libsndfile1-dev
```

# Optional (install only if you need PulseAudio support or GTK-based modules):
# sudo -E apt -y install libpulse-dev libgtk-3-dev libglib2.0-dev libpango1.0-dev libcairo2-dev

Notes:
- Package names can vary between distributions and releases. If a package (for example `libdispatch-dev`) is not available, install from your distribution's backports or build it from source.
- `libre` (the RE library) and `baresip` are not always packaged on Debian/Ubuntu; build from source below if they're missing.

### FreeBSD (verified package names)

Run as root (uses `sudo -E pkg`):

```sh
sudo -E pkg update
sudo -E pkg install -y \
    gmake pkgconf cmake portaudio jackit \
    openssl png pkgconf ffmpeg aom libvpx libopus portaudio sndfile
```

Notes:
- On FreeBSD `jack` is distributed as `jackit`; `libpng` appears as `png`.
- `libre` and `baresip` may not be available as binary packages in your repo; building from source is shown below.

---

## Build from source: `re` (libre) and `baresip`

If your platform does not have `libre` / `baresip` packages, build and install them into `/usr/local`:

```sh
# Build libre (aka 're')
git clone --depth 1 https://github.com/baresip/re.git /tmp/re-src
cd /tmp/re-src
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build build -j$(nproc)
sudo -E cmake --install build --prefix /usr/local

# Build baresip (exclude Linux-only modules on non-Linux platforms)
git clone --depth 1 https://github.com/baresip/baresip.git /tmp/baresip-src
cd /tmp/baresip-src
# If building on FreeBSD, exclude Linux-only modules like evdev and v4l2
# Example: pass MODULES without evdev/v4l2 (see baresip cmake/modules.cmake)
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local -DMODULES="account;alsa;...;x11"
cmake --build build -j$(nproc)
sudo -E cmake --install build --prefix /usr/local
```

After installing into `/usr/local`, headers will appear under `/usr/local/include/re` and libs under `/usr/local/lib` which `Phone` will use during build.

---

## FreeBSD specific notes / gotchas

- I verified and used the following while testing on FreeBSD:
  - `jack` → installed via `jackit`
  - `libpng` → package name `png`
  - `libre` / `baresip` were built from source and installed to `/usr/local` (no binary pkg in my repo).
- GUI-related packages (GTK, GLib, Pango, Cairo) are **not required** for Phone itself (it uses GNUstep for the UI). Install GTK only if you plan to build specific `baresip` modules that depend on it.
- PulseAudio / PipeWire are **optional** audio backends — Phone primarily uses ALSA/PortAudio/JACK. Install Pulse/pipewire only if you need those backends.
- There is a symbol conflict on FreeBSD between the system `hexdump` and `re`'s `hexdump` prototype. A small compile-time workaround was added in `SIPManager.m` using a temporary local renaming of the `hexdump` symbol while including `<re/re.h>` (see comments in file).

---

## Build Instructions

1. Ensure the system packages (above) are installed and that `re` / `baresip` are available (either via pkg/apt or built & installed into `/usr/local`).
2. Build Phone:

```sh
cd ershwin-components/Phone
gmake
```

The build requires `libre`/`baresip` to be available; see the sections above for installing via packages or building from source.



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

## Known Issues

- Threading issues.