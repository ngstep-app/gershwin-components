# X11 Authorization in Gershwin LoginWindow

## Overview

LoginWindow uses **libXau** to handle X11 authorization directly, without relying on PAM's `pam_xauth.so` module or external tools like `xauth`. This approach is portable across FreeBSD and Linux.

## How It Works

### X Server Authorization

When LoginWindow starts the X server:

1. **Generate Cookie**: A secure 16-byte MIT-MAGIC-COOKIE-1 is generated using `/dev/urandom`
2. **Write Server Auth**: The cookie is written to `/var/run/loginwindow.auth` using `XauWriteAuth()` from libXau
3. **Start Xorg**: The X server is started with `-auth /var/run/loginwindow.auth`

### User Session Authorization

When a user logs in:

1. **Create User Xauthority**: After `setuid()` to the user, LoginWindow writes the **same cookie** to `~/.Xauthority` using libXau
2. **Set Environment**: `DISPLAY=:0` and `XAUTHORITY=~/.Xauthority` are set
3. **Start Session**: The user's session is started with proper X11 authorization

### Key Points

- The **same cookie** is used for both X server and user session
- No external `xauth` command is invoked
- No reliance on `pam_xauth.so` (which may not exist on FreeBSD)
- Cookie is generated securely from `/dev/urandom`

## Implementation Details

### libXau Functions Used

- `XauWriteAuth()` - Writes authorization entries to `.Xauthority` files

### Cookie Format

- Type: MIT-MAGIC-COOKIE-1
- Size: 16 bytes (128 bits)
- Family: FamilyLocal (for local connections)

## Verification

After logging in, verify authorization works:

```bash
# Check that .Xauthority exists
ls -l ~/.Xauthority

# List authorization entries (requires xauth tool, optional)
xauth list

# Test by launching an X client
xterm
```

## Requirements

- **libXau** library and development headers
  - FreeBSD: Part of X11 (installed by default)
  - Linux: `libxau-dev` (Debian/Ubuntu) or `libXau-devel` (RHEL/Fedora)

## References

- libXau documentation
- X11 authorization protocol specification
- MIT-MAGIC-COOKIE-1 authentication
- X11 authorization: `man xauth`
