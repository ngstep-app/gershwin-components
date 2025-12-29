/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "KeyboardController.h"

static NSString *const kKeyboardDomain = @"KeyboardPreferences";
static NSString *const kDefaultKeyboardFile = @"/etc/default/keyboard";
static NSString *const kSetxkbmapLocal = @"/usr/local/bin/setxkbmap";
static NSString *const kSetxkbmapSystem = @"/usr/bin/setxkbmap";

static NSComparisonResult LayoutComparator(id a, id b, void *context)
{
    NSDictionary *map = (NSDictionary *)context;
    NSString *da = [map objectForKey:a];
    NSString *db = [map objectForKey:b];
    return [da caseInsensitiveCompare:db];
}

@interface KeyboardController ()
- (void)ensureMetadataLoaded;
- (void)parseKeyboardMetadata;
- (NSDictionary *)fallbackLayouts;
- (NSString *)findExecutableFromCandidates:(NSArray *)candidates;
- (NSDictionary *)savedPreferences;
- (NSDictionary *)systemKeyboardDefaults;
- (NSDictionary *)currentXkbmapSettings;
- (void)populateLayoutTable;
- (void)populateVariantsForLayout:(NSString *)layout;
- (void)selectLayout:(NSString *)layout variant:(NSString *)variant;
- (BOOL)applyLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options error:(NSString **)error;
- (void)persistUserDefaultsLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options;
- (void)writeUserAutostartWithLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options;
- (BOOL)updateSystemKeyboardFileWithLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options error:(NSString **)error;
- (NSString *)shellEscapedValue:(NSString *)value;
- (NSString *)trimmed:(NSString *)value;
- (void)updateStatus:(NSString *)message;
- (void)showAlertWithTitle:(NSString *)title text:(NSString *)text;
@end

@implementation KeyboardController

- (id)init
{
    self = [super init];
    if (self) {
        isRefreshing = YES;  // Start in refresh mode to prevent unwanted writes during initialization
        NSLog(@"[Keyboard] Controller init, isRefreshing set to YES");
    }
    return self;
}

- (void)dealloc
{
    [mainView release];
    [layoutTable release];
    [variantTable release];
    [layoutScroll release];
    [variantScroll release];
    [statusLabel release];
    [tryTextField release];
    [swapCheckbox release];
    [layouts release];
    [variantsByLayout release];
    [setxkbmapPath release];
    [sortedLayouts release];
    [currentVariants release];
    [lastAppliedLayout release];
    [lastAppliedVariant release];
    [super dealloc];
}

