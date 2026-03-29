/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "DisplayController.h"
#import "DisplayView.h"
#import <dispatch/dispatch.h>

@implementation DisplayInfo

@synthesize name, frame, resolution, isPrimary, isConnected, output, currentResolutionString;

- (id)init
{
    self = [super init];
    if (self) {
        name = nil;
        frame = NSZeroRect;
        resolution = NSZeroSize;
        isPrimary = NO;
        isConnected = NO;
        output = nil;
        currentResolutionString = nil;
    }
    return self;
}

- (void)dealloc
{
    [name release];
    [output release];
    [currentResolutionString release];
    [super dealloc];
}

@end

static NSInteger dialogIDCounter = 0;
static NSMutableDictionary *activeDialogsByID = nil;

@implementation DisplayController

- (id)init
{
    self = [super init];
    if (self) {
        displays = [[NSMutableArray alloc] init];
        selectedDisplay = nil;
        isRefreshing = NO;
        xrandrPath = [[self findXrandrPath] retain];
        
        NSDebugLog(@"DisplayController: Initializing with xrandr path: %@", xrandrPath);
        
        if (!xrandrPath) {
            NSDebugLog(@"DisplayController: ERROR - xrandr not found in PATH");
        }
    }
    return self;
}

- (void)dealloc
{
    [displays release];
    [displayView release];
    [mainView release];
    [resolutionPopup release];
    [mirrorDisplaysCheckbox release];
    [xrandrPath release];
    [lastXrandrOutput release];
    [saveButton release];
    [savedStateSnapshot release];
    [super dealloc];
}

- (NSView *)createMainView
{
    if (mainView) {
        return mainView;
    }
    
    // Check if xrandr is available before creating the view
    if (![self isXrandrAvailable]) {
        NSDebugLog(@"DisplayController: Cannot create main view - xrandr not available");
        
        // Create a simple error view
        mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 320)];
        
        NSTextField *errorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 140, 460, 40)];
        [errorLabel setStringValue:@"Display configuration is not available.\nThe xrandr tool is required but was not found."];
        [errorLabel setBezeled:NO];
        [errorLabel setDrawsBackground:NO];
        [errorLabel setEditable:NO];
        [errorLabel setSelectable:NO];
        [errorLabel setFont:[NSFont systemFontOfSize:14]];
        [errorLabel setAlignment:NSCenterTextAlignment];
        [mainView addSubview:errorLabel];
        [errorLabel release];
        
        return mainView;
    }
    
    NSDebugLog(@"DisplayController: Creating main view with xrandr available");
    
    // Get available width from SystemPreferences window if possible
    float availableWidth = 500; // Default fallback
    float availableHeight = 320; // Default fallback
    
    // Try to get the actual SystemPreferences window size
    NSArray *windows = [NSApp windows];
    for (NSWindow *window in windows) {
        if ([[window title] containsString:@"System Preferences"] || 
            [[window className] containsString:@"PreferencePane"]) {
            NSRect windowFrame = [window frame];
            NSRect contentRect = [window contentRectForFrameRect:windowFrame];
            // Use most of the content area, leaving margins
            availableWidth = contentRect.size.width - 40; // 20px margin on each side
            availableHeight = contentRect.size.height - 80; // Space for title and controls
            NSDebugLog(@"DisplayController: Found SystemPreferences window, using size: %.0fx%.0f", availableWidth, availableHeight);
            break;
        }
    }
    
    // Ensure reasonable minimums
    if (availableWidth < 400) availableWidth = 500;
    if (availableHeight < 250) availableHeight = 320;
    
    mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, availableWidth, availableHeight)];
    
    NSTextField *instructLabel1 = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 115, availableWidth - 22, 20)];
    [instructLabel1 setStringValue:@"Drag displays to arrange them. Drag menu bar to set the main display."];
    [instructLabel1 setBezeled:NO];
    [instructLabel1 setDrawsBackground:NO];
    [instructLabel1 setEditable:NO];
    [instructLabel1 setSelectable:NO];
    [instructLabel1 setFont:[NSFont systemFontOfSize:11]];
    [mainView addSubview:instructLabel1];
    [instructLabel1 release];
    
    // Create a display arrangement view that uses most of the available space
    float displayAreaHeight = availableHeight - 160; // Leave space for controls below
    displayView = [[DisplayView alloc] initWithFrame:NSMakeRect(20, 140, availableWidth - 22, displayAreaHeight)];
    [displayView setController:self];
    [mainView addSubview:displayView];

    
    // Mirror displays checkbox
    mirrorDisplaysCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 65, 200, 20)];
    [mirrorDisplaysCheckbox setButtonType:NSSwitchButton];
    [mirrorDisplaysCheckbox setTitle:@"Mirror Displays"];
    [mirrorDisplaysCheckbox setTarget:self];
    [mirrorDisplaysCheckbox setAction:@selector(mirrorDisplaysChanged:)];
    [mainView addSubview:mirrorDisplaysCheckbox];
    
    // Resolution popup
    NSTextField *resLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 35, 80, 20)];
    [resLabel setStringValue:@"Resolution:"];
    [resLabel setBezeled:NO];
    [resLabel setDrawsBackground:NO];
    [resLabel setEditable:NO];
    [resLabel setSelectable:NO];
    [mainView addSubview:resLabel];
    [resLabel release];
    
    resolutionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 32, 180, 25)];
    [resolutionPopup setTarget:self];
    [resolutionPopup setAction:@selector(resolutionChanged:)];
    [mainView addSubview:resolutionPopup];

    // Save Settings button
    saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(availableWidth - 120, 32, 100, 25)];
    [saveButton setTitle:@"Save Settings"];
    [saveButton setButtonType:NSMomentaryPushInButton];
    [saveButton setBezelStyle:NSRoundedBezelStyle];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(saveSettings:)];
    [saveButton setEnabled:NO];
    [mainView addSubview:saveButton];

    // Do not call refreshDisplays: here — the DisplayPane's didSelect
    // will trigger it once the view is in the window hierarchy.
    // Calling it here races with didSelect and causes double async loads.

    return mainView;
}

