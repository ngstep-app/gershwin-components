/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "ScreenshotController.h"
#import "ScreenshotCapture.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSAlert.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSTimer.h>
#import <unistd.h>

@implementation ScreenshotController

@synthesize mainWindow;
@synthesize statusLabel;
@synthesize windowButton;
@synthesize areaButton;
@synthesize fullScreenButton;
@synthesize saveButton;
@synthesize copyButton;
@synthesize delayField;
@synthesize progressIndicator;

- (id)init {
    self = [super init];
    if (self) {
        currentMode = ScreenshotModeFullScreen;
        lastSavedPath = nil;
        capturedImage = nil;
    }
    return self;
}

- (void)dealloc {
    [lastSavedPath release];
    [capturedImage release];
    [ScreenshotCapture cleanupX11];
    [super dealloc];
}

- (void)createUI {
    // Create main menu
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    
    // Application menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"Screenshot" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Screenshot"];
    [appMenu addItemWithTitle:@"About Screenshot" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];
    [appMenu release];
    [appMenuItem release];
    
    [[NSApplication sharedApplication] setMainMenu:mainMenu];
    [mainMenu release];
    
    // Create main window (compact layout)
    NSRect windowFrame = NSMakeRect(100, 100, 420, 260);
    mainWindow = [[NSWindow alloc] initWithContentRect:windowFrame
                                             styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [mainWindow setTitle:@"Screenshot"];
    [mainWindow setDelegate:self];
    
    NSView *contentView = [mainWindow contentView];
    
    // Create status label
    NSRect statusFrame = NSMakeRect(15, 225, 390, 16);
    statusLabel = [[NSTextField alloc] initWithFrame:statusFrame];
    [statusLabel setStringValue:@"Ready to take screenshot"];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setBezeled:NO];
    [statusLabel setDrawsBackground:NO];
    [contentView addSubview:statusLabel];
    
    // Create mode selection label
    NSRect modeLabelFrame = NSMakeRect(15, 197, 390, 14);
    NSTextField *modeLabel = [[NSTextField alloc] initWithFrame:modeLabelFrame];
    [modeLabel setStringValue:@"Select capture mode:"];
    [modeLabel setEditable:NO];
    [modeLabel setSelectable:NO];
    [modeLabel setBezeled:NO];
    [modeLabel setDrawsBackground:NO];
    [contentView addSubview:modeLabel];
    [modeLabel release];
    
    // Create buttons for screenshot mode (evenly spaced)
    CGFloat btnY = 152;
    CGFloat btnHeight = 22;
    CGFloat btnWidth = 125;
    CGFloat spacing = 13;
    CGFloat startX = 15;
    
    NSRect windowBtnFrame = NSMakeRect(startX, btnY, btnWidth, btnHeight);
    windowButton = [[NSButton alloc] initWithFrame:windowBtnFrame];
    [windowButton setTitle:@"Window"];
    [windowButton setButtonType:NSMomentaryLight];
    [windowButton setTarget:self];
    [windowButton setAction:@selector(takeWindowScreenshot:)];
    [windowButton setEnabled:NO];
    [contentView addSubview:windowButton];
    
    NSRect areaBtnFrame = NSMakeRect(startX + btnWidth + spacing, btnY, btnWidth, btnHeight);
    areaButton = [[NSButton alloc] initWithFrame:areaBtnFrame];
    [areaButton setTitle:@"Area"];
    [areaButton setButtonType:NSMomentaryLight];
    [areaButton setTarget:self];
    [areaButton setAction:@selector(takeAreaScreenshot:)];
    [contentView addSubview:areaButton];
    
    NSRect fullScreenBtnFrame = NSMakeRect(startX + 2 * (btnWidth + spacing), btnY, btnWidth, btnHeight);
    fullScreenButton = [[NSButton alloc] initWithFrame:fullScreenBtnFrame];
    [fullScreenButton setTitle:@"Full Screen"];
    [fullScreenButton setButtonType:NSMomentaryLight];
    [fullScreenButton setTarget:self];
    [fullScreenButton setAction:@selector(takeFullScreenScreenshot:)];
    [contentView addSubview:fullScreenButton];
    
    // Create delay field label and input
    NSRect delayLabelFrame = NSMakeRect(15, 120, 110, 16);
    NSTextField *delayLabel = [[NSTextField alloc] initWithFrame:delayLabelFrame];
    [delayLabel setStringValue:@"Delay (seconds):"];
    [delayLabel setEditable:NO];
    [delayLabel setSelectable:NO];
    [delayLabel setBezeled:NO];
    [delayLabel setDrawsBackground:NO];
    [contentView addSubview:delayLabel];
    [delayLabel release];
    
    NSRect delayFieldFrame = NSMakeRect(125, 120, 50, 20);
    delayField = [[NSTextField alloc] initWithFrame:delayFieldFrame];
    [delayField setIntValue:0];
    [contentView addSubview:delayField];
    
    // Create save and copy buttons (bottom, equally sized)
    CGFloat actionBtnY = 20;
    CGFloat actionBtnHeight = 22;
    CGFloat actionBtnWidth = 200;
    CGFloat btnSpacing = 10;
    CGFloat totalBtnWidth = 2 * actionBtnWidth + btnSpacing;
    CGFloat btnStartX = (420 - totalBtnWidth) / 2;
    
    NSRect saveBtnFrame = NSMakeRect(btnStartX, actionBtnY, actionBtnWidth, actionBtnHeight);
    saveButton = [[NSButton alloc] initWithFrame:saveBtnFrame];
    [saveButton setTitle:@"Save Screenshot"];
    [saveButton setButtonType:NSMomentaryLight];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(saveScreenshot:)];
    [saveButton setEnabled:NO];
    [contentView addSubview:saveButton];
    
    NSRect copyBtnFrame = NSMakeRect(btnStartX + actionBtnWidth + btnSpacing, actionBtnY, actionBtnWidth, actionBtnHeight);
    copyButton = [[NSButton alloc] initWithFrame:copyBtnFrame];
    [copyButton setTitle:@"Copy to Clipboard"];
    [copyButton setButtonType:NSMomentaryLight];
    [copyButton setTarget:self];
    [copyButton setAction:@selector(copyToClipboard:)];
    [copyButton setEnabled:NO];
    [contentView addSubview:copyButton];
    
    // Create progress indicator
    NSRect progressFrame = NSMakeRect(400, 180, 16, 16);
    progressIndicator = [[NSProgressIndicator alloc] initWithFrame:progressFrame];
    [progressIndicator setStyle:NSProgressIndicatorSpinningStyle];
    [progressIndicator setHidden:YES];
    [contentView addSubview:progressIndicator];
    
    // Initialize mode
    [self setScreenshotMode:ScreenshotModeFullScreen];
}