- (NSView *)createMainView
{
    if (mainView) {
        return mainView;
    }

    [self ensureMetadataLoaded];

    mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 290)];

    // Try layout text field at the top
    NSTextField *tryLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 260, 100, 20)];
    [tryLabel setBezeled:NO];
    [tryLabel setEditable:NO];
    [tryLabel setSelectable:NO];
    [tryLabel setDrawsBackground:NO];
    [tryLabel setStringValue:@"Try layout:"];
    [tryLabel setAutoresizingMask:NSViewMinYMargin];
    [mainView addSubview:tryLabel];
    [tryLabel release];

    tryTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 255, 420, 24)];
    [tryTextField setEditable:YES];
    [tryTextField setSelectable:YES];
    [tryTextField setBezeled:YES];
    [tryTextField setDrawsBackground:YES];
    [tryTextField setPlaceholderString:@"Type here to test the keyboard layout"];
    [tryTextField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [mainView addSubview:tryTextField];

    // Swap checkbox
    swapCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 225, 300, 18)];
    [swapCheckbox setButtonType:NSSwitchButton];
    [swapCheckbox setTitle:@"Swap command key (for Apple keyboards)"];
    [swapCheckbox setTarget:self];
    [swapCheckbox setAction:@selector(swapCheckboxChanged:)];
    [swapCheckbox setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [mainView addSubview:swapCheckbox];

    // Layout label
    NSTextField *layoutLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 195, 80, 20)];
    [layoutLabel setBezeled:NO];
    [layoutLabel setEditable:NO];
    [layoutLabel setSelectable:NO];
    [layoutLabel setDrawsBackground:NO];
    [layoutLabel setStringValue:@"Layout:"];
    [layoutLabel setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [mainView addSubview:layoutLabel];
    [layoutLabel release];

    // Variant label
    NSTextField *variantLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(310, 195, 80, 20)];
    [variantLabel setBezeled:NO];
    [variantLabel setEditable:NO];
    [variantLabel setSelectable:NO];
    [variantLabel setDrawsBackground:NO];
    [variantLabel setStringValue:@"Variant:"];
    [variantLabel setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [mainView addSubview:variantLabel];
    [variantLabel release];

    // Layout table - wider to use more space
    layoutScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 270, 130)];
    [layoutScroll setHasVerticalScroller:YES];
    [layoutScroll setHasHorizontalScroller:NO];
    [layoutScroll setBorderType:NSBezelBorder];
    [layoutScroll setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
    [mainView addSubview:layoutScroll];

    layoutTable = [[NSTableView alloc] initWithFrame:[layoutScroll bounds]];
    [layoutTable setDelegate:self];
    [layoutTable setDataSource:self];
    [layoutTable setAllowsMultipleSelection:NO];
    [layoutTable setAllowsEmptySelection:NO];

    NSTableColumn *layoutColumn = [[NSTableColumn alloc] initWithIdentifier:@"layout"];
    [layoutColumn setTitle:@""];
    [layoutColumn setWidth:250];
    [layoutColumn setEditable:NO];
    [layoutTable addTableColumn:layoutColumn];
    [layoutColumn release];

    [layoutScroll setDocumentView:layoutTable];

    // Variant table - wider to use more space
    variantScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(310, 60, 230, 130)];
    [variantScroll setHasVerticalScroller:YES];
    [variantScroll setHasHorizontalScroller:NO];
    [variantScroll setBorderType:NSBezelBorder];
    [variantScroll setAutoresizingMask:NSViewHeightSizable | NSViewMinXMargin | NSViewWidthSizable];
    [mainView addSubview:variantScroll];

    variantTable = [[NSTableView alloc] initWithFrame:[variantScroll bounds]];
    [variantTable setDelegate:self];
    [variantTable setDataSource:self];
    [variantTable setAllowsMultipleSelection:NO];
    [variantTable setAllowsEmptySelection:YES];

    NSTableColumn *variantColumn = [[NSTableColumn alloc] initWithIdentifier:@"variant"];
    [variantColumn setTitle:@""];
    [variantColumn setWidth:210];
    [variantColumn setEditable:NO];
    [variantTable addTableColumn:variantColumn];
    [variantColumn release];

    [variantScroll setDocumentView:variantTable];

    // Status label at the bottom
    statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 10, 520, 40)];
    [statusLabel setBezeled:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setDrawsBackground:NO];
    [statusLabel setFont:[NSFont systemFontOfSize:10]];
    [statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [mainView addSubview:statusLabel];

    [self populateLayoutTable];
    [self refreshFromSystem];

    return mainView;
}

- (void)ensureMetadataLoaded
{
    if (metadataLoaded) {
        return;
    }

    [self parseKeyboardMetadata];
    setxkbmapPath = [[self findExecutableFromCandidates:[NSArray arrayWithObjects:kSetxkbmapLocal, kSetxkbmapSystem, nil]] retain];
    metadataLoaded = YES;
}