- (void)refreshDisplays:(NSTimer *)timer
{
    if (![self isXrandrAvailable]) {
        NSDebugLog(@"DisplayController: Cannot refresh displays - xrandr not available");
        return;
    }

    // Prevent concurrent refreshes — if one is already in flight, skip.
    // The in-flight refresh will deliver up-to-date results when it finishes.
    if (isRefreshing) {
        NSDebugLog(@"DisplayController: Refresh already in progress, skipping");
        return;
    }
    isRefreshing = YES;

    NSDebugLog(@"DisplayController: Refreshing displays using xrandr at: %@", xrandrPath);

    // Store the currently selected display to preserve selection
    NSString *previouslySelectedOutput = nil;
    if (selectedDisplay) {
        previouslySelectedOutput = [[selectedDisplay output] retain];
        NSDebugLog(@"DisplayController: Preserving selection for display: %@", previouslySelectedOutput);
    }

    // Run xrandr off the main thread so the UI stays responsive
    NSString *path = [xrandrPath retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:path];
        [task setArguments:@[@"--query"]];

        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];

        NSFileHandle *file = [pipe fileHandleForReading];

        [task launch];
        // Read pipe data BEFORE waitUntilExit to avoid pipe-buffer deadlock.
        NSData *data = [file readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [task release];
        [path release];

        // Switch back to the main thread for all UI and model updates
        dispatch_async(dispatch_get_main_queue(), ^{
            isRefreshing = NO;

            [self parseXrandrOutput:output];
            [output release];

            // Restore the previously selected display if it still exists
            if (previouslySelectedOutput) {
                selectedDisplay = nil;
                for (DisplayInfo *display in displays) {
                    if ([[display output] isEqualToString:previouslySelectedOutput]) {
                        selectedDisplay = display;
                        NSDebugLog(@"DisplayController: Restored selection for display: %@", [display name]);
                        break;
                    }
                }
                [previouslySelectedOutput release];
            }

            // Update the display view with new data
            if (displayView) {
                [displayView updateDisplayRects];
                [displayView setNeedsDisplay:YES];
            }

            // Update resolution popup
            [self updateResolutionPopup];

            [self updateSaveButtonState];
        });
    });
}

