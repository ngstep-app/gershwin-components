/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define DS_SOCKET_PATH "/var/run/dshelper.sock"

/* Saved stdout fd for password output — set in main() before GNUstep init
 * can pollute stdout with startup messages. */
static int savedStdoutFd = -1;

@interface SudoAskPassController : NSObject<NSTextFieldDelegate>
{
    NSWindow *window;
    NSSecureTextField *passwordField;
    NSTextField *promptLabel;
    NSButton *okButton;
    NSButton *cancelButton;
    NSButton *detailsButton;
    NSTextField *commandLabel;
    NSScrollView *commandScrollView;
    NSString *sudoCommand;
    BOOL cancelled;
    BOOL detailsVisible;
}

- (void)showPasswordDialog;
- (BOOL)validatePassword:(NSString *)password;
- (void)shakeWindow;
- (void)updateOKButtonState;
- (void)okClicked:(id)sender;
- (void)cancelClicked:(id)sender;
- (void)detailsClicked:(id)sender;
- (void)applicationWillFinishLaunching:(NSNotification *)notification;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;

@end

@implementation SudoAskPassController

- (id)init
{
    self = [super init];
    if (self) {
        cancelled = NO;
        detailsVisible = NO;
    }
    return self;
}

- (void)showPasswordDialog
{

    // Check command line arguments as fallback - extract actual command after sudo options
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    if ([args count] > 1) {
        // Look for the command after sudo options (skip -A, -E, etc.)
        NSMutableArray *commandParts = [NSMutableArray array];
        BOOL foundCommand = NO;
        for (int i = 1; i < [args count]; i++) {
            NSString *arg = [args objectAtIndex:i];
            // Skip sudo options that start with dash
            if ([arg hasPrefix:@"-"] && !foundCommand) {
                continue;
            }
            foundCommand = YES;
            [commandParts addObject:arg];
        }
        if ([commandParts count] > 0) {
            sudoCommand = [[commandParts componentsJoinedByString:@" "] retain];
        } else {
            sudoCommand = [[NSString stringWithFormat:@"Arguments: %@", [args componentsJoinedByString:@" "]] retain];
        }
    }


    // Create window with initial size (compact mode)
    NSRect windowRect = NSMakeRect(100, 100, 400, 150);
    window = [[NSWindow alloc] initWithContentRect:windowRect
                                         styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];

    if (!window) {
        // If window creation fails, exit gracefully
        exit(1);
    }

    [window setTitle:@"Password"];
    [window center];
    [window setLevel:NSFloatingWindowLevel]; // Keep window on top

    // Disable system beeps and alerts for this window
    [window setHidesOnDeactivate:NO];

    // Create prompt label
    NSRect promptRect = NSMakeRect(24, 90, 352, 30);
    promptLabel = [[NSTextField alloc] initWithFrame:promptRect];
    [promptLabel setStringValue:@"Enter your password for sudo:"];
    [promptLabel setBezeled:NO];
    [promptLabel setDrawsBackground:NO];
    [promptLabel setEditable:NO];
    [promptLabel setSelectable:NO];
    [[window contentView] addSubview:promptLabel];

    // Create password field
    NSRect passwordRect = NSMakeRect(24, 60, 352, 22);
    passwordField = [[NSSecureTextField alloc] initWithFrame:passwordRect];
    [passwordField setDelegate:self];  // Set delegate to monitor text changes
    [[window contentView] addSubview:passwordField];

    // Create Details button (left side)
    NSRect detailsRect = NSMakeRect(24, 20, 80, 24);
    detailsButton = [[NSButton alloc] initWithFrame:detailsRect];
    [detailsButton setTitle:@"Details"];
    [detailsButton setTarget:self];
    [detailsButton setAction:@selector(detailsClicked:)];
    [[window contentView] addSubview:detailsButton];

    // Create OK button (right side, 24px from right edge: 400-24-80 = 296)
    NSRect okRect = NSMakeRect(296, 20, 80, 24);
    okButton = [[NSButton alloc] initWithFrame:okRect];
    [okButton setTitle:@"OK"];
    [okButton setTarget:self];
    [okButton setAction:@selector(okClicked:)];
    [okButton setKeyEquivalent:@"\r"];
    [okButton setEnabled:NO]; // Initially disabled
    [[window contentView] addSubview:okButton];

    // Create Cancel button (12px gap from OK: 296-80-12 = 204)
    NSRect cancelRect = NSMakeRect(204, 20, 80, 24);
    cancelButton = [[NSButton alloc] initWithFrame:cancelRect];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancelClicked:)];
    [cancelButton setKeyEquivalent:@"\033"];
    [[window contentView] addSubview:cancelButton];

    // Create command details (initially hidden)
    NSRect commandRect = NSMakeRect(24, 55, 352, 60);
    commandScrollView = [[NSScrollView alloc] initWithFrame:commandRect];
    [commandScrollView setHasVerticalScroller:YES];
    [commandScrollView setHasHorizontalScroller:YES];
    [commandScrollView setAutohidesScrollers:YES];
    [commandScrollView setBorderType:NSBezelBorder];
    [commandScrollView setHidden:YES];

    NSSize contentSize = [commandScrollView contentSize];
    commandLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    [commandLabel setStringValue:[NSString stringWithFormat:@"%@", sudoCommand]];
    [commandLabel setBezeled:NO];
    [commandLabel setDrawsBackground:YES];
    [commandLabel setBackgroundColor:[NSColor controlBackgroundColor]];
    [commandLabel setEditable:NO];
    [commandLabel setSelectable:YES];
    [commandLabel setFont:[NSFont fontWithName:@"Monaco" size:10]];
    [commandScrollView setDocumentView:commandLabel];

    [[window contentView] addSubview:commandScrollView];

    // Show window immediately and aggressively
    [window makeKeyAndOrderFront:nil];
    [window orderFrontRegardless]; // Force window to front immediately
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

    // Set focus to password field immediately - no delay
    [window makeFirstResponder:passwordField];
}