- (void)parseKeyboardMetadata
{
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSArray *possiblePaths = [NSArray arrayWithObjects:
                              @"/usr/share/X11/xkb/rules/base.lst",
                              @"/usr/local/share/X11/xkb/rules/base.lst",
                              nil];
    NSString *lstPath = nil;
    for (NSString *path in possiblePaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            lstPath = path;
            break;
        }
    }
    NSError *error = nil;
    NSString *contents = lstPath ? [NSString stringWithContentsOfFile:lstPath encoding:NSUTF8StringEncoding error:&error] : nil;

    NSMutableDictionary *layoutMap = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *variantMap = [[NSMutableDictionary alloc] init];

    if (contents) {
        BOOL inLayout = NO;
        BOOL inVariant = NO;
        NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

        for (NSString *line in lines) {
            NSString *trim = [line stringByTrimmingCharactersInSet:ws];
            if ([trim length] == 0) {
                continue;
            }

            if ([trim hasPrefix:@"! "]) {
                inLayout = [trim hasPrefix:@"! layout"];
                inVariant = [trim hasPrefix:@"! variant"];
                continue;
            }

            if (inLayout) {
                NSRange space = [trim rangeOfString:@" "];
                if (space.location == NSNotFound) {
                    continue;
                }
                NSString *code = [[trim substringToIndex:space.location] stringByTrimmingCharactersInSet:ws];
                NSString *desc = [[trim substringFromIndex:space.location] stringByTrimmingCharactersInSet:ws];
                if ([code length] > 0) {
                    [layoutMap setObject:(desc.length ? desc : code) forKey:code];
                }
                continue;
            }

            if (inVariant) {
                NSRange colon = [trim rangeOfString:@":"];
                if (colon.location == NSNotFound) {
                    continue;
                }
                NSString *lhs = [[trim substringToIndex:colon.location] stringByTrimmingCharactersInSet:ws];
                NSString *rhs = [[trim substringFromIndex:(colon.location + 1)] stringByTrimmingCharactersInSet:ws];

                NSArray *parts = [lhs componentsSeparatedByCharactersInSet:ws];
                if ([parts count] < 2) {
                    continue;
                }
                NSString *variantCode = [parts objectAtIndex:0];
                NSString *layoutCode = [parts lastObject];

                if ([variantCode length] == 0 || [layoutCode length] == 0) {
                    continue;
                }

                NSMutableArray *list = [variantMap objectForKey:layoutCode];
                if (!list) {
                    list = [NSMutableArray array];
                    [variantMap setObject:list forKey:layoutCode];
                }
                NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:variantCode, @"code", (rhs.length ? rhs : variantCode), @"description", nil];
                [list addObject:entry];
            }
        }
    }

    if ([layoutMap count] == 0) {
        NSDictionary *fallback = [self fallbackLayouts];
        layoutMap = [fallback mutableCopy];
    }

    [layouts release];
    [variantsByLayout release];

    layouts = layoutMap;
    variantsByLayout = variantMap;
}

- (NSDictionary *)fallbackLayouts
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"English (US)", @"us",
            @"English (UK)", @"gb",
            @"German", @"de",
            @"French", @"fr",
            @"Spanish", @"es",
            @"Italian", @"it",
            nil];
}

- (NSString *)findExecutableFromCandidates:(NSArray *)candidates
{
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) {
            return path;
        }
    }

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/which"];
    [task setArguments:[NSArray arrayWithObject:@"setxkbmap"]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    [task release];

    NSString *trim = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trim length] > 0 && [fm isExecutableFileAtPath:trim]) {
        return trim;
    }

    return nil;
}

- (NSDictionary *)savedPreferences
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [defaults persistentDomainForName:kKeyboardDomain];
    if (domain) {
        return domain;
    }
    return [NSDictionary dictionary];
}

- (NSDictionary *)systemKeyboardDefaults
{
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:kDefaultKeyboardFile encoding:NSUTF8StringEncoding error:&error];
    if (!contents) {
        return [NSDictionary dictionary];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) {
            continue;
        }
        NSString *key = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *val = [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        val = [val stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        if ([key length] && [val length]) {
            [result setObject:val forKey:key];
        }
    }
    return result;
}

- (NSDictionary *)currentXkbmapSettings
{
    if (!setxkbmapPath) {
        return [NSDictionary dictionary];
    }

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:setxkbmapPath];
    [task setArguments:[NSArray arrayWithObject:@"-query"]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    [task release];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *key = [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *val = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([key length] && [val length]) {
            [result setObject:val forKey:key];
        }
    }
    return result;
}

- (void)populateLayoutTable
{
    [sortedLayouts release];
    sortedLayouts = [[layouts allKeys] sortedArrayUsingFunction:LayoutComparator context:layouts];
    [sortedLayouts retain];
    [layoutTable reloadData];
}

- (void)populateVariantsForLayout:(NSString *)layout
{
    [currentVariants release];
    currentVariants = [[variantsByLayout objectForKey:layout] retain];
    if (!currentVariants) {
        currentVariants = [[NSArray array] retain];
    }
    [variantTable reloadData];
}

