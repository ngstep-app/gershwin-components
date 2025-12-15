# libDSStore

A GNUstep library and command-line tool for reading and writing macOS .DS_Store files.

## Overview

libDSStore provides a pure GNUstep/Objective-C implementation for manipulating .DS_Store files. These files are used by macOS Finder to store metadata about files and folders, including icon positions, view settings, background images, and more.

## Observations

* Mac Finder writes `.DSStore` not just when closing a window
* x coordinate is from top left in pixels to the right
* y coordinate is from top left in pixels downwards
* The coordinates are to the center of the icon

## TODO

Make sure we can also read the following properties:

* Label (None, Red, Orange, Yellow, Green, Blue, Purple, Grey)
* Icon size (it is per folder)
* Grid spacing (it is per folder)
* Text size (it is per folder)
* Label position (bottom, right) (it is per folder)
* Show item info (it is per folder)
* Show icon preview (it is per folder)
* Arrange by (None, Snap to Grid, Name, Date Modified, Date Created, Size, Kind, Label) (it is per folder)
* Which colums are shown in column view (Date Modified, Date Created, Last Opened, Size, Kind, Version, Comments, Label (it is per folder)
* Use relative dates (it is per folder)
* Calculate all sizes (it is per folder)
* Show/hide Status Bar
* Show/hide Path Bar
* Show/hide Sidebar
* Show/hide Toolbar (toggles Spatial Mode)

## Features

- Read and write .DS_Store files
- Support for all standard entry types (bool, long, blob, ustr, type, comp, dutc)
- Decode common blob types (icon positions, plist data)
- Command-line tool for inspection and modification
- Full GNUstep compatibility

## Supported Entry Types

- **bool**: Boolean values
- **long/shor**: 32-bit integers
- **blob**: Binary data (automatically decoded for known types)
- **ustr**: Unicode strings (UTF-16BE)
- **type**: 4-character type codes
- **comp/dutc**: 64-bit integers/timestamps

## Common Entry Codes

- **Iloc**: Icon location (x, y coordinates)
- **bwsp**: Browser window state plist
- **lsvp**: List view properties plist
- **lsvP**: List view properties plist (alternate)
- **icvp**: Icon view properties plist
- **pBBk**: Background picture bookmark

## Library Usage

### Basic Usage

```objc
#import <DSStore/DSStore.h>

// Load existing .DS_Store file
DSStore *store = [DSStore storeWithPath:@"/path/to/.DS_Store"];
if ([store load]) {
    // Access entries
    NSArray<DSStoreEntry *> *entries = store.entries;
    
    // Get specific entry
    DSStoreEntry *entry = [store entryForFilename:@"file.txt" code:@"Iloc"];
    
    // Get icon position
    NSPoint iconPos = [store iconLocationForFilename:@"file.txt"];
    
    // Set icon position
    [store setIconLocation:NSMakePoint(100, 200) forFilename:@"file.txt"];
    
    // Save changes
    [store save];
}

// Create new .DS_Store file
DSStore *newStore = [DSStore createStoreAtPath:@"/path/to/new/.DS_Store" withEntries:nil];
[newStore setIconLocation:NSMakePoint(50, 100) forFilename:@"document.pdf"];
[newStore save];
```

### Working with Entries

```objc
// Create a new entry
DSStoreEntry *entry = [[DSStoreEntry alloc] initWithFilename:@"file.txt"
                                                        code:@"note" 
                                                        type:DSStoreEntryTypeUnicodeString
                                                       value:@"My note"];
[store setEntry:entry];

// Remove an entry
[store removeEntryForFilename:@"file.txt" code:@"note"];
```

### Working with Plists

```objc
// Get background picture settings
NSDictionary *bgPicture = [store backgroundPictureForDirectory];

// Set list view settings
NSDictionary *listViewSettings = @{
    @"calculateAllSizes": @(YES),
    @"columns": @{
        @"name": @{@"ascending": @(YES), @"index": @(0), @"visible": @(YES), @"width": @(300)},
        @"size": @{@"ascending": @(NO), @"index": @(1), @"visible": @(YES), @"width": @(100)}
    }
};
[store setListViewSettings:listViewSettings];
```

## Command-Line Tool

The `dsstore` command-line tool provides easy access to .DS_Store file functionality.

## Building

Requirements:
- GNUstep development environment
- clang19 compiler

```bash
# Build library and tool
gmake

# Install
sudo gmake install

# Clean
gmake clean
```

## File Format

The .DS_Store file format consists of:

1. **Buddy Allocator Header**: Manages block allocation within the file
2. **DSDB Superblock**: Contains metadata about the B-tree structure
3. **B-tree Nodes**: Store the actual entries in sorted order

Each entry contains:
- Filename (UTF-16BE string)
- 4-character code
- 4-character type
- Value data (format depends on type)

## Compatibility

This implementation is compatible with .DS_Store files created by:
- Other .DS_Store manipulation tools
- The Python `ds_store` library
- macOS Finder (not tested yet)

## Error Handling

The library provides comprehensive error handling:
- Invalid file format detection
- Corrupted data recovery attempts
- Missing file handling
- Write permission checks

## Thread Safety

The library is not thread-safe. Use appropriate synchronization when accessing DSStore objects from multiple threads.

## Limitations

- Complex B-tree structures are simplified during write operations
- Some advanced Finder features may not be fully supported
- Large directories may have performance implications

## Examples

See the `dsstore` command-line tool source code for comprehensive usage examples.

## Contributing

Contributions are welcome! Please ensure all code follows the project's coding standards and includes appropriate tests.
