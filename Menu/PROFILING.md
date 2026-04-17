# Menu Application Profiling

The Menu application includes lightweight CPU profiling instrumentation to help identify performance bottlenecks.

## Building with Profiling

Build Menu with profiling enabled:

```bash
gmake PROFILE=1
```

When compiled with profiling enabled, the application will:
1. Print a startup message to stderr: `[Profile] Instrumentation active — dump with: kill -USR1 <pid>`
2. Collect detailed metrics for all instrumented code sections
3. Print dumps to stderr every 10 seconds (or when SIGUSR1 is sent)

## Instrumentation Requirements

**Important:** The profiler requires code to be explicitly instrumented with `MENU_PROFILE_BEGIN` and `MENU_PROFILE_END` macros. Without instrumentation, there will be no profiling data.

When compiled **without** profiling (`gmake` without `PROFILE=1`), the macros compile to nothing and have zero overhead.

## Usage

### Step 1: Verify Profiling is Active

Start Menu with profiling enabled and watch stderr for the startup message:

```bash
./Menu.app/Menu 2>&1 | grep Profile
# Expected output:
# [Profile] Instrumentation active — dump with: kill -USR1 12345
```

If you don't see this message, verify you built with `PROFILE=1` by checking:
```bash
grep MENU_PROFILING obj/Menu.obj/MenuProfiler.o >/dev/null && echo "Profiling enabled" || echo "Profiling disabled"
```

### Step 2: Add Instrumentation

Wrap performance-sensitive code sections with profiling macros:

```objc
#import "MenuProfiler.h"

- (void)updateMenuBar
{
    MENU_PROFILE_BEGIN(updateMenuBar);
    
    // ... your code ...
    
    MENU_PROFILE_END(updateMenuBar);
}
```

### Step 3: View Profile Dumps

Once instrumented code is running, dumps are printed automatically every 10 seconds to stderr. Or get an immediate dump:

```bash
kill -USR1 $(pgrep Menu)
```

Example output:
```
═══ Menu Profile (10.0s) ═════════════════════════════════════════════════
Probe                       Calls      Total ms      Avg µs      Min µs      Max µs
updateMenuBar                 1245          523.4      419.0        12.5       1567.3
handleMenuClick                 892          156.2      175.0         3.2        892.1
════════════════════════════════════════════════════════════════════════
```

The columns show:
- **Probe**: Function or section name
- **Calls**: Number of times the probe was executed
- **Total ms**: Total time spent in this probe
- **Avg µs**: Average time per call
- **Min µs**: Minimum execution time
- **Max µs**: Maximum execution time

### Viewing stderr Output

If running Menu.app from Terminal, stderr goes to the terminal window. If using `pgrep` to send signals, tail the debug log:

```bash
# Start Menu with output to log
./Menu.app/Menu 2>menu-profile.log &
sleep 2
# Get the PID
PID=$(pgrep Menu)
# Trigger a profile dump
kill -USR1 $PID
# View the results
tail menu-profile.log
```
## Instrumenting Code

To add profiling to your code, include the header:

```objc
#import "MenuProfiler.h"
```

Then instrument your functions:

```objc
- (void)updateMenuBar
{
    MENU_PROFILE_BEGIN(updateMenuBar);
    // ... work ...
    MENU_PROFILE_END(updateMenuBar);
}
```

**Key points:**
- Probes are named using standard C identifiers (letters, digits, underscores)
- The probe name is used both as the label and in the profile output
- Probes are registered automatically on first use (idempotent)
- When profiling is disabled, both macros compile to nothing—zero overhead

## Performance Considerations

- **When disabled** (default build): All profiling macros compile to nothing—zero overhead.
- **When enabled** (PROFILE=1 build): Small overhead from `clock_gettime()` calls per probe measurement (~1-2 µs per measurement).
- **Probe limit**: Maximum 64 distinct probes; additional probes are silently ignored.
- **Memory**: ~800 bytes for probe storage, minimal stack overhead per probe.

## Configuration

Edit `MenuProfiler.m` to adjust:
- `MENU_PROFILE_INTERVAL`: Auto-dump interval (default: 10 seconds)
- `MENU_MAX_PROBES`: Maximum number of distinct probes (default: 64)

Rebuild after making changes.