// NSTableView data source methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == layoutTable) {
        return [sortedLayouts count];
    } else if (tableView == variantTable) {
        return [currentVariants count];
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (tableView == layoutTable) {
        NSString *code = [sortedLayouts objectAtIndex:row];
        NSString *desc = [layouts objectForKey:code];
        return [NSString stringWithFormat:@"%@ (%@)", desc, code];
    } else if (tableView == variantTable) {
        NSDictionary *entry = [currentVariants objectAtIndex:row];
        NSString *code = [entry objectForKey:@"code"];
        NSString *desc = [entry objectForKey:@"description"];
        return [NSString stringWithFormat:@"%@ (%@)", desc, code];
    }
    return nil;
}

// NSTableView delegate methods
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSLog(@"[Keyboard] tableViewSelectionDidChange: isRefreshing=%d", isRefreshing);
    if (isRefreshing) {
        NSLog(@"[Keyboard] Ignoring table selection change during refresh");
        return;
    }
    NSTableView *tableView = [notification object];
    if (tableView == layoutTable) {
        NSInteger selectedRow = [layoutTable selectedRow];
        if (selectedRow >= 0 && selectedRow < (NSInteger)[sortedLayouts count]) {
            NSString *layout = [sortedLayouts objectAtIndex:selectedRow];
            NSLog(@"[Keyboard] Layout table selection changed to row %ld: '%@'", (long)selectedRow, layout);
            [self populateVariantsForLayout:layout];
            [variantTable deselectAll:nil];
            [self applySelection:nil];
        }
    } else if (tableView == variantTable) {
        NSInteger selectedRow = [variantTable selectedRow];
        NSLog(@"[Keyboard] Variant table selection changed to row %ld", (long)selectedRow);
        [self applySelection:nil];
    }
}

- (void)selectLayout:(NSString *)layout variant:(NSString *)variant
{
    NSLog(@"[Keyboard] selectLayout: layout='%@' variant='%@' isRefreshing=%d", layout, variant, isRefreshing);
    if (![layout length]) {
        layout = @"us";
    }

    // ensure layout exists, otherwise fall back
    if (![layouts objectForKey:layout]) {
        NSLog(@"[Keyboard] Layout '%@' not found in layouts dictionary", layout);
        NSArray *allKeys = [layouts allKeys];
        if ([allKeys containsObject:@"us"]) {
            NSLog(@"[Keyboard] Falling back to 'us'");
            layout = @"us";
        } else if ([allKeys count] > 0) {
            NSLog(@"[Keyboard] Falling back to first available layout");
            layout = [allKeys objectAtIndex:0];
        }
    }

    // Select layout in table
    NSInteger layoutIndex = [sortedLayouts indexOfObject:layout];
    NSLog(@"[Keyboard] Looking for layout '%@' in sortedLayouts, index=%ld", layout, (long)layoutIndex);
    if (layoutIndex != NSNotFound) {
        [layoutTable selectRowIndexes:[NSIndexSet indexSetWithIndex:layoutIndex] byExtendingSelection:NO];
        [layoutTable scrollRowToVisible:layoutIndex];
    }

    [self populateVariantsForLayout:layout];

    // Select variant in table
    NSInteger variantIndex = NSNotFound;
    if ([variant length]) {
        for (NSUInteger i = 0; i < [currentVariants count]; i++) {
            NSDictionary *entry = [currentVariants objectAtIndex:i];
            if ([[entry objectForKey:@"code"] isEqualToString:variant]) {
                variantIndex = i;
                break;
            }
        }
    }
    NSLog(@"[Keyboard] Looking for variant '%@', index=%ld", variant, (long)variantIndex);
    if (variantIndex != NSNotFound) {
        [variantTable selectRowIndexes:[NSIndexSet indexSetWithIndex:variantIndex] byExtendingSelection:NO];
        [variantTable scrollRowToVisible:variantIndex];
    } else {
        [variantTable deselectAll:nil];
    }
}

- (BOOL)applyLayout:(NSString *)layout variant:(NSString *)variant error:(NSString **)error
{
    return [self applyLayout:layout variant:variant options:@"" error:error];
}

