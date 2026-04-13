/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BuildController.h"

@implementation BuildController

@synthesize makefilePath;

- (id)init
{
    self = [super init];
    if (self) {
        self.buildOutput = [[NSMutableString alloc] init];
        self.consoleMode = NO;
    }
    return self;
}

- (void)showWindow
{
    if (!getenv("DISPLAY")) {
        // Headless mode, just start build without GUI
        if (makefilePath) {
            [self startBuild];
        }
        return;
    }

    // Create window
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                         styleMask: NSTitledWindowMask | NSClosableWindowMask
                                           backing: NSBackingStoreBuffered
                                             defer: NO];

    [window setTitle: @"Build"];
    [window setDelegate: self];

    // Create status label
    statusLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 240, 360, 24)];
    [statusLabel setStringValue: @"Building..."];
    [statusLabel setEditable: NO];
    [statusLabel setBordered: NO];
    [statusLabel setDrawsBackground: NO];
    [statusLabel setAlignment: NSCenterTextAlignment];
    [statusLabel setFont: [NSFont fontWithName: @"Courier" size: 12.0]];
    [[window contentView] addSubview: statusLabel];

    // Create progress bar
    progressBar = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(20, 200, 360, 20)];
    [progressBar setStyle: NSProgressIndicatorBarStyle];
    [progressBar setIndeterminate: NO];
    [progressBar setMinValue: 0.0];
    [progressBar setMaxValue: 100.0];
    [progressBar setDoubleValue: 0.0];
    [[window contentView] addSubview: progressBar];

    // Create output text view
    outputScrollView = [[NSScrollView alloc] initWithFrame: NSMakeRect(20, 20, 360, 160)];
    [outputScrollView setBorderType: NSBezelBorder];
    [outputScrollView setHasVerticalScroller: YES];
    [outputScrollView setHasHorizontalScroller: YES];
    [outputScrollView setAutohidesScrollers: YES];

    outputView = [[NSTextView alloc] initWithFrame: [[outputScrollView contentView] frame]];
    [outputView setEditable: NO];
    [outputView setRichText: NO];
    [outputView setFont: [NSFont fontWithName: @"Courier" size: 10.0]];
    [outputScrollView setDocumentView: outputView];
    [[window contentView] addSubview: outputScrollView];

    [window makeKeyAndOrderFront: self];

    // Start build if makefile path is provided, otherwise show file dialog
    if (makefilePath) {
        [self startBuild];
    } else {
        [self showFileOpenDialog];
    }
}

- (void)showFileOpenDialog
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setTitle: @"Select GNUmakefile"];
    [openPanel setCanChooseFiles: YES];
    [openPanel setCanChooseDirectories: NO];
    [openPanel setAllowsMultipleSelection: NO];

    [openPanel beginSheetModalForWindow: window
                      completionHandler: ^(NSInteger result) {
        if (result == NSModalResponseOK) {
            NSArray *urls = [openPanel URLs];
            if ([urls count] > 0) {
                self.makefilePath = [[urls objectAtIndex: 0] path];
                [self startBuild];
            }
        }
    }];
}

- (void)startBuild
{
    // Clear previous output
    [self.buildOutput setString: @""];

    if (!makefilePath) {
        if (statusLabel) [statusLabel setStringValue: @"Error: No GNUmakefile specified"];
        return;
    }

    // Resolve to absolute path if needed
    if (![makefilePath hasPrefix: @"/"]) {
        NSString *currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        makefilePath = [currentDir stringByAppendingPathComponent: makefilePath];
        makefilePath = [makefilePath stringByStandardizingPath];
        self.makefilePath = makefilePath;
    }

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath: makefilePath]) {
        if (statusLabel) [statusLabel setStringValue: [NSString stringWithFormat: @"Error: GNUmakefile not found: %@", makefilePath]];
        return;
    }

    // Get directory containing the makefile
    NSString *directory = [makefilePath stringByDeletingLastPathComponent];
    if ([directory length] == 0) {
        directory = @".";
    }

    // Create task
    buildTask = [[NSTask alloc] init];
    [buildTask setCurrentDirectoryPath: directory];
    NSString *gmakePath = [NSTask launchPathForTool: @"gmake"];
    if (!gmakePath) {
        if (statusLabel) [statusLabel setStringValue: @"Error: gmake not found in PATH"];
        return;
    }
    [buildTask setLaunchPath: gmakePath];
    NSMutableArray *taskArgs = [NSMutableArray arrayWithObjects: @"-f", makefilePath, nil];
    if (self.extraArgs) {
        [taskArgs addObjectsFromArray: self.extraArgs];
    }
    [buildTask setArguments: taskArgs];
    [buildTask setEnvironment: [[NSProcessInfo processInfo] environment]];

    // Create output pipe and connect to task
    outputPipe = [[NSPipe alloc] init];
    [buildTask setStandardOutput: outputPipe];
    [buildTask setStandardError: outputPipe];

    // Set up notification for task termination
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(taskDidTerminate:)
                                                 name: NSTaskDidTerminateNotification
                                               object: buildTask];

    // Set up notification for output
    NSFileHandle *outputHandle = [outputPipe fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(outputAvailable:)
                                                 name: NSFileHandleReadCompletionNotification
                                               object: outputHandle];

    [outputHandle readInBackgroundAndNotify];

    // Start the task
    @try {
        [buildTask launch];
    } @catch (NSException *exception) {
        if (statusLabel) [statusLabel setStringValue: [NSString stringWithFormat: @"Error: Failed to start build: %@", [exception reason]]];
        return;
    }
}

