# appstub

A CLI tool that wraps executables in GNUstep application bundles.

## Purpose

`appstub` reads the `GSWrappedExecutable` key from its Info.plist and executes the specified command from `$PATH`, passing through all command-line arguments.

All errors are displayed via NSAlert dialogs with clear descriptions to help diagnose configuration issues.

## Building

```sh
gmake
```

## Usage

1. Place `appstub` in an application bundle (e.g., `YourApp.app/YourApp`)
2. Create an Info.plist in the Resources directory with the `GSWrappedExecutable` key:

```
{
    GSWrappedExecutable = "command-to-execute";
}
```

3. Run the application bundle:

```sh
YourApp.app/YourApp [arguments...]
```

The tool will find `command-to-execute` in `$PATH` and execute it with all provided arguments.

## Error Handling

The tool displays GUI error dialogs for all failure conditions:
- Missing or invalid Info.plist
- Missing GSWrappedExecutable key
- Command not found in PATH
- Memory allocation failures
- Invalid bundle structure
- Unexpected exceptions

## Example

For a Chromium wrapper:

```
/Local/Applications/Chromium.app/Resources/Info.plist:
{
    CFBundleName = "Chromium";
    NSExecutable = "Chromium";
    GSWrappedExecutable = "chromium";
}
```

When `Chromium.app/Chromium` is executed, it will find and run `chromium` from `$PATH`.