- (BOOL)applyLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options error:(NSString **)error
{
    if (isRefreshing) {
        NSLog(@"[Keyboard] applyLayout blocked during refresh");
        return YES;  // Pretend success during refresh
    }
    NSLog(@"[Keyboard] applyLayout: layout='%@' variant='%@' options='%@'", layout, variant, options);
    if (!setxkbmapPath) {
        if (error) {
            *error = @"setxkbmap not found";
        }
        return NO;
    }

    NSString *trimmedLayout = [self trimmed:layout];
    NSString *trimmedVariant = [self trimmed:variant];
    NSString *trimmedOptions = [self trimmed:options];

    NSTask *clearTask = [[NSTask alloc] init];
    [clearTask setLaunchPath:setxkbmapPath];
    [clearTask setArguments:[NSArray arrayWithObjects:@"-option", @"", nil]];
    [clearTask launch];
    [clearTask waitUntilExit];
    [clearTask release];

    NSMutableArray *args = [NSMutableArray array];
    if ([trimmedLayout length]) {
        [args addObject:@"-layout"];
        [args addObject:trimmedLayout];
    }

    if ([trimmedVariant length]) {
        [args addObject:@"-variant"];
        [args addObject:trimmedVariant];
    }

    if ([trimmedOptions length]) {
        [args addObject:@"-option"];
        [args addObject:trimmedOptions];
    }

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:setxkbmapPath];
    [task setArguments:args];

    NSPipe *stderrPipe = [NSPipe pipe];
    [task setStandardError:stderrPipe];

    [task launch];
    [task waitUntilExit];

    int status = [task terminationStatus];
    [task release];

    if (status != 0) {
        NSData *data = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NSString *stderrString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        if (error) {
            *error = (stderrString.length ? stderrString : @"Failed to run setxkbmap");
        }
        return NO;
    }

    [lastAppliedLayout release];
    [lastAppliedVariant release];

    lastAppliedLayout = [trimmedLayout copy];
    lastAppliedVariant = [trimmedVariant copy];

    return YES;
}

- (void)persistUserDefaultsLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options
{
    if (isRefreshing) {
        NSLog(@"[Keyboard] persistUserDefaultsLayout blocked during refresh");
        return;
    }
    NSLog(@"[Keyboard] persistUserDefaultsLayout: layout='%@' variant='%@' options='%@'", layout, variant, options);
    NSMutableDictionary *domain = [NSMutableDictionary dictionary];
    if (layout) {
        [domain setObject:layout forKey:@"layout"];
    }
    if (variant) {
        [domain setObject:variant forKey:@"variant"];
    }
    if (options) {
        [domain setObject:options forKey:@"options"];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setPersistentDomain:domain forName:kKeyboardDomain];
    [defaults synchronize];
}

- (void)writeUserAutostartWithLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options
{
    if (isRefreshing) {
        NSLog(@"[Keyboard] writeUserAutostartWithLayout blocked during refresh");
        return;
    }
    NSLog(@"[Keyboard] writeUserAutostartWithLayout: layout='%@' variant='%@' options='%@'", layout, variant, options);
    NSString *home = NSHomeDirectory();
    NSString *binDir = [home stringByAppendingPathComponent:@".local/bin"];
    NSString *scriptPath = [binDir stringByAppendingPathComponent:@"gershwin-apply-keyboard.sh"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:binDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *escapedLayout = [self shellEscapedValue:(layout ? layout : @"")];
    NSString *escapedVariant = [self shellEscapedValue:(variant ? variant : @"")];
    NSString *escapedOptions = [self shellEscapedValue:(options ? options : @"")];

    NSMutableString *script = [NSMutableString string];
    [script appendString:@"#!/bin/sh\nset -e\n\nsetxkbmap_bin=\"/usr/local/bin/setxkbmap\"\n[ -x \"$setxkbmap_bin\" ] || setxkbmap_bin=\"/usr/bin/setxkbmap\"\n[ -x \"$setxkbmap_bin\" ] || exit 0\n\n$setxkbmap_bin -option '' >/dev/null 2>&1 || true\ncmd=\"$setxkbmap_bin -layout '"];
    [script appendString:escapedLayout];
    [script appendString:@"'\"\nif [ -n \""];
    [script appendString:escapedVariant];
    [script appendString:@"\" ]; then\n  cmd=\"$cmd -variant '"];
    [script appendString:escapedVariant];
    [script appendString:@"'\"\nfi\nif [ -n \""];
    [script appendString:escapedOptions];
    [script appendString:@"\" ]; then\n  cmd=\"$cmd -option '"];
    [script appendString:escapedOptions];
    [script appendString:@"'\"\nelse\n  cmd=\"$cmd -option ''\"\nfi\nsh -c \"$cmd\" >/dev/null 2>&1\n"];

    [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0755] forKey:NSFilePosixPermissions];
    [fm setAttributes:attrs ofItemAtPath:scriptPath error:nil];
}