- (void)parseXrandrOutput:(NSString *)output
{
    [displays removeAllObjects];

    // Cache the raw output so getAvailableResolutionsForDisplay: can
    // parse it without spawning another xrandr process.
    [lastXrandrOutput release];
    lastXrandrOutput = [output copy];

    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    DisplayInfo *currentDisplay = nil;
    BOOL parsingModes = NO;
    
    NSDebugLog(@"DisplayController: Parsing xrandr output...");
    
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        // Check for output line (display name)
        if ([trimmedLine rangeOfString:@" connected"].location != NSNotFound ||
            [trimmedLine rangeOfString:@" disconnected"].location != NSNotFound) {
            
            // Finish previous display if any
            if (currentDisplay) {
                if ([currentDisplay isConnected]) {
                    [displays addObject:currentDisplay];
                    NSDebugLog(@"Added display %@ to list", [currentDisplay name]);
                }
                [currentDisplay release];
                currentDisplay = nil;
                parsingModes = NO;
            }
            
            NSArray *parts = [trimmedLine componentsSeparatedByString:@" "];
            if ([parts count] >= 2) {
                currentDisplay = [[DisplayInfo alloc] init];
                [currentDisplay setOutput:[parts objectAtIndex:0]];
                [currentDisplay setName:[parts objectAtIndex:0]];
                [currentDisplay setIsConnected:[trimmedLine rangeOfString:@" connected"].location != NSNotFound];
                
                if ([currentDisplay isConnected]) {
                    parsingModes = YES;
                }
                
                NSDebugLog(@"Found display: %@ (connected: %d)", [currentDisplay name], [currentDisplay isConnected]);
                
                // Parse geometry if present
                if ([currentDisplay isConnected] && [parts count] >= 3) {
                    NSString *geomString = [parts objectAtIndex:2];
                    if ([geomString rangeOfString:@"x"].location != NSNotFound && 
                        [geomString rangeOfString:@"+"].location != NSNotFound) {
                        
                        // Parse resolution and position (e.g., "1920x1080+0+0")
                        NSArray *geomParts = [geomString componentsSeparatedByString:@"+"];
                        if ([geomParts count] >= 3) {
                            NSString *resPart = [geomParts objectAtIndex:0];
                            NSArray *resComponents = [resPart componentsSeparatedByString:@"x"];
                            if ([resComponents count] == 2) {
                                float width = [[resComponents objectAtIndex:0] floatValue];
                                float height = [[resComponents objectAtIndex:1] floatValue];
                                [currentDisplay setResolution:NSMakeSize(width, height)];
                                
                                float x = [[geomParts objectAtIndex:1] floatValue];
                                float y = [[geomParts objectAtIndex:2] floatValue];
                                [currentDisplay setFrame:NSMakeRect(x, y, width, height)];
                                
                                NSDebugLog(@"Display %@ resolution: %.0fx%.0f at %.0f,%.0f", 
                                     [currentDisplay name], width, height, x, y);
                            }
                        }
                        
                        // Check if this is the primary display
                        [currentDisplay setIsPrimary:[trimmedLine rangeOfString:@" primary"].location != NSNotFound];
                        if ([currentDisplay isPrimary]) {
                            NSDebugLog(@"Display %@ is primary", [currentDisplay name]);
                        }
                    } else {
                        // Display is connected but not configured - give it default values
                        NSDebugLog(@"Display %@ is connected but not configured, using defaults", [currentDisplay name]);
                        [currentDisplay setResolution:NSMakeSize(1920, 1080)]; // Default resolution
                        [currentDisplay setFrame:NSMakeRect(0, 0, 1920, 1080)]; // Default position
                        [currentDisplay setIsPrimary:YES]; // Make it primary if it's the only one
                    }
                } else if ([currentDisplay isConnected]) {
                    // Display is connected but no geometry info at all - use defaults
                    NSDebugLog(@"Display %@ is connected but has no geometry info, using defaults", [currentDisplay name]);
                    [currentDisplay setResolution:NSMakeSize(1920, 1080)]; // Default resolution
                    [currentDisplay setFrame:NSMakeRect(0, 0, 1920, 1080)]; // Default position
                    [currentDisplay setIsPrimary:YES]; // Make it primary if it's the only one
                }
            }
        } else if (parsingModes && [trimmedLine rangeOfString:@"x"].location != NSNotFound) {
            // Parse mode line for current display
            if ([trimmedLine rangeOfString:@"*"].location != NSNotFound) {
                // This is the current mode
                NSArray *parts = [trimmedLine componentsSeparatedByString:@" "];
                NSMutableArray *filteredParts = [NSMutableArray array];
                for (NSString *part in parts) {
                    NSString *trimmedPart = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([trimmedPart length] > 0) {
                        [filteredParts addObject:trimmedPart];
                    }
                }
                
                if ([filteredParts count] > 0) {
                    NSString *resPart = [filteredParts objectAtIndex:0];
                    [currentDisplay setCurrentResolutionString:resPart];
                    NSDebugLog(@"Display %@ current resolution string: %@", [currentDisplay name], resPart);
                }
            }
        }
    }
    
    // Finish last display if any
    if (currentDisplay) {
        if ([currentDisplay isConnected]) {
            [displays addObject:currentDisplay];
            NSDebugLog(@"Added display %@ to list", [currentDisplay name]);
        }
        [currentDisplay release];
        currentDisplay = nil;
    }
    
    NSDebugLog(@"DisplayController: Found %lu connected displays", (unsigned long)[displays count]);
    
    // If we have displays but none seem to be properly configured, try to auto-configure them
    BOOL hasConfiguredDisplay = NO;
    for (DisplayInfo *display in displays) {
        if ([display frame].size.width > 0 && [display frame].size.height > 0) {
            hasConfiguredDisplay = YES;
            break;
        }
    }
    
    if ([displays count] > 0 && !hasConfiguredDisplay) {
        NSDebugLog(@"DisplayController: No displays are properly configured, attempting auto-configuration");
        [self autoConfigureDisplays];
    }
}

- (void)updateResolutionPopup
{
    [resolutionPopup removeAllItems];
    
    // Get the selected display to show its available resolutions
    DisplayInfo *targetDisplay = selectedDisplay;
    
    // If no display is selected, default to primary display
    if (!targetDisplay) {
        for (DisplayInfo *display in displays) {
            if ([display isPrimary]) {
                targetDisplay = display;
                selectedDisplay = display; // Set as selected
                NSDebugLog(@"DisplayController: Auto-selecting primary display: %@", [display name]);
                break;
            }
        }
    }
    
    // If still no display, use first available and make it primary
    if (!targetDisplay && [displays count] > 0) {
        targetDisplay = [displays objectAtIndex:0];
        selectedDisplay = targetDisplay;
        [targetDisplay setIsPrimary:YES]; // Make first display primary if none is set
        NSDebugLog(@"DisplayController: Auto-selecting first display as primary: %@", [targetDisplay name]);
    }
    
    if (targetDisplay) {
        NSDebugLog(@"DisplayController: Updating resolution popup for display: %@", [targetDisplay name]);
        NSMutableArray *availableResolutions = [[self getAvailableResolutionsForDisplay:targetDisplay] mutableCopy];
        
        // Ensure current resolution is in the list
        NSString *currentRes = [targetDisplay currentResolutionString];
        if (!currentRes) {
            // Fallback to formatted size
            currentRes = [NSString stringWithFormat:@"%.0fx%.0f", 
                         [targetDisplay resolution].width, 
                         [targetDisplay resolution].height];
        }
        if (![availableResolutions containsObject:currentRes]) {
            [availableResolutions addObject:currentRes];
            NSDebugLog(@"DisplayController: Added current resolution to popup: %@", currentRes);
        }
        
        for (NSString *res in availableResolutions) {
            [resolutionPopup addItemWithTitle:res];
        }
        
        // Select current resolution
        [resolutionPopup selectItemWithTitle:currentRes];
        NSDebugLog(@"DisplayController: Set resolution popup to current resolution: %@", currentRes);
    }
}