#pragma mark - Application Delegate Methods

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Check if we were launched with command line arguments
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    
    if ([arguments count] > 1) {
        [self handleCommandLineArguments];
        return;
    }
    
    // Initialize X11 system
    if (![ScreenshotCapture initializeX11]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Screenshot Error"];
        [alert setInformativeText:@"Failed to initialize screenshot system. Make sure X11 is running."];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert runModal];
        [alert release];
        
        [[NSApplication sharedApplication] terminate:self];
        return;
    }
    
    // Set up the application delegate
    [[NSApplication sharedApplication] setDelegate:self];
    
    // Create the UI programmatically
    [self createUI];
    
    // Show main window
    if (mainWindow) {
        [mainWindow makeKeyAndOrderFront:self];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [ScreenshotCapture cleanupX11];
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename {
    // Handle file opening requests
    return NO;
}

#pragma mark - Screenshot Actions

- (IBAction)takeWindowScreenshot:(id)sender {
    [self setScreenshotMode:ScreenshotModeWindow];
    [self performScreenshotWithMode:ScreenshotModeWindow];
}

- (IBAction)takeAreaScreenshot:(id)sender {
    [self setScreenshotMode:ScreenshotModeArea];
    [self performScreenshotWithMode:ScreenshotModeArea];
}

- (IBAction)takeFullScreenScreenshot:(id)sender {
    [self setScreenshotMode:ScreenshotModeFullScreen];
    [self performScreenshotWithMode:ScreenshotModeFullScreen];
}

- (void)performScreenshotWithMode:(ScreenshotMode)mode {
    [self updateStatus:@"Taking screenshot..."];
    [self showProgressIndicator:YES];
    
    int delay = [delayField intValue];
    CaptureRect rect = {0, 0, 0, 0};
    
    // Get selection rectangle for window/area modes
    if (mode == ScreenshotModeWindow) {
        // Hide the main window while the user selects a window so it doesn't get captured
        BOOL windowWasVisible = (mainWindow && [mainWindow isVisible]);
        if (windowWasVisible) {
            [mainWindow orderOut:self];
            // Give the window manager more time to unmap the window before grabbing pointer
            usleep(250000); // 250ms - needed for X11 pointer grab to succeed
        }

        rect = [ScreenshotCapture selectWindow];

        // Restore the main window after selection
        if (windowWasVisible) {
            [mainWindow makeKeyAndOrderFront:self];
        }

        [self showProgressIndicator:NO];
        if (rect.width == 0 || rect.height == 0) {
            [self updateStatus:@"Window selection cancelled or failed"];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Window Selection Failed"];
            [alert setInformativeText:@"Unable to select window. This may be due to an X11 error. Check the terminal for details."];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];
            [alert release];
            return;
        }
    } else if (mode == ScreenshotModeArea) {
        // Hide the main window while the user selects an area so it doesn't get captured
        BOOL windowWasVisible = (mainWindow && [mainWindow isVisible]);
        if (windowWasVisible) {
            [mainWindow orderOut:self];
            // Give the window manager more time to unmap the window before grabbing pointer
            usleep(250000); // 250ms - needed for X11 pointer grab to succeed
        }

        rect = [ScreenshotCapture selectArea];

        // Restore the main window after selection
        if (windowWasVisible) {
            [mainWindow makeKeyAndOrderFront:self];
        }

        [self showProgressIndicator:NO];
        if (rect.width == 0 || rect.height == 0) {
            [self updateStatus:@"Area selection cancelled or failed"];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Area Selection Failed"];
            [alert setInformativeText:@"Unable to select area. This may be due to an X11 error. Check the terminal for details."];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];
            [alert release];
            return;
        }
    }
    
    // Perform the capture with the selected rect
    [self captureScreenshotWithRect:rect mode:mode delay:delay];
}

