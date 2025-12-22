# LoginWindow

A simple, minimalist login manager for GNUstep-based desktop environments.

## Installation

1. Build the application with `gmake`
2. Install with `gmake install`
3. Add the following line to `/etc/rc.conf` to enable LoginWindow:
   ```
   loginwindow_enable="YES"
   ```
4. Disable other display managers (gdm, lightdm, etc.) in `/etc/rc.conf`


## Enabling

Create the local preferences directory if it doesn't exist

```
sudo -A -E mkdir -p /Local/Library/Preferences
```

Create or update `/Local/Library/Preferences/LoginWindow.plist` with the auto-login user (replace `User`)

```
{
    autoLoginUser = User;
    lastLoggedInUser = User;
    lastSession = "/System/Library/Scripts/Gershwin.sh";
}'
```

To disable autologin, remove the key or the file.

## Logs

Logs are written to `/var/log/LoginWindow.log` if invoked from the rc script.