- (NSArray *)getAvailableResolutionsForDisplay:(DisplayInfo *)display
{
    if (!display || ![self isXrandrAvailable]) {
        return @[];
    }

    // Use the already-parsed xrandr output stored in lastXrandrOutput
    // instead of spawning another blocking xrandr process on the main thread.
    if (!lastXrandrOutput) {
        return @[];
    }

    NSMutableArray *resolutions = [NSMutableArray array];
    NSArray *lines = [lastXrandrOutput componentsSeparatedByString:@"\n"];
    BOOL foundDisplay = NO;

    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        if ([trimmedLine hasPrefix:[display output]]) {
            foundDisplay = YES;
            continue;
        }

        if (foundDisplay) {
            if ([trimmedLine rangeOfString:@" connected"].location != NSNotFound ||
                [trimmedLine rangeOfString:@" disconnected"].location != NSNotFound) {
                break;
            }

            if ([trimmedLine rangeOfString:@"x"].location != NSNotFound) {
                NSArray *parts = [trimmedLine componentsSeparatedByString:@" "];
                for (NSString *part in parts) {
                    NSString *trimmedPart = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([trimmedPart length] > 0 && [trimmedPart rangeOfString:@"x"].location != NSNotFound) {
                        [resolutions addObject:trimmedPart];
                        break; // first token is the resolution
                    }
                }
            }
        }
    }

    return resolutions;
}

- (void)mirrorDisplaysChanged:(id)sender
{
    // Implementation for mirror displays
    BOOL mirror = [mirrorDisplaysCheckbox state] == NSOnState;
    
    NSDebugLog(@"DisplayController: Mirror displays changed to: %@", mirror ? @"ON" : @"OFF");
    
    if (mirror && [displays count] > 1) {
        // Enable mirroring
        NSMutableArray *args = [NSMutableArray array];
        DisplayInfo *primary = nil;
        
        // Find primary display
        for (DisplayInfo *display in displays) {
            if ([display isPrimary]) {
                primary = display;
                break;
            }
        }
        
        if (!primary && [displays count] > 0) {
            primary = [displays objectAtIndex:0];
        }
        
        if (primary) {
            NSDebugLog(@"DisplayController: Enabling mirroring with primary display: %@", [primary name]);
            
            [args addObject:@"--output"];
            [args addObject:[primary output]];
            [args addObject:@"--auto"];
            [args addObject:@"--primary"];
            
            for (DisplayInfo *display in displays) {
                if (display != primary) {
                    [args addObject:@"--output"];
                    [args addObject:[display output]];
                    [args addObject:@"--same-as"];
                    [args addObject:[primary output]];
                    NSDebugLog(@"DisplayController: Mirroring %@ to %@", [display name], [primary name]);
                }
            }
            
            [self runXrandrWithArgs:args];
        }
    } else {
        // Disable mirroring - arrange displays side by side
        NSDebugLog(@"DisplayController: Disabling mirroring, arranging displays side by side");
        [self applyDisplayConfiguration];
    }
}

- (void)resolutionChanged:(id)sender
{
    NSString *selectedResolution = [resolutionPopup titleOfSelectedItem];
    
    // Apply resolution to selected display
    DisplayInfo *targetDisplay = selectedDisplay;
    if (!targetDisplay) {
        NSDebugLog(@"DisplayController: No display selected for resolution change");
        return;
    }
    
    if (targetDisplay && selectedResolution) {
        // Store the current resolution for potential revert
        NSString *currentRes = [targetDisplay currentResolutionString];
        
        if ([selectedResolution isEqualToString:currentRes]) {
            NSDebugLog(@"DisplayController: Selected resolution same as current, no change needed");
            return; // No change needed
        }
        
        NSDebugLog(@"DisplayController: Changing resolution for %@ from %@ to %@", [targetDisplay name], currentRes, selectedResolution);
        
        // Apply the new resolution
        NSArray *args = @[@"--output", [targetDisplay output], @"--mode", selectedResolution];
        [self runXrandrWithArgs:args];
        
        // Show confirmation dialog with auto-revert timer
        [self showResolutionConfirmationDialogWithOldResolution:currentRes 
                                                 newResolution:selectedResolution 
                                                       display:targetDisplay];
    }
}