- (void)captureScreenshotWithRect:(CaptureRect)rect mode:(ScreenshotMode)mode delay:(int)delay {
    CaptureMode captureMode;
    
    switch (mode) {
        case ScreenshotModeWindow:
            captureMode = CaptureWindow;
            break;
        case ScreenshotModeArea:
            captureMode = CaptureArea;
            break;
        case ScreenshotModeFullScreen:
        default:
            captureMode = CaptureFullScreen;
            break;
    }
    
    // Capture the image
    NSImage *image = [ScreenshotCapture captureImageWithMode:captureMode delay:delay rect:rect];
    
    [self showProgressIndicator:NO];
    
    if (image) {
        [capturedImage release];
        capturedImage = [image retain];
        [self updateStatus:@"Screenshot captured successfully"];
        [saveButton setEnabled:YES];
        [copyButton setEnabled:YES];
    } else {
        [self updateStatus:@"Failed to capture screenshot"];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Screenshot Failed"];
        [alert setInformativeText:@"Unable to capture screenshot. This may be due to an X11 error or insufficient permissions. Please try again."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
    }
}

- (IBAction)saveScreenshot:(id)sender {
    if (!capturedImage) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"No Screenshot"];
        [alert setInformativeText:@"Please take a screenshot first."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }
    
    [self showSavePanel];
}

