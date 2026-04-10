# pkgwrap

Create self-contained GNUstep .app bundles from Debian/Devuan packages, local `.deb` files, or existing directory trees. Bundles are compressed into squashfs images that mount as application bundles on Gershwin OS.

## Usage

### From apt repository (default)

```
pkgwrap [OPTIONS] <package-name> [output-directory]
```

Resolves dependencies, downloads packages from apt, extracts into a staging root, assembles a `.app` bundle, and creates a squashfs image.

```
pkgwrap obs-studio
pkgwrap -v --strip chromium ~/Applications/
pkgwrap -f --name "My Browser" chromium
```

### From a local .deb file

```
pkgwrap --localpkg FILE [OPTIONS] [output-directory]
```

Uses the local `.deb` as the primary package. Reads its `Package` and `Depends` fields, resolves and downloads dependencies from apt, then bundles everything together.

```
pkgwrap --localpkg ~/downloads/myapp_1.0_amd64.deb
pkgwrap --localpkg custom-build.deb -v ~/Applications/
```

### From an existing directory

```
pkgwrap --localdir DIR --name NAME --exec PATH --icon PATH [OPTIONS] [output-directory]
```

Bundles an existing directory tree directly (no apt, no dependency resolution). The directory should contain a filesystem layout (e.g., `usr/bin/`, `usr/lib/`, etc.). Requires `--name`, `--exec`, and `--icon`.

```
pkgwrap --localdir /opt/myapp --name "My App" --exec /usr/bin/myapp --icon ~/myapp.png
```

## Options

| Option | Description |
|--------|-------------|
| `--localpkg FILE` | Use a local .deb as the primary package |
| `--localdir DIR` | Bundle an existing directory tree (requires --name, --exec, --icon) |
| `--overlay DIR` | Copy contents of DIR into the bundle's Contents/ directory (merged recursively, overwrites existing files) |
| `-s, --skip-list FILE` | Package skip list (one package name per line; packages assumed on the host) |
| `-e, --exec PATH` | Main executable path within package (e.g., `/usr/bin/app`) |
| `-N, --name NAME` | Override application name for the bundle |
| `-i, --icon PATH` | Override icon (path on host filesystem) |
| `-L, --launch-args ARGS` | Extra arguments baked into the launcher exec line |
| `-f, --force` | Overwrite existing bundle without asking |
| `--strip` | Strip debug symbols from binaries |
| `--keep-root` | Don't delete the staging root after bundling |
| `--enable-redirect` | Force LD_PRELOAD path redirect in launcher |
| `--no-redirect` | Disable LD_PRELOAD path redirect in launcher |
| `-v, --verbose` | Show detailed progress |
| `-h, --help` | Show help |

## Generated bundle structure

```
App Name.app/
  App Name              # Launcher script (executable)
  Contents/
    usr/                # Debian filesystem layout
    lib/
    etc/
    lib/pkgwrap-redirect.so  # LD_PRELOAD redirect library
  Resources/
    Info.plist
    AppIcon.png         # Application icon
```

## Features

- **Automatic dependency resolution** from apt repositories
- **Deb download caching** via `/var/cache/apt/archives/` (shared with system apt)
- **LD_PRELOAD path redirect** for apps with hardcoded absolute paths (disabled by default; auto-detects Qt6 apps)
- **Bundled ld-linux** for FreeBSD linuxulator support (skipped on native Linux)
- **Chromium/Electron auto-detection** with `--no-sandbox` on FreeBSD
- **Application menu stub** registers a standard app-name menu (Services, Hide, Quit) with Menu.app via GNUstep Distributed Objects
- **GIMP 3.0 env var overrides** (GIMP3_DATADIR, GIMP3_SYSCONFDIR, GIMP3_PLUGINDIR)
- **Overlay directory** for injecting custom files into the bundle
- **RPATH rewriting** via patchelf for self-contained library resolution

## Skip list

The skip list tells pkgwrap which packages are already on the host system and don't need to be bundled. Generate one from a Gershwin live ISO:

```
dpkg-query -W -f '${Package}\n' > gershwin-base-packages.txt
```

The default skip list is loaded from `/System/Library/pkgwrap/gershwin-base-packages.txt` if present.

## Components

| File | Description |
|------|-------------|
| `pkgwrap.m` | Main tool — CLI parsing, orchestration |
| `PWPackageManager.m` | Dependency resolution, download, extraction |
| `PWBundleAssembler.m` | Bundle directory assembly, RPATH rewriting |
| `PWLauncherGenerator.m` | Launcher script generation |
| `pkgwrap-redirect.c` | LD_PRELOAD shared library for path redirection |
| `pkgwrap-menu-stub.m` | Menu.app integration helper |
