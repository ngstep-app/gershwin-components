# Keyboard Preference Pane

This preference pane lets you select an XKB layout and optional variant using two side-by-side list views, plus a keyboard type selector for ANSI or ISO physical layouts. Changes apply instantly with `setxkbmap`, saves your choice to user defaults, and writes a small autostart helper so the layout is restored when you log in again. If `sudo -E -A` is available it also attempts to update `/etc/default/keyboard` for system-wide persistence.

## Features

- Select from all available XKB layouts and variants
- Switch between ANSI and ISO physical keyboard types
- Optionally swap command key (for Apple keyboards)
- Instant preview with a test text field
- Settings persist across user sessions

## Notes

- Layout and variant data are parsed from `/usr/share/X11/xkb/rules/base.lst` or `/usr/local/share/X11/xkb/rules/base.lst` (e.g., for FreeBSD); a small fallback list is used if neither file is found.
- Keyboard type is stored in user defaults and affects the XKBMODEL setting (pc104 for ANSI, pc105 for ISO, pc106 for JIS).
- If the "Apple keyboard" checkbox is checked the preference pane will use Apple keyboard models (`applealu_ansi`, `applealu_iso`, `applealu_jis`) instead of PC models.
- User-level persistence lives in `~/.local/bin/gershwin-apply-keyboard.sh`.
- System-wide persistence uses `/etc/default/keyboard` and requires `sudo -E -A`.
## Apple ISO Keyboard Fix

Apple ISO keyboards have a hardware difference compared to standard PC ISO keyboards: two keys are physically swapped.

**The Problem:**

On PC ISO keyboards:
- Top-left key (keycode 49, TLDE): `^` circumflex
- Left-of-Z key (keycode 94, LSGT): `<` less-than
  
On Apple ISO keyboards:
- Top-left key (same keycode 49): physically has `<` printed on it
- Left-of-Z key (same keycode 94): physically has `^` printed on it

The XKB `applealu_iso` model correctly identifies Apple keyboards but does **not** remap these keycodes, causing the symbols to appear wrong regardless of the layout or checkbox state.

**The Solution:**

When both conditions are true:
1. "Apple keyboard" checkbox is checked
2. Keyboard type is set to "ISO"

The preference pane generates an autostart script that:
1. Configures the keyboard layout with `setxkbmap`
2. Uses `xmodmap` to swap the symbol mappings for keycodes 49 and 94

This ensures the symbols match the physical key labels on Apple ISO keyboards.

**Technical Details:**
- Keycode 49 (TLDE) is remapped to produce: `< >` (less/greater)
- Keycode 94 (LSGT) is remapped to produce: `^ °` (circumflex/degree)
- The fix is automatically applied in the generated `~/.local/bin/gershwin-apply-keyboard.sh` script
- The xmodmap commands are safe and only execute if xmodmap is available
## Apple ISO Keyboard Fix

Apple ISO keyboards have a hardware difference compared to standard PC ISO keyboards: two keys are physically swapped.

**The Problem:**
- On PC ISO keyboards:
  - Top-left key (keycode 49, TLDE): `^` circumflex
  - Left-of-Z key (keycode 94, LSGT): `<` less-than
  
- On Apple ISO keyboards:
  - Top-left key (same keycode 49): physically has `<` printed on it
  - Left-of-Z key (same keycode 94): physically has `^` printed on it

The XKB `applealu_iso` model correctly identifies Apple keyboards but does **not** remap these keycodes, causing the symbols to appear wrong regardless of the layout or checkbox state.

**The Solution:**

When both conditions are true:
1. "Apple keyboard" checkbox is checked
2. Keyboard type is set to "ISO"

The preference pane generates an autostart script that:
1. Configures the keyboard layout with `setxkbmap`
2. Uses `xmodmap` to swap the symbol mappings for keycodes 49 and 94

This ensures the symbols match the physical key labels on Apple ISO keyboards.

**Technical Details:**
- Keycode 49 (TLDE) is remapped to produce: `< >` (less/greater)
- Keycode 94 (LSGT) is remapped to produce: `^ °` (circumflex/degree)
- The fix is automatically applied in the generated `~/.local/bin/gershwin-apply-keyboard.sh` script
- The xmodmap commands are safe and only execute if xmodmap is available