- (IBAction)copyToClipboard:(id)sender {
    NSLog(@"=== Copy to Clipboard Started ===");
    
    if (!capturedImage) {
        NSLog(@"ERROR: No captured image");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"No Screenshot"];
        [alert setInformativeText:@"Please take a screenshot first."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }
    
    NSLog(@"Step 1: Getting TIFF representation from captured image");
    NSData *tiffData = [capturedImage TIFFRepresentation];
    if (!tiffData) {
        NSLog(@"ERROR: Failed to get TIFF representation");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Copy Failed"];
        [alert setInformativeText:@"Unable to get TIFF representation."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }
    NSLog(@"TIFF data size: %lu bytes", (unsigned long)[tiffData length]);
    
    NSLog(@"Step 2: Creating bitmap from TIFF data");
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    if (!bitmap) {
        NSLog(@"ERROR: Failed to create bitmap from TIFF");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Copy Failed"];
        [alert setInformativeText:@"Unable to get bitmap representation."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }
    NSLog(@"Bitmap created: %ldx%ld, %ld bps, %ld spp", 
          (long)[bitmap pixelsWide], (long)[bitmap pixelsHigh],
          (long)[bitmap bitsPerSample], (long)[bitmap samplesPerPixel]);
    
    NSLog(@"Step 3: Converting bitmap to PNG (SAME AS SAVING)");
    NSData *pngData = [bitmap representationUsingType:NSPNGFileType properties:nil];
    if (!pngData) {
        NSLog(@"ERROR: Failed to create PNG data");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Copy Failed"];
        [alert setInformativeText:@"Unable to create PNG data for clipboard."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }
    NSLog(@"PNG data size: %lu bytes", (unsigned long)[pngData length]);
    
    // Plausibility check
    if ([pngData length] < 100) {
        NSLog(@"ERROR: PNG data suspiciously small: %lu bytes", (unsigned long)[pngData length]);
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Copy Failed"];
        [alert setInformativeText:@"Generated PNG data is invalid (too small)."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }
    
    // Verify PNG header
    const unsigned char *bytes = [pngData bytes];
    if ([pngData length] >= 8) {
        NSLog(@"PNG header: %02x %02x %02x %02x %02x %02x %02x %02x",
              bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7]);
        if (bytes[0] != 0x89 || bytes[1] != 0x50 || bytes[2] != 0x4E || bytes[3] != 0x47) {
            NSLog(@"WARNING: PNG header is invalid!");
        } else {
            NSLog(@"PNG header is valid");
        }
    }
    
    NSLog(@"Step 4: Putting PNG data on clipboard");
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    if (!pasteboard) {
        NSLog(@"ERROR: Failed to get pasteboard");
        return;
    }
    NSLog(@"Got pasteboard: %@", pasteboard);
    
    NSLog(@"Declaring types (this clears the pasteboard automatically)...");
    NSArray *types = [NSArray arrayWithObject:NSPasteboardTypePNG];
    NSLog(@"Types array created: %@", types);
    
    @try {
        NSLog(@"Calling declareTypes...");
        [pasteboard declareTypes:types owner:nil];
        NSLog(@"declareTypes completed");
    } @catch (NSException *exception) {
        NSLog(@"EXCEPTION in declareTypes: %@", exception);
        return;
    }
    
    NSLog(@"Setting PNG data (%lu bytes)...", (unsigned long)[pngData length]);
    @try {
        BOOL pngSuccess = [pasteboard setData:pngData forType:NSPasteboardTypePNG];
        NSLog(@"PNG set result: %d", pngSuccess);
        
        if (pngSuccess) {
            NSLog(@"=== Copy to Clipboard Completed Successfully ===");
            [self updateStatus:@"Screenshot copied to clipboard"];
        } else {
            NSLog(@"ERROR: Failed to set PNG data on pasteboard");
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Copy Failed"];
            [alert setInformativeText:@"Unable to put PNG data on clipboard."];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];
            [alert release];
        }
    } @catch (NSException *exception) {
        NSLog(@"EXCEPTION in setData: %@", exception);
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Copy Failed"];
        [alert setInformativeText:[NSString stringWithFormat:@"Exception: %@", [exception reason]]];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
    }
}

#pragma mark - Utility Methods

- (void)updateStatus:(NSString *)status {
    if (statusLabel) {
        [statusLabel setStringValue:status];
    } else {
        NSLog(@"Screenshot: %@", status);
    }
}

- (void)showProgressIndicator:(BOOL)show {
    if (progressIndicator) {
        if (show) {
            [progressIndicator startAnimation:self];
            [progressIndicator setHidden:NO];
        } else {
            [progressIndicator stopAnimation:self];
            [progressIndicator setHidden:YES];
        }
    }
}

- (void)setScreenshotMode:(ScreenshotMode)mode {
    currentMode = mode;
    
    // Update UI to reflect current mode
    if (windowButton && areaButton && fullScreenButton) {
        [windowButton setState:(mode == ScreenshotModeWindow) ? NSOnState : NSOffState];
        [areaButton setState:(mode == ScreenshotModeArea) ? NSOnState : NSOffState];
        [fullScreenButton setState:(mode == ScreenshotModeFullScreen) ? NSOnState : NSOffState];
    }
}

- (NSString *)generateDefaultFileName {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HHmmss"];
    NSString *dateString = [formatter stringFromDate:[NSDate date]];
    [formatter release];
    
    NSString *filename = [NSString stringWithFormat:@"Screenshot-%@.png", dateString];
    
    // Get desktop path
    NSArray *desktopPaths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    if ([desktopPaths count] > 0) {
        NSString *desktopPath = [desktopPaths objectAtIndex:0];
        return [desktopPath stringByAppendingPathComponent:filename];
    }
    
    return filename;
}

- (BOOL)saveImageToFile:(NSString *)filepath {
    if (!capturedImage) {
        return NO;
    }
    
    NSData *imageData = [capturedImage TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:imageData];
    
    if (!bitmap) {
        return NO;
    }
    
    NSData *pngData = [bitmap representationUsingType:NSPNGFileType properties:nil];
    if (!pngData) {
        return NO;
    }
    
    return [pngData writeToFile:filepath atomically:YES];
}

- (void)showSavePanel {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"png"]];
    [panel setCanCreateDirectories:YES];
    
    // Generate default filename and set it
    NSString *defaultPath = [self generateDefaultFileName];
    [panel setNameFieldStringValue:[defaultPath lastPathComponent]];
    
    NSString *directory = [defaultPath stringByDeletingLastPathComponent];
    if (directory && [directory length] > 0) {
        [panel setDirectoryURL:[NSURL fileURLWithPath:directory]];
    }
    
    NSInteger result = [panel runModal];
    if (result == NSFileHandlingPanelOKButton) {
        NSString *filepath = [[panel URL] path];
        if ([self saveImageToFile:filepath]) {
            [lastSavedPath release];
            lastSavedPath = [filepath retain];
            [self updateStatus:[NSString stringWithFormat:@"Saved to: %@", filepath]];
            [self updateStatus:[NSString stringWithFormat:@"Screenshot saved to %@", [filepath lastPathComponent]]];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Save Failed"];
            [alert setInformativeText:@"Unable to save screenshot to the specified location."];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];
            [alert release];
        }
    }
}