- (void)showResolutionConfirmationDialogWithOldResolution:(NSString *)oldRes 
                                           newResolution:(NSString *)newRes 
                                                 display:(DisplayInfo *)display
{
    NSDebugLog(@"DisplayController: Showing resolution confirmation dialog - old:%@ new:%@", oldRes, newRes);
    
    // Create a floating window for confirmation (non-modal to allow timer to work)
    NSWindow *confirmWindow = [[NSWindow alloc] 
        initWithContentRect:NSMakeRect(100, 100, 400, 150)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered
        defer:NO];
    
    [confirmWindow setTitle:@"Display Resolution Changed"];
    [confirmWindow setLevel:NSFloatingWindowLevel];
    [confirmWindow setHidesOnDeactivate:NO];
    
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 150)];
    [confirmWindow setContentView:contentView];
    
    // Message text
    NSTextField *messageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 80, 360, 40)];
    [messageLabel setStringValue:[NSString stringWithFormat:@"Resolution changed to %@.\nKeep this resolution? Auto-revert in 15 seconds.", newRes]];
    [messageLabel setBezeled:NO];
    [messageLabel setDrawsBackground:NO];
    [messageLabel setEditable:NO];
    [messageLabel setSelectable:NO];
    [messageLabel setAlignment:NSCenterTextAlignment];
    [contentView addSubview:messageLabel];
    [messageLabel release];
    
    // Countdown label
    NSTextField *countdownLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 360, 20)];
    [countdownLabel setStringValue:@"15"];
    [countdownLabel setBezeled:NO];
    [countdownLabel setDrawsBackground:NO];
    [countdownLabel setEditable:NO];
    [countdownLabel setSelectable:NO];
    [countdownLabel setAlignment:NSCenterTextAlignment];
    [countdownLabel setFont:[NSFont boldSystemFontOfSize:16]];
    [contentView addSubview:countdownLabel];
    
    // Buttons
    NSButton *revertButton = [[NSButton alloc] initWithFrame:NSMakeRect(220, 20, 80, 25)];
    [revertButton setTitle:@"Revert"];
    [revertButton setKeyEquivalent:@"\e"]; // ESC key
    [contentView addSubview:revertButton];
    
    NSButton *keepButton = [[NSButton alloc] initWithFrame:NSMakeRect(310, 20, 70, 25)];
    [keepButton setTitle:@"Keep"];
    [keepButton setKeyEquivalent:@"\r"]; // Enter key
    [contentView addSubview:keepButton];
    
    // Store data for timer and button actions
    NSMutableDictionary *dialogData = [[NSMutableDictionary alloc] init];
    [dialogData setObject:confirmWindow forKey:@"window"];
    [dialogData setObject:oldRes forKey:@"oldResolution"];
    [dialogData setObject:display forKey:@"display"];
    [dialogData setObject:countdownLabel forKey:@"countdownLabel"];
    [dialogData setObject:[NSNumber numberWithInt:15] forKey:@"countdown"];
    [dialogData setObject:@NO forKey:@"released"];
    
    // Assign unique ID and store in global registry
    if (!activeDialogsByID) {
        activeDialogsByID = [[NSMutableDictionary alloc] init];
    }
    NSInteger dialogID = ++dialogIDCounter;
    [dialogData setObject:@(dialogID) forKey:@"id"];
    [activeDialogsByID setObject:dialogData forKey:@(dialogID)];
    
    [revertButton setTarget:self];
    [revertButton setAction:@selector(resolutionRevertClicked:)];
    [revertButton setTag:dialogID];
    
    [keepButton setTarget:self];
    [keepButton setAction:@selector(resolutionKeepClicked:)];
    [keepButton setTag:dialogID];
    
    // Create countdown timer - Use NSRunLoop mainRunLoop to ensure it works
        NSTimer *countdownTimer = [NSTimer timerWithTimeInterval:1.0
                                                                                                            target:self
                                                                                                        selector:@selector(resolutionCountdownTimer:)
                                                                                                        userInfo:@(dialogID) // store ID to avoid retaining dialogData in timer
                                                                                                         repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:countdownTimer forMode:NSDefaultRunLoopMode];
    [dialogData setObject:countdownTimer forKey:@"timer"];
    
    [confirmWindow center];
    [confirmWindow makeKeyAndOrderFront:nil];
    [confirmWindow orderFrontRegardless]; // Ensure it appears on top
    
    [revertButton release];
    [keepButton release];
    [contentView release];
}

- (void)revertResolutionTimer:(NSTimer *)timer
{
    NSDictionary *userInfo = [timer userInfo];
    NSString *oldRes = [userInfo objectForKey:@"oldResolution"];
    DisplayInfo *display = [userInfo objectForKey:@"display"];
    
    NSDebugLog(@"Auto-reverting resolution to %@", oldRes);
    [self revertToResolution:oldRes forDisplay:display];
    
    // Show a brief notification
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Resolution Reverted"];
    [alert setInformativeText:[NSString stringWithFormat:@"The display resolution has been automatically reverted to %@.", oldRes]];
    [alert addButtonWithTitle:@"OK"];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert runModal];
    [alert release];
}