- (void)okClicked:(id)sender
{
    NSString *password = [passwordField stringValue];

    if (password && [password length] > 0) {
        if ([self validatePassword:password]) {
            // Password is correct, write to saved stdout fd and exit.
            // We use the saved fd because GNUstep may have written
            // startup messages to stdout, corrupting the askpass protocol.
            const char *pw = [password UTF8String];
            write(savedStdoutFd, pw, strlen(pw));
            write(savedStdoutFd, "\n", 1);
            [NSApp terminate:nil];
        } else {
            // Password is wrong, shake window and clear field
            [self shakeWindow];
            [passwordField setStringValue:@""];
            [self updateOKButtonState];
            [window makeFirstResponder:passwordField];
        }
    }
}

- (void)cancelClicked:(id)sender
{
    cancelled = YES;
    [NSApp terminate:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self showPasswordDialog];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    // Ensure our window is on top when we become active
    if (window) {
        [window makeKeyAndOrderFront:nil];
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    return NSTerminateNow;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)dealloc
{
    [window release];
    [passwordField release];
    [promptLabel release];
    [okButton release];
    [cancelButton release];
    [detailsButton release];
    [commandLabel release];
    [commandScrollView release];
    [sudoCommand release];
    [super dealloc];
}

- (void)detailsClicked:(id)sender
{
    @try {
        detailsVisible = !detailsVisible;

        NSRect currentFrame = [window frame];
        NSRect newFrame;

        if (detailsVisible) {
            // Expand window to show details - make it taller to fit command area
            newFrame = NSMakeRect(currentFrame.origin.x, currentFrame.origin.y - 132, 400, 282);
            [detailsButton setTitle:@"Hide Details"];

            [promptLabel setFrame:NSMakeRect(24, 222, 352, 20)];  // 40px from top
            [passwordField setFrame:NSMakeRect(24, 192, 352, 22)]; // 68px from top
            [commandScrollView setFrame:NSMakeRect(24, 54, 352, 130)];
            [commandScrollView setHidden:NO];

            // Buttons stay at bottom
            [detailsButton setFrame:NSMakeRect(24, 20, 80, 24)];
            [cancelButton setFrame:NSMakeRect(204, 20, 80, 24)];
            [okButton setFrame:NSMakeRect(296, 20, 80, 24)];
        } else {
            // Collapse window to hide details - RESET to EXACT original compact positions
            newFrame = NSMakeRect(currentFrame.origin.x, currentFrame.origin.y + 132, 400, 150);
            [detailsButton setTitle:@"Details"];

            // CRITICAL: Reset to EXACT original compact view positions as in showPasswordDialog
            [promptLabel setFrame:NSMakeRect(24, 90, 352, 20)];  // EXACT original position
            [passwordField setFrame:NSMakeRect(24, 60, 352, 22)]; // EXACT original position
            [commandScrollView setHidden:YES];

            // Reset buttons to EXACT original positions
            [detailsButton setFrame:NSMakeRect(24, 20, 80, 24)];
            [cancelButton setFrame:NSMakeRect(204, 20, 80, 24)];
            [okButton setFrame:NSMakeRect(296, 20, 80, 24)];
        }

        [window setFrame:newFrame display:YES animate:YES];
    }
    @catch (NSException *exception) {
        // If animation fails, just ignore it
    }
}

- (BOOL)validatePassword:(NSString *)password
{
    // Validate password via Gershwin Directory Services dshelper socket.
    // Using the auth protocol avoids recursively spawning sudo (which would
    // re-invoke this askpass helper via SUDO_ASKPASS).

    NSString *username = NSUserName();
    if (!username || [username length] == 0) {
        return NO;
    }

    // Connect to dshelper Unix socket
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        return NO;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, DS_SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return NO;
    }

    // Send auth request: "auth:username:password"
    NSString *request = [NSString stringWithFormat:@"auth:%@:%@", username, password];
    const char *requestBytes = [request UTF8String];
    ssize_t written = write(sock, requestBytes, strlen(requestBytes));
    if (written < 0) {
        close(sock);
        return NO;
    }

    // Shutdown write side so dshelper knows the request is complete
    shutdown(sock, SHUT_WR);

    // Read response
    char buf[16];
    memset(buf, 0, sizeof(buf));
    ssize_t bytesRead = read(sock, buf, sizeof(buf) - 1);
    close(sock);

    if (bytesRead <= 0) {
        return NO;
    }

    // dshelper returns "1" for success, "0" for failure
    return (buf[0] == '1');
}