- (void)outputAvailable:(NSNotification *)notification
{
    NSData *data = [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem];
    if ([data length] > 0) {
        NSString *output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        [self.buildOutput appendString: output];

        // Write to stdout for verbose output
        NSFileHandle *stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
        [stdoutHandle writeData: data];

        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update output view
            if (outputView) {
                [outputView setString: self.buildOutput];
                [outputView scrollRangeToVisible: NSMakeRange([[outputView string] length], 0)];
            }
        });

        // Continue reading
        [[notification object] readInBackgroundAndNotify];
    }
}

- (void)taskDidTerminate:(NSNotification *)notification
{
    NSTask *task = [notification object];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildFinished: task];
    });
}

- (void)buildFinished:(NSTask *)task
{
    int status = [task terminationStatus];
    if (status == 0) {
        if (statusLabel) [statusLabel setStringValue: @"Build completed successfully"];
        if (progressBar) [progressBar setDoubleValue: 100.0];
        if (self.consoleMode) {
            exit(0);
        } else {
            [NSApp terminate: self];
        }
    } else {
        if (statusLabel) [statusLabel setStringValue: @"Build failed"];
        if (progressBar) [progressBar setDoubleValue: 0.0];
        NSString *errorMessage = [self formatErrorOutput: self.buildOutput];
        NSDebugLLog(@"gwcomp", @"Build failed with the following output:\n%@", errorMessage);
        if (self.consoleMode) {
            exit(status);
        } else {
            [NSApp terminate: self];
        }
    }

    // Clean up
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSTaskDidTerminateNotification
                                                  object: task];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSFileHandleReadCompletionNotification
                                                  object: nil];
    buildTask = nil;
    outputPipe = nil;
    [self.buildOutput setString: @""];
}

- (NSString *)formatErrorOutput:(NSString *)output
{
    NSArray *lines = [output componentsSeparatedByString: @"\n"];

    // Remove empty lines at the end
    NSMutableArray *cleanLines = [NSMutableArray array];
    for (NSString *line in lines) {
        if ([line length] > 0) {
            [cleanLines addObject: line];
        }
    }

    NSUInteger totalLines = [cleanLines count];
    if (totalLines == 0) {
        return @"No output captured";
    }

    NSMutableString *formattedOutput = [NSMutableString string];

    // First 5 lines
    NSUInteger firstCount = MIN(5, totalLines);
    for (NSUInteger i = 0; i < firstCount; i++) {
        [formattedOutput appendFormat:@"%@\n", [cleanLines objectAtIndex: i]];
    }

    if (totalLines > 5) {
        [formattedOutput appendString:@"...\n"];

        // Last 25 lines
        NSUInteger lastCount = MIN(25, totalLines - 5);
        NSUInteger startIndex = totalLines - lastCount;
        for (NSUInteger i = startIndex; i < totalLines; i++) {
            [formattedOutput appendFormat:@"%@\n", [cleanLines objectAtIndex: i]];
        }
    }

    return formattedOutput;
}

- (void)windowWillClose:(NSNotification *)notification
{
    // Terminate any running build task
    if (buildTask && [buildTask isRunning]) {
        [buildTask terminate];
    }

    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [NSApp terminate: self];
}

@end