#pragma mark - Command Line Handling

- (void)handleCommandLineArguments {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    
    // Parse arguments
    BOOL showHelp = NO;
    NSString *outputFile = nil;
    int delay = 0;
    ScreenshotMode mode = ScreenshotModeFullScreen;
    
    for (int i = 1; i < [arguments count]; i++) {
        NSString *arg = [arguments objectAtIndex:i];
        
        if ([arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]) {
            showHelp = YES;
            break;
        } else if ([arg isEqualToString:@"-a"] || [arg isEqualToString:@"--area"]) {
            mode = ScreenshotModeArea;
        } else if ([arg isEqualToString:@"-s"] || [arg isEqualToString:@"--screen"]) {
            mode = ScreenshotModeScreen;
        } else if ([arg isEqualToString:@"-w"] || [arg isEqualToString:@"--window"]) {
            mode = ScreenshotModeWindow;
        } else if ([arg isEqualToString:@"-d"] || [arg isEqualToString:@"--delay"]) {
            if (i + 1 < [arguments count]) {
                delay = [[arguments objectAtIndex:++i] intValue];
            }
        } else if ([arg isEqualToString:@"-o"] || [arg isEqualToString:@"--output"]) {
            if (i + 1 < [arguments count]) {
                outputFile = [arguments objectAtIndex:++i];
            }
        } else if (![arg hasPrefix:@"-"] && !outputFile) {
            outputFile = arg;
        }
    }
    
    if (showHelp) {
        [self printUsageAndExit];
        return;
    }
    
    // Initialize X11
    if (![ScreenshotCapture initializeX11]) {
        fprintf(stderr, "Error: Failed to initialize screenshot system\n");
        exit(1);
    }
    
    // Apply delay before any interaction
    if (delay > 0) {
        printf("Waiting %d seconds...\n", delay);
        sleep(delay);
    }
    
    // Take screenshot
    if (!outputFile) {
        outputFile = [self generateDefaultFileName];
    }
    
    CaptureMode captureMode;
    CaptureRect rect = {0, 0, 0, 0};
    
    switch (mode) {
        case ScreenshotModeWindow:
            captureMode = CaptureWindow;
            printf("Click on a window to capture...\n");
            rect = [ScreenshotCapture selectWindow];
            if (rect.width == 0 || rect.height == 0) {
                fprintf(stderr, "Error: No window selected\n");
                exit(1);
            }
            break;
        case ScreenshotModeArea:
            captureMode = CaptureArea;
            printf("Select an area to capture...\n");
            rect = [ScreenshotCapture selectArea];
            if (rect.width == 0 || rect.height == 0) {
                fprintf(stderr, "Error: No area selected\n");
                exit(1);
            }
            break;
        case ScreenshotModeScreen:
            captureMode = CaptureFullScreen;
            break;
        case ScreenshotModeFullScreen:
        default:
            captureMode = CaptureFullScreen;
            break;
    }
    
    NSString *result = [ScreenshotCapture captureScreenshotWithMode:captureMode 
                                                      filename:outputFile 
                                                         delay:0  // Delay already applied
                                                          rect:rect];
    
    if (result) {
        printf("Screenshot saved to: %s\n", [result UTF8String]);
        exit(0);
    } else {
        fprintf(stderr, "Error: Failed to capture screenshot\n");
        exit(1);
    }
}

- (void)printUsageAndExit {
    printf("Screenshot - GNUstep Screenshot Application\n\n");
    printf("Usage: Screenshot [options] [output-file]\n\n");
    printf("Options:\n");
    printf("  -h, --help         Show this help message\n");
    printf("  -a, --area         Select area to screenshot (alias: --select)\n");
    printf("  -w, --window       Select window to screenshot\n");
    printf("  -s, --screen       Capture the whole screen where cursor is\n");
    printf("  -d, --delay SEC    Wait SEC seconds before taking screenshot\n");
    printf("  -o, --output FILE  Save screenshot to FILE\n");
    printf("\n");
    printf("If no options are specified, a full screen screenshot will be taken.\n");
    printf("If no output file is specified, a default name will be generated.\n");
    
    exit(0);
}

@end