- (void)shakeWindow
{
    NSRect originalFrame = [window frame];
    NSRect shakeFrame = originalFrame;

    // Create a shake animation by moving the window left and right
    for (int i = 0; i < 6; i++) {
        // Move window 10 pixels to the right, then left
        shakeFrame.origin.x = originalFrame.origin.x + ((i % 2 == 0) ? 10 : -10);
        [window setFrame:shakeFrame display:YES];

        // Small delay between shake movements
        usleep(50000); // 50ms delay

        // Process events to ensure smooth animation
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    }

    // Return to original position
    [window setFrame:originalFrame display:YES];
}

- (void)updateOKButtonState
{
    NSString *password = [passwordField stringValue];
    BOOL hasPassword = (password && [password length] > 0);
    [okButton setEnabled:hasPassword];
}

// NSTextField delegate method to monitor text changes
- (void)controlTextDidChange:(NSNotification *)notification
{
    if ([notification object] == passwordField) {
        [self updateOKButtonState];
    }
}

@end

int main(int argc, const char * argv[])
{
    // Save stdout fd BEFORE GNUstep can write startup messages to it.
    // sudo reads the password from our stdout, so it must be clean.
    savedStdoutFd = dup(STDOUT_FILENO);

    // Redirect both stdout and stderr to /dev/null so GNUstep
    // initialization noise doesn't reach sudo or the terminal.
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull != -1) {
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        close(devnull);
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    // Get the shared application instance and cast it
    NSApplication *app = [NSApplication sharedApplication];

    // Create controller immediately
    SudoAskPassController *controller = [[SudoAskPassController alloc] init];

    // Set delegate
    [app setDelegate:controller];

    // Force activation and run
    [app activateIgnoringOtherApps:YES];
    [app run];

    [controller release];
    [pool drain];

    return 0;
}