- (BOOL)updateSystemKeyboardFileWithLayout:(NSString *)layout variant:(NSString *)variant options:(NSString *)options error:(NSString **)error
{
    if (isRefreshing) {
        NSLog(@"[Keyboard] updateSystemKeyboardFileWithLayout blocked during refresh");
        if (error) {
            *error = @"Skipped during refresh";
        }
        return NO;
    }
    NSLog(@"[Keyboard] updateSystemKeyboardFileWithLayout: layout='%@' variant='%@' options='%@'", layout, variant, options);
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];

    NSDictionary *systemDefaults = [self systemKeyboardDefaults];
    NSString *model = [systemDefaults objectForKey:@"XKBMODEL"];
    if (![model length]) {
        model = @"pc105";
    }

    NSMutableString *payload = [NSMutableString string];
    [payload appendFormat:@"XKBMODEL=\"%@\"\n", model];
    [payload appendFormat:@"XKBLAYOUT=\"%@\"\n", (layout ? layout : @"")];
    [payload appendFormat:@"XKBVARIANT=\"%@\"\n", (variant ? variant : @"")];
    [payload appendFormat:@"XKBOPTIONS=\"%@\"\n", (options ? options : @"")];

    if (![payload writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        if (error) {
            *error = @"Unable to write temporary keyboard file";
        }
        return NO;
    }

    NSString *sudoPath = @"/usr/bin/sudo";
    if (![fm isExecutableFileAtPath:sudoPath]) {
        [fm removeItemAtPath:tmpPath error:nil];
        if (error) {
            *error = @"sudo not available";
        }
        return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:sudoPath];
    [task setArguments:[NSArray arrayWithObjects:@"-E", @"-A", @"install", @"-m", @"644", tmpPath, kDefaultKeyboardFile, nil]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardError:pipe];

    [task launch];
    [task waitUntilExit];

    int status = [task terminationStatus];
    NSData *stderrData = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *stderrString = [[[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] autorelease];

    [task release];
    [fm removeItemAtPath:tmpPath error:nil];

    if (status != 0) {
        if (error) {
            *error = (stderrString.length ? stderrString : @"Failed to update /etc/default/keyboard");
        }
        return NO;
    }

    return YES;
}

- (NSString *)shellEscapedValue:(NSString *)value
{
    NSString *v = (value ? value : @"");
    return [v stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
}

- (NSString *)trimmed:(NSString *)value
{
    if (!value) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)updateStatus:(NSString *)message
{
    [statusLabel setStringValue:(message ? message : @"")];
}

- (void)showAlertWithTitle:(NSString *)title text:(NSString *)text
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:(title ? title : @"Keyboard Preference")];
    [alert setInformativeText:(text ? text : @"")];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)swapCheckboxChanged:(id)sender
{
    (void)sender;
    // Don't apply changes during initial refresh
    if (isRefreshing) {
        return;
    }
    [self applySelection:nil];
}