- (void)resolutionCountdownTimer:(NSTimer *)timer
{
    NSNumber *dialogIDNum = [timer userInfo];
    NSMutableDictionary *dialogData = [activeDialogsByID objectForKey:dialogIDNum];
    if (!dialogData) return;

    NSNumber *countdownNum = [dialogData objectForKey:@"countdown"];
    NSTextField *countdownLabel = [dialogData objectForKey:@"countdownLabel"];
    
    int countdown = [countdownNum intValue] - 1;
    [dialogData setObject:[NSNumber numberWithInt:countdown] forKey:@"countdown"];
    
    [countdownLabel setStringValue:[NSString stringWithFormat:@"%d", countdown]];
    
    if (countdown <= 0) {
        // Time's up - revert
        if ([[dialogData objectForKey:@"released"] boolValue]) return;
        [dialogData setObject:@YES forKey:@"released"];
        
        [timer invalidate];
        NSString *oldRes = [dialogData objectForKey:@"oldResolution"];
        DisplayInfo *display = [dialogData objectForKey:@"display"];
        NSWindow *window = [dialogData objectForKey:@"window"];
        
        NSNumber *dialogIDNum = [dialogData objectForKey:@"id"];
        NSTimer *timerFromData = [dialogData objectForKey:@"timer"];
        [timerFromData invalidate];
        [dialogData removeObjectForKey:@"timer"]; // release timer retained by dialogData
        [activeDialogsByID removeObjectForKey:dialogIDNum];
        
        NSDebugLog(@"DisplayController: Countdown reached 0, auto-reverting resolution");
        [self revertToResolution:oldRes forDisplay:display];
        [window close];
    }
}

- (void)resolutionRevertClicked:(id)sender
{
    NSButton *button = (NSButton *)sender;
    NSInteger dialogID = [button tag];
    NSMutableDictionary *dialogData = [activeDialogsByID objectForKey:@(dialogID)];
    
    if (!dialogData) return;
    
    if ([[dialogData objectForKey:@"released"] boolValue]) return;
    [dialogData setObject:@YES forKey:@"released"];
    
    NSTimer *timer = [dialogData objectForKey:@"timer"];
    NSString *oldRes = [dialogData objectForKey:@"oldResolution"];
    DisplayInfo *display = [dialogData objectForKey:@"display"];
    NSWindow *window = [dialogData objectForKey:@"window"];
    
    [timer invalidate];
    [dialogData removeObjectForKey:@"timer"]; // release timer retained by dialogData
    NSDebugLog(@"DisplayController: User clicked Revert button");
    [self revertToResolution:oldRes forDisplay:display];
    [window close];
    [activeDialogsByID removeObjectForKey:@(dialogID)];
}

- (void)resolutionKeepClicked:(id)sender
{
    NSButton *button = (NSButton *)sender;
    NSInteger dialogID = [button tag];
    NSMutableDictionary *dialogData = [activeDialogsByID objectForKey:@(dialogID)];
    
    if (!dialogData) return;
    
    if ([[dialogData objectForKey:@"released"] boolValue]) return;
    [dialogData setObject:@YES forKey:@"released"];
    
    NSTimer *timer = [dialogData objectForKey:@"timer"];
    NSWindow *window = [dialogData objectForKey:@"window"];
    
    [timer invalidate];
    [dialogData removeObjectForKey:@"timer"]; // release timer retained by dialogData
    NSDebugLog(@"DisplayController: User clicked Keep button - keeping new resolution");
    [window close];
    [activeDialogsByID removeObjectForKey:@(dialogID)];
}

- (void)revertToResolution:(NSString *)resolution forDisplay:(DisplayInfo *)display
{
    NSArray *args = @[@"--output", [display output], @"--mode", resolution];
    [self runXrandrWithArgs:args];
    
    // Update the popup to reflect the reverted resolution
    [resolutionPopup selectItemWithTitle:resolution];
}


- (void)runXrandrWithArgs:(NSArray *)args
{
    if (![self isXrandrAvailable]) {
        NSDebugLog(@"DisplayController: Cannot run xrandr - not available");
        return;
    }

    NSDebugLog(@"DisplayController: Running xrandr with args: %@", args);

    NSString *path = [xrandrPath retain];
    NSArray *argsCopy = [args retain];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:path];
        [task setArguments:argsCopy];

        [task launch];
        [task waitUntilExit];

        int exitStatus = [task terminationStatus];
        NSDebugLog(@"DisplayController: xrandr command completed with exit status: %d", exitStatus);

        [task release];
        [path release];
        [argsCopy release];

        // Refresh displays after change (back on main thread with delay)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshDisplays:nil];
        });
    });
}

- (void)applyDisplayConfiguration
{
    if ([displays count] == 0) return;
    
    NSMutableArray *args = [NSMutableArray array];
    
    // Sort displays by X position for left-to-right arrangement
    NSArray *sortedDisplays = [displays sortedArrayUsingComparator:^NSComparisonResult(DisplayInfo *obj1, DisplayInfo *obj2) {
        return [@([obj1 frame].origin.x) compare:@([obj2 frame].origin.x)];
    }];
    
    for (int i = 0; i < [sortedDisplays count]; i++) {
        DisplayInfo *display = [sortedDisplays objectAtIndex:i];
        
        [args addObject:@"--output"];
        [args addObject:[display output]];
        [args addObject:@"--auto"];
        
        if ([display isPrimary]) {
            [args addObject:@"--primary"];
        }
        
        if (i == 0) {
            [args addObject:@"--pos"];
            [args addObject:[NSString stringWithFormat:@"%.0fx%.0f", [display frame].origin.x, [display frame].origin.y]];
        } else {
            DisplayInfo *prevDisplay = [sortedDisplays objectAtIndex:i-1];
            [args addObject:@"--right-of"];
            [args addObject:[prevDisplay output]];
        }
    }
    
    [self runXrandrWithArgs:args];
}

- (void)setPrimaryDisplay:(DisplayInfo *)display
{
    NSDebugLog(@"DisplayController: Setting primary display to: %@", [display name]);
    
    // Update the isPrimary flag
    for (DisplayInfo *d in displays) {
        [d setIsPrimary:(d == display)];
    }
    
    // Apply the change via xrandr
    NSArray *args = @[@"--output", [display output], @"--primary"];
    [self runXrandrWithArgs:args];
}

- (NSString *)findXrandrPath
{
    NSDebugLog(@"DisplayController: Looking for xrandr in PATH");
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/which"];
    [task setArguments:@[@"xrandr"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [task launch];
    [task waitUntilExit];
    
    int exitStatus = [task terminationStatus];
    NSData *data = [file readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    [task release];
    
    if (exitStatus == 0 && output && [output length] > 0) {
        NSString *path = [output stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSDebugLog(@"DisplayController: Found xrandr at: %@", path);
        [output release];
        return path;
    } else {
        NSDebugLog(@"DisplayController: xrandr not found in PATH (exit status: %d)", exitStatus);
        [output release];
        return nil;
    }
}

- (BOOL)isXrandrAvailable
{
    return xrandrPath != nil;
}

- (NSArray *)displays
{
    return displays;
}

- (void)selectDisplay:(DisplayInfo *)display
{
    NSDebugLog(@"DisplayController: Selecting display: %@", [display name]);
    selectedDisplay = display;
    
    // Update resolution popup for selected display
    [self updateResolutionPopup];
    
    // Update the display view to show selection - update all display rectangles
    if (displayView) {
        NSArray *allRectViews = [displayView displayRects];
        for (DisplayRectView *rectView in allRectViews) {
            BOOL shouldBeSelected = ([rectView displayInfo] == display);
            [rectView setIsSelected:shouldBeSelected];
            [rectView setNeedsDisplay:YES];
        }
    }
}

- (DisplayInfo *)selectedDisplay
{
    return selectedDisplay;
}

- (NSString *)currentStateSnapshot
{
    NSMutableString *snap = [NSMutableString string];
    NSArray *sorted = [displays sortedArrayUsingComparator:^NSComparisonResult(DisplayInfo *a, DisplayInfo *b) {
        return [[a output] compare:[b output]];
    }];
    for (DisplayInfo *d in sorted) {
        if (![d isConnected]) continue;
        NSRect f = [d frame];
        [snap appendFormat:@"%@:%@:%.0f,%.0f:%d\n",
            [d output],
            [d currentResolutionString] ? [d currentResolutionString] : @"",
            f.origin.x, f.origin.y,
            [d isPrimary]];
    }
    return snap;
}

- (void)updateSaveButtonState
{
    if (!saveButton) return;

    if (!savedStateSnapshot) {
        // No saved snapshot yet — take one now (initial state)
        savedStateSnapshot = [[self currentStateSnapshot] copy];
        [saveButton setEnabled:NO];
        return;
    }

    NSString *current = [self currentStateSnapshot];
    BOOL changed = ![current isEqualToString:savedStateSnapshot];
    [saveButton setEnabled:changed];
}

// Marker comments used to identify our managed sections in xorg.conf
static NSString *const GERSHWIN_BEGIN = @"# BEGIN Gershwin Display Settings";
static NSString *const GERSHWIN_END   = @"# END Gershwin Display Settings";

- (NSString *)generateXorgConfSections
{
    NSMutableString *conf = [NSMutableString string];
    [conf appendString:GERSHWIN_BEGIN];
    [conf appendString:@"\n"];

    for (DisplayInfo *display in displays) {
        if (![display isConnected]) continue;

        NSString *identifier = [NSString stringWithFormat:@"Monitor-%@", [display output]];

        [conf appendFormat:@"Section \"Monitor\"\n"];
        [conf appendFormat:@"    Identifier \"%@\"\n", identifier];
        if ([display currentResolutionString]) {
            [conf appendFormat:@"    Option \"PreferredMode\" \"%@\"\n", [display currentResolutionString]];
        }
        if ([display isPrimary]) {
            [conf appendFormat:@"    Option \"Primary\" \"true\"\n"];
        }
        NSRect f = [display frame];
        [conf appendFormat:@"    Option \"Position\" \"%.0f %.0f\"\n", f.origin.x, f.origin.y];
        [conf appendString:@"EndSection\n\n"];

        [conf appendFormat:@"Section \"Screen\"\n"];
        [conf appendFormat:@"    Identifier \"Screen-%@\"\n", [display output]];
        [conf appendFormat:@"    Monitor \"%@\"\n", identifier];
        if ([display currentResolutionString]) {
            [conf appendFormat:@"    DefaultDepth 24\n"];
            [conf appendFormat:@"    SubSection \"Display\"\n"];
            [conf appendFormat:@"        Depth 24\n"];
            [conf appendFormat:@"        Modes \"%@\"\n", [display currentResolutionString]];
            [conf appendFormat:@"    EndSubSection\n"];
        }
        [conf appendString:@"EndSection\n\n"];
    }

    [conf appendString:GERSHWIN_END];
    return conf;
}

- (void)saveSettings:(id)sender
{
    if ([displays count] == 0) {
        NSRunAlertPanel(@"Save Settings",
                       @"No displays detected to save.",
                       @"OK", nil, nil);
        return;
    }

    NSString *xorgConfPath = @"/etc/X11/xorg.conf";
    NSString *newSections = [self generateXorgConfSections];
    NSString *finalContent = nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:xorgConfPath]) {
        NSString *existing = [NSString stringWithContentsOfFile:xorgConfPath
                                                      encoding:NSUTF8StringEncoding
                                                         error:NULL];
        if (existing) {
            // Strip any previous Gershwin managed block
            NSRange beginRange = [existing rangeOfString:GERSHWIN_BEGIN];
            NSRange endRange = [existing rangeOfString:GERSHWIN_END];

            if (beginRange.location != NSNotFound && endRange.location != NSNotFound) {
                NSUInteger blockEnd = endRange.location + endRange.length;
                // Also consume a trailing newline if present
                if (blockEnd < [existing length] &&
                    [existing characterAtIndex:blockEnd] == '\n') {
                    blockEnd++;
                }
                NSMutableString *stripped = [NSMutableString stringWithString:existing];
                [stripped deleteCharactersInRange:NSMakeRange(beginRange.location,
                                                              blockEnd - beginRange.location)];
                existing = stripped;
            }

            // Trim trailing whitespace from existing content, then append our block
            existing = [existing stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([existing length] > 0) {
                finalContent = [NSString stringWithFormat:@"%@\n\n%@\n", existing, newSections];
            } else {
                finalContent = [NSString stringWithFormat:@"%@\n", newSections];
            }
        } else {
            finalContent = [NSString stringWithFormat:@"%@\n", newSections];
        }
    } else {
        finalContent = [NSString stringWithFormat:@"%@\n", newSections];
    }

    // Write via a temp file and sudo mv for atomic root-owned write
    NSString *tmpPath = @"/tmp/gershwin-xorg.conf.tmp";
    NSError *error = nil;
    BOOL wrote = [finalContent writeToFile:tmpPath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&error];
    if (!wrote) {
        NSRunAlertPanel(@"Save Settings",
                       @"Failed to write temporary file: %@",
                       @"OK", nil, nil, [error localizedDescription]);
        return;
    }

    // Ensure /etc/X11 directory exists, then move the file into place
    NSString *cmd = [NSString stringWithFormat:
        @"sudo -A -E /bin/sh -c 'mkdir -p /etc/X11 && mv %@ %@'",
        tmpPath, xorgConfPath];

    NSTask *task = [[NSTask alloc] init];
    NSPipe *errPipe = [NSPipe pipe];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", cmd]];
    [task setStandardError:errPipe];

    @try {
        [task launch];
        NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];

        if ([task terminationStatus] == 0) {
            [savedStateSnapshot release];
            savedStateSnapshot = [[self currentStateSnapshot] copy];
            [saveButton setEnabled:NO];

            NSRunAlertPanel(@"Save Settings",
                           @"Display settings saved to %@.\n"
                           @"They will take effect on next X server restart.",
                           @"OK", nil, nil, xorgConfPath);
        } else {
            NSString *errStr = [[[NSString alloc] initWithData:errData
                                                      encoding:NSUTF8StringEncoding] autorelease];
            NSRunAlertPanel(@"Save Settings",
                           @"Failed to save settings: %@",
                           @"OK", nil, nil, errStr);
        }
    } @catch (NSException *exception) {
        NSRunAlertPanel(@"Save Settings",
                       @"Failed to save settings: %@",
                       @"OK", nil, nil, [exception reason]);
    }
    [task release];
}

- (void)autoConfigureDisplays
{
    NSDebugLog(@"DisplayController: Auto-configuring displays...");
    
    if ([displays count] == 0) {
        NSDebugLog(@"DisplayController: No displays to configure");
        return;
    }
    
    // Try to auto-configure each connected display
    NSMutableArray *args = [NSMutableArray array];
    
    for (DisplayInfo *display in displays) {
        if ([display isConnected]) {
            NSDebugLog(@"DisplayController: Auto-configuring display: %@", [display name]);
            [args addObject:@"--output"];
            [args addObject:[display output]];
            [args addObject:@"--auto"];
            
            // Make the first display primary
            if (display == [displays objectAtIndex:0]) {
                [args addObject:@"--primary"];
                [display setIsPrimary:YES];
                NSDebugLog(@"DisplayController: Setting %@ as primary display", [display name]);
            }
        }
    }
    
    if ([args count] > 0) {
        NSDebugLog(@"DisplayController: Running auto-configuration with args: %@", args);
        [self runXrandrWithArgs:args];
        
        // Note: runXrandrWithArgs already calls refreshDisplays with a delay
        // so we don't need to call it again here
    } else {
        NSDebugLog(@"DisplayController: No auto-configuration needed");
    }
}

@end