- (IBAction)applySelection:(id)sender
{
    NSLog(@"[Keyboard] applySelection called, isRefreshing=%d", isRefreshing);
    (void)sender;
    // Don't apply changes during initial refresh
    if (isRefreshing) {
        NSLog(@"[Keyboard] Blocking applySelection during refresh");
        return;
    }
    [self ensureMetadataLoaded];

    NSInteger layoutRow = [layoutTable selectedRow];
    NSString *layout = (layoutRow >= 0 && layoutRow < (NSInteger)[sortedLayouts count]) ? [sortedLayouts objectAtIndex:layoutRow] : nil;

    NSInteger variantRow = [variantTable selectedRow];
    NSString *variant = nil;
    if (variantRow >= 0 && variantRow < (NSInteger)[currentVariants count]) {
        NSDictionary *entry = [currentVariants objectAtIndex:variantRow];
        variant = [entry objectForKey:@"code"];
    }

    NSString *options = @"";
    if ([swapCheckbox state] == NSOnState) {
        options = @"altwin:swap_alt_win";
    }

    NSLog(@"[Keyboard] Applying layout='%@' variant='%@' options='%@'", layout, variant, options);

    NSString *error = nil;
    if (![self applyLayout:layout variant:variant options:options error:&error]) {
        [self showAlertWithTitle:@"Could not set layout" text:error];
        [self updateStatus:[NSString stringWithFormat:@"Failed to apply layout (%@)", error ? error : @"unknown error"]];
        return;
    }

    [self persistUserDefaultsLayout:layout variant:variant options:options];
    [self writeUserAutostartWithLayout:layout variant:variant options:options];

    NSString *systemError = nil;
    BOOL systemUpdated = [self updateSystemKeyboardFileWithLayout:layout variant:variant options:options error:&systemError];

    NSMutableString *status = [NSMutableString stringWithFormat:@"Active layout: %@", layout];
    if ([variant length]) {
        [status appendFormat:@" / %@", variant];
    }

    if (systemUpdated) {
        [status appendString:@" — saved to /etc/default/keyboard."];
    } else {
        [status appendString:@" — saved for this user. System file not updated."];
        if ([systemError length]) {
            [status appendFormat:@" (%@)", systemError];
        }
    }

    [self updateStatus:status];
}

- (void)refreshFromSystem
{
    NSLog(@"[Keyboard] refreshFromSystem: START");
    [self ensureMetadataLoaded];
    isRefreshing = YES;
    NSLog(@"[Keyboard] isRefreshing set to YES");

    // First, try system keyboard config file
    NSDictionary *system = [self systemKeyboardDefaults];
    NSString *layout = [system objectForKey:@"XKBLAYOUT"];
    NSString *variant = [system objectForKey:@"XKBVARIANT"];
    NSString *options = [system objectForKey:@"XKBOPTIONS"];
    NSLog(@"[Keyboard] System config file: layout='%@' variant='%@' options='%@'", layout, variant, options);

    // If system config is empty, try current XKB settings
    if (![layout length]) {
        NSLog(@"[Keyboard] System config empty, trying current XKB settings");
        NSDictionary *current = [self currentXkbmapSettings];
        layout = [current objectForKey:@"layout"];
        variant = [current objectForKey:@"variant"];
        options = [current objectForKey:@"options"];
        NSLog(@"[Keyboard] Current XKB: layout='%@' variant='%@' options='%@'", layout, variant, options);
        // Handle multiple layouts/variants by taking the first one
        if ([layout rangeOfString:@","].location != NSNotFound) {
            layout = [[layout componentsSeparatedByString:@","] objectAtIndex:0];
            NSLog(@"[Keyboard] Multiple layouts detected, using first: '%@'", layout);
        }
        if ([variant rangeOfString:@","].location != NSNotFound) {
            variant = [[variant componentsSeparatedByString:@","] objectAtIndex:0];
            NSLog(@"[Keyboard] Multiple variants detected, using first: '%@'", variant);
        }
    }

    // If still empty, try saved preferences
    if (![layout length]) {
        NSLog(@"[Keyboard] Still empty, trying saved preferences");
        NSDictionary *saved = [self savedPreferences];
        layout = [saved objectForKey:@"layout"];
        variant = [saved objectForKey:@"variant"];
        options = [saved objectForKey:@"options"];
        NSLog(@"[Keyboard] Saved prefs: layout='%@' variant='%@' options='%@'", layout, variant, options);
    }

    NSLog(@"[Keyboard] Final values to select: layout='%@' variant='%@' options='%@'", layout, variant, options);
    [self selectLayout:layout variant:variant];
    [swapCheckbox setState:([options isEqualToString:@"altwin:swap_alt_win"] ? NSOnState : NSOffState)];

    NSMutableString *status = [NSMutableString stringWithFormat:@"Current layout: %@", layout ? layout : @"(unknown)"];
    if ([variant length]) {
        [status appendFormat:@" / %@", variant];
    }
    if ([options length]) {
        [status appendFormat:@" (%@)", options];
    }
    [status appendString:@". Changes apply instantly."];
    [self updateStatus:status];
    
    isRefreshing = NO;
    NSLog(@"[Keyboard] isRefreshing set to NO");
    NSLog(@"[Keyboard] refreshFromSystem: END");
}

@end
