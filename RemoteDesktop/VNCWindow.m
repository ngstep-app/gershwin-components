/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// VNCWindow.m
// Remote Desktop - VNC Viewer Window
//

#import "VNCWindow.h"
#import <unistd.h>

@implementation VNCWindow

@synthesize vncClient = _vncClient;
@synthesize hostname = _hostname;
@synthesize port = _port;
@synthesize username = _username;
@synthesize password = _password;
@synthesize connected = _connected;
@synthesize headlessMode = _headlessMode;
@synthesize vncDelegate = _vncDelegate;

#pragma mark - Initialization

- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port
{
    return [self initWithContentRect:contentRect hostname:hostname port:port username:nil password:nil];
}

- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port password:(NSString *)password
{
    return [self initWithContentRect:contentRect hostname:hostname port:port username:nil password:password];
}

- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password
{
    self = [super initWithContentRect:contentRect
                            styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    
    if (self) {
        _hostname = [hostname copy];
        _port = port;
        _username = [username copy];
        _password = [password copy];
        _connected = NO;
        _framebufferSize = NSZeroSize;
        _currentImage = nil;
        _mouseInside = NO;
        
        [self setTitle:[NSString stringWithFormat:@"VNC: %@:%ld", hostname, (long)port]];
        [self setMinSize:NSMakeSize(320, 240)];
        [self setReleasedWhenClosed:NO];
        [self setDelegate:self];
        
        [self setupVNCClient];
        [self setupUserInterface];
        [self setupEventHandling];
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnectFromVNC];
    [_hostname release];
    [_username release];
    [_password release];
    [_currentImage release];
    [_imageView release];
    [_trackingArea release];
    [super dealloc];
}

#pragma mark - Setup Methods

- (void)setupVNCClient
{
    _vncClient = [[VNCClient alloc] init];
    [_vncClient setDelegate:self];
}

- (void)setupUserInterface
{
    NSRect contentRect = [[self contentView] bounds];
    
    // Create image view for VNC display
    _imageView = [[NSImageView alloc] initWithFrame:contentRect];
    [_imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [_imageView setImageAlignment:NSImageAlignCenter];
    [_imageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_imageView setFocusRingType:NSFocusRingTypeNone];
    
    [[self contentView] addSubview:_imageView];
    
    // Set placeholder image
    NSImage *placeholderImage = [[NSImage alloc] initWithSize:NSMakeSize(640, 480)];
    [placeholderImage lockFocus];
    [[NSColor blackColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 640, 480));
    
    NSString *message = @"Connecting to VNC server...";
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSColor whiteColor], NSForegroundColorAttributeName,
        [NSFont systemFontOfSize:16], NSFontAttributeName,
        nil];
    NSSize textSize = [message sizeWithAttributes:attributes];
    NSPoint textPoint = NSMakePoint((640 - textSize.width) / 2, (480 - textSize.height) / 2);
    [message drawAtPoint:textPoint withAttributes:attributes];
    
    [placeholderImage unlockFocus];
    [_imageView setImage:placeholderImage];
    [placeholderImage release];
}

- (void)setupEventHandling
{
    [self setAcceptsMouseMovedEvents:YES];
    [self makeFirstResponder:self];
    
    _trackingArea = [[NSTrackingArea alloc] 
        initWithRect:[_imageView bounds]
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
               owner:self
            userInfo:nil];
    
    if ([_imageView respondsToSelector:@selector(addTrackingArea:)]) {
        [_imageView performSelector:@selector(addTrackingArea:) withObject:_trackingArea];
    }
}

#pragma mark - Connection Management

- (BOOL)connectToVNC
{
    if (_connected) {
        NSDebugLLog(@"gwcomp", @"VNCWindow: Already connected");
        return YES;
    }
    
    NSDebugLLog(@"gwcomp", @"VNCWindow: Connecting to %@:%ld (username: %@)%@", _hostname, (long)_port, 
          _username ? _username : @"(none)",
          _headlessMode ? @" [headless mode]" : @"");
    
    // Pre-populate credentials if provided via command line
    if (_username) {
        [_vncClient setUsername:_username];
    }
    if (_password) {
        [_vncClient setPassword:_password];
    }
    
    // Set headless mode on the client
    [_vncClient setHeadlessMode:_headlessMode];
    
    BOOL result = [_vncClient connectToHost:_hostname port:_port password:_password];
    if (!result) {
        if (_headlessMode) {
            // In headless mode, just log the error and exit
            NSDebugLLog(@"gwcomp", @"VNCWindow: ERROR - Connection failed in headless mode");
            [NSApp terminate:nil];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"VNC Connection Failed"];
            [alert setInformativeText:@"Failed to connect to VNC server. Please check that the server is running and the address is correct."];
            [alert runModal];
            [alert release];
        }
    }
    
    return result;
}

- (void)disconnectFromVNC
{
    // Prevent multiple calls to disconnect - if EITHER is already cleared, we're disconnecting or disconnected
    if (!_vncClient || !_connected) {
        NSDebugLLog(@"gwcomp", @"VNCWindow: Already disconnected or disconnecting, skipping");
        return;
    }
    
    NSDebugLLog(@"gwcomp", @"VNCWindow: Disconnecting from VNC");
    
    // Set _connected to NO immediately to prevent re-entry
    _connected = NO;
    
    [self orderOut:nil];
    
    if (_vncClient) {
        VNCClient *client = _vncClient;
        _vncClient = nil;  // Clear reference immediately to prevent re-entry
        
        [client setDelegate:nil];
        [client disconnect];
        [client release];
    }
}

#pragma mark - Display Management

- (void)updateDisplay
{
    if (!_vncClient || !_connected) {
        return;
    }
    
    NSImage *newImage = [_vncClient framebufferImage];
    if (newImage) {
        [_currentImage release];
        _currentImage = [newImage retain];
        
        [self performSelectorOnMainThread:@selector(setImageOnMainThread:)
                               withObject:_currentImage
                            waitUntilDone:NO];
        
        NSSize imageSize = [newImage size];
        if (!NSEqualSizes(_framebufferSize, imageSize)) {
            _framebufferSize = imageSize;
            [self performSelectorOnMainThread:@selector(resizeWindowToFitFramebuffer)
                                   withObject:nil
                                waitUntilDone:NO];
        }
    }
}

- (void)setImageOnMainThread:(NSImage *)image
{
    [_imageView setImage:image];
    [_imageView setNeedsDisplay:YES];
}

- (void)resizeWindowToFitFramebuffer
{
    if (NSEqualSizes(_framebufferSize, NSZeroSize)) {
        return;
    }
    
    NSDebugLLog(@"gwcomp", @"VNCWindow: Resizing window to fit framebuffer: %.0fx%.0f", _framebufferSize.width, _framebufferSize.height);
    
    NSSize windowSize = _framebufferSize;
    NSRect contentRect = NSMakeRect(0, 0, windowSize.width, windowSize.height);
    NSRect windowRect = [self frameRectForContentRect:contentRect];
    
    NSRect currentFrame = [self frame];
    windowRect.origin = currentFrame.origin;
    
    NSScreen *screen = [self screen];
    if (screen) {
        NSRect screenFrame = [screen visibleFrame];
        
        if (windowRect.size.width > screenFrame.size.width) {
            CGFloat scale = screenFrame.size.width / windowRect.size.width;
            windowRect.size.width = screenFrame.size.width;
            windowRect.size.height *= scale;
        }
        
        if (windowRect.size.height > screenFrame.size.height) {
            CGFloat scale = screenFrame.size.height / windowRect.size.height;
            windowRect.size.height = screenFrame.size.height;
            windowRect.size.width *= scale;
        }
        
        if (NSMaxX(windowRect) > NSMaxX(screenFrame)) {
            windowRect.origin.x = screenFrame.origin.x + (screenFrame.size.width - windowRect.size.width) / 2;
        }
        if (NSMaxY(windowRect) > NSMaxY(screenFrame)) {
            windowRect.origin.y = screenFrame.origin.y + (screenFrame.size.height - windowRect.size.height) / 2;
        }
    }
    
    [self setFrame:windowRect display:YES animate:YES];
}

#pragma mark - Event Handling

- (void)keyDown:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super keyDown:event];
        return;
    }
    
    NSUInteger keyCode = [event keyCode];
    NSUInteger modifierFlags = [event modifierFlags];
    
    BOOL specialKeyHandled = YES;
    uint32_t vncKeyCode = 0;
    
    switch (keyCode) {
        case 36: vncKeyCode = 0xFF0D; break; // Return
        case 48: vncKeyCode = 0xFF09; break; // Tab
        case 51: vncKeyCode = 0xFF08; break; // Backspace
        case 53: vncKeyCode = 0xFF1B; break; // Escape
        case 123: vncKeyCode = 0xFF51; break; // Left Arrow
        case 124: vncKeyCode = 0xFF53; break; // Right Arrow
        case 125: vncKeyCode = 0xFF54; break; // Down Arrow
        case 126: vncKeyCode = 0xFF52; break; // Up Arrow
        case 122: vncKeyCode = 0xFFBE; break; // F1
        case 120: vncKeyCode = 0xFFBF; break; // F2
        case 99: vncKeyCode = 0xFFC0; break; // F3
        case 118: vncKeyCode = 0xFFC1; break; // F4
        case 96: vncKeyCode = 0xFFC2; break; // F5
        case 97: vncKeyCode = 0xFFC3; break; // F6
        case 98: vncKeyCode = 0xFFC4; break; // F7
        case 100: vncKeyCode = 0xFFC5; break; // F8
        case 101: vncKeyCode = 0xFFC6; break; // F9
        case 109: vncKeyCode = 0xFFC7; break; // F10
        case 103: vncKeyCode = 0xFFC8; break; // F11
        case 111: vncKeyCode = 0xFFC9; break; // F12
        case 49: vncKeyCode = 0x0020; break; // Space
        case 117: vncKeyCode = 0xFFFF; break; // Delete
        case 116: vncKeyCode = 0xFF55; break; // Page Up
        case 121: vncKeyCode = 0xFF56; break; // Page Down
        case 115: vncKeyCode = 0xFF50; break; // Home
        case 119: vncKeyCode = 0xFF57; break; // End
        default: specialKeyHandled = NO; break;
    }
    
    if (specialKeyHandled && vncKeyCode != 0) {
        [_vncClient sendKeyboardEvent:vncKeyCode pressed:YES];
    } else {
        NSString *characters = [event charactersIgnoringModifiers];
        if ([characters length] > 0) {
            for (NSUInteger i = 0; i < [characters length]; i++) {
                unichar character = [characters characterAtIndex:i];
                if ((modifierFlags & NSShiftKeyMask) && character >= 'a' && character <= 'z') {
                    character = character - 'a' + 'A';
                }
                [_vncClient sendKeyboardEvent:character pressed:YES];
            }
        }
    }
}

- (void)keyUp:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super keyUp:event];
        return;
    }
    
    NSUInteger keyCode = [event keyCode];
    NSUInteger modifierFlags = [event modifierFlags];
    
    BOOL specialKeyHandled = YES;
    uint32_t vncKeyCode = 0;
    
    switch (keyCode) {
        case 36: vncKeyCode = 0xFF0D; break;
        case 48: return; // Tab handled in keyDown
        case 51: vncKeyCode = 0xFF08; break;
        case 53: vncKeyCode = 0xFF1B; break;
        case 123: vncKeyCode = 0xFF51; break;
        case 124: vncKeyCode = 0xFF53; break;
        case 125: vncKeyCode = 0xFF54; break;
        case 126: vncKeyCode = 0xFF52; break;
        case 122: vncKeyCode = 0xFFBE; break;
        case 120: vncKeyCode = 0xFFBF; break;
        case 99: vncKeyCode = 0xFFC0; break;
        case 118: vncKeyCode = 0xFFC1; break;
        case 96: vncKeyCode = 0xFFC2; break;
        case 97: vncKeyCode = 0xFFC3; break;
        case 98: vncKeyCode = 0xFFC4; break;
        case 100: vncKeyCode = 0xFFC5; break;
        case 101: vncKeyCode = 0xFFC6; break;
        case 109: vncKeyCode = 0xFFC7; break;
        case 103: vncKeyCode = 0xFFC8; break;
        case 111: vncKeyCode = 0xFFC9; break;
        case 49: vncKeyCode = 0x0020; break;
        case 117: vncKeyCode = 0xFFFF; break;
        case 116: vncKeyCode = 0xFF55; break;
        case 121: vncKeyCode = 0xFF56; break;
        case 115: vncKeyCode = 0xFF50; break;
        case 119: vncKeyCode = 0xFF57; break;
        default: specialKeyHandled = NO; break;
    }
    
    if (specialKeyHandled && vncKeyCode != 0) {
        [_vncClient sendKeyboardEvent:vncKeyCode pressed:NO];
    } else {
        NSString *characters = [event charactersIgnoringModifiers];
        if ([characters length] > 0) {
            for (NSUInteger i = 0; i < [characters length]; i++) {
                unichar character = [characters characterAtIndex:i];
                if ((modifierFlags & NSShiftKeyMask) && character >= 'a' && character <= 'z') {
                    character = character - 'a' + 'A';
                }
                [_vncClient sendKeyboardEvent:character pressed:NO];
            }
        }
    }
}

- (void)flagsChanged:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super flagsChanged:event];
        return;
    }
    
    NSUInteger currentFlags = [event modifierFlags];
    static NSUInteger previousFlags = 0;
    
    if ((currentFlags & NSControlKeyMask) != (previousFlags & NSControlKeyMask)) {
        BOOL pressed = (currentFlags & NSControlKeyMask) != 0;
        [_vncClient sendKeyboardEvent:0xFFE3 pressed:pressed];
    }
    
    if ((currentFlags & NSAlternateKeyMask) != (previousFlags & NSAlternateKeyMask)) {
        BOOL pressed = (currentFlags & NSAlternateKeyMask) != 0;
        [_vncClient sendKeyboardEvent:0xFFE9 pressed:pressed];
    }
    
    if ((currentFlags & NSShiftKeyMask) != (previousFlags & NSShiftKeyMask)) {
        BOOL pressed = (currentFlags & NSShiftKeyMask) != 0;
        [_vncClient sendKeyboardEvent:0xFFE1 pressed:pressed];
    }
    
    if ((currentFlags & NSCommandKeyMask) != (previousFlags & NSCommandKeyMask)) {
        BOOL pressed = (currentFlags & NSCommandKeyMask) != 0;
        [_vncClient sendKeyboardEvent:0xFFEB pressed:pressed];
    }
    
    previousFlags = currentFlags;
}

- (void)mouseDown:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super mouseDown:event];
        return;
    }
    
    NSPoint location = [event locationInWindow];
    NSPoint imagePoint = [_imageView convertPoint:location fromView:nil];
    
    NSSize imageSize = [_imageView bounds].size;
    if (_framebufferSize.width > 0 && _framebufferSize.height > 0) {
        imagePoint.x = (imagePoint.x / imageSize.width) * _framebufferSize.width;
        imagePoint.y = (imagePoint.y / imageSize.height) * _framebufferSize.height;
    }
    
    [_vncClient sendMouseButtonEvent:1 pressed:YES position:imagePoint];
}

- (void)mouseUp:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super mouseUp:event];
        return;
    }
    
    NSPoint location = [event locationInWindow];
    NSPoint imagePoint = [_imageView convertPoint:location fromView:nil];
    
    NSSize imageSize = [_imageView bounds].size;
    if (_framebufferSize.width > 0 && _framebufferSize.height > 0) {
        imagePoint.x = (imagePoint.x / imageSize.width) * _framebufferSize.width;
        imagePoint.y = (imagePoint.y / imageSize.height) * _framebufferSize.height;
    }
    
    [_vncClient sendMouseButtonEvent:1 pressed:NO position:imagePoint];
}

- (void)rightMouseDown:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super rightMouseDown:event];
        return;
    }
    
    NSPoint location = [event locationInWindow];
    NSPoint imagePoint = [_imageView convertPoint:location fromView:nil];
    
    NSSize imageSize = [_imageView bounds].size;
    if (_framebufferSize.width > 0 && _framebufferSize.height > 0) {
        imagePoint.x = (imagePoint.x / imageSize.width) * _framebufferSize.width;
        imagePoint.y = (imagePoint.y / imageSize.height) * _framebufferSize.height;
    }
    
    [_vncClient sendMouseButtonEvent:3 pressed:YES position:imagePoint];
}

- (void)rightMouseUp:(NSEvent *)event
{
    if (!_connected || !_vncClient) {
        [super rightMouseUp:event];
        return;
    }
    
    NSPoint location = [event locationInWindow];
    NSPoint imagePoint = [_imageView convertPoint:location fromView:nil];
    
    NSSize imageSize = [_imageView bounds].size;
    if (_framebufferSize.width > 0 && _framebufferSize.height > 0) {
        imagePoint.x = (imagePoint.x / imageSize.width) * _framebufferSize.width;
        imagePoint.y = (imagePoint.y / imageSize.height) * _framebufferSize.height;
    }
    
    [_vncClient sendMouseButtonEvent:3 pressed:NO position:imagePoint];
}

- (void)mouseMoved:(NSEvent *)event
{
    if (!_connected || !_vncClient || !_mouseInside) {
        return;
    }
    
    NSPoint location = [event locationInWindow];
    NSPoint imagePoint = [_imageView convertPoint:location fromView:nil];
    
    NSSize imageSize = [_imageView bounds].size;
    if (_framebufferSize.width > 0 && _framebufferSize.height > 0) {
        imagePoint.x = (imagePoint.x / imageSize.width) * _framebufferSize.width;
        imagePoint.y = (imagePoint.y / imageSize.height) * _framebufferSize.height;
    }
    
    [_vncClient sendMouseMoveEvent:imagePoint];
}

- (void)mouseEntered:(NSEvent *)event
{
    _mouseInside = YES;
}

- (void)mouseExited:(NSEvent *)event
{
    _mouseInside = NO;
}

#pragma mark - Window Delegate

- (BOOL)windowShouldClose:(id)sender
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: windowShouldClose called");
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: Window closing, notifying delegate");
    if (_vncDelegate && [_vncDelegate respondsToSelector:@selector(vncWindowWillClose:)]) {
        [_vncDelegate vncWindowWillClose:self];
    }
    [self disconnectFromVNC];
}

#pragma mark - VNCClient Delegate

- (void)vncClient:(VNCClient *)client didConnect:(BOOL)success
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: VNC connection result: %@", success ? @"SUCCESS" : @"FAILED");
    
    if (success) {
        _connected = YES;
        // Always show the remote desktop window, even in headless mode
        // (headless only prevents credential prompts, not the actual display)
        [self makeKeyAndOrderFront:nil];
        [self updateDisplay];
        [_vncClient requestFullFramebufferUpdate];
    } else {
        if (_headlessMode) {
            NSDebugLLog(@"gwcomp", @"VNCWindow: ERROR - Connection failed in headless mode");
            [NSApp terminate:nil];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"VNC Connection Failed"];
            [alert setInformativeText:@"Could not connect to the VNC server. Please ensure the server is running and accessible."];
            [alert runModal];
            [alert release];
        }
    }
}

- (void)vncClient:(VNCClient *)client didDisconnect:(NSString *)reason
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: VNC disconnected: %@", reason);
    _connected = NO;
    
    NSImage *disconnectedImage = [[NSImage alloc] initWithSize:NSMakeSize(640, 480)];
    [disconnectedImage lockFocus];
    [[NSColor darkGrayColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 640, 480));
    
    NSString *message = @"VNC Connection Lost";
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSColor whiteColor], NSForegroundColorAttributeName,
        [NSFont systemFontOfSize:16], NSFontAttributeName,
        nil];
    NSSize textSize = [message sizeWithAttributes:attributes];
    NSPoint textPoint = NSMakePoint((640 - textSize.width) / 2, (480 - textSize.height) / 2);
    [message drawAtPoint:textPoint withAttributes:attributes];
    
    [disconnectedImage unlockFocus];
    [_imageView setImage:disconnectedImage];
    [disconnectedImage release];
}

- (void)vncClient:(VNCClient *)client didReceiveError:(NSString *)error
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: VNC error: %@", error);
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"VNC Error"];
    [alert setInformativeText:error];
    [alert runModal];
    [alert release];
}

- (void)vncClient:(VNCClient *)client framebufferDidUpdate:(NSRect)rect
{
    [self performSelectorOnMainThread:@selector(updateDisplay)
                           withObject:nil
                        waitUntilDone:NO];
}

- (NSString *)vncClientNeedsPassword:(VNCClient *)client
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: Prompting for password");
    
    // Match Workspace credentials dialog geometry exactly
    // Panel: 400x200, centered
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                                styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [panel setTitle:@"VNC Password Required"];
    [panel center];
    
    NSView *contentView = [panel contentView];
    
    // Main label: NSMakeRect(20, 140, 360, 40)
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 140, 360, 40)];
    [label setStringValue:[NSString stringWithFormat:@"Enter password for %@:", [client hostname]]];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [contentView addSubview:label];
    [label release];
    
    // Password label: NSMakeRect(20, 75, 100, 17)
    NSTextField *passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 75, 100, 17)];
    [passwordLabel setStringValue:@"Password:"];
    [passwordLabel setBezeled:NO];
    [passwordLabel setDrawsBackground:NO];
    [passwordLabel setEditable:NO];
    [passwordLabel setSelectable:NO];
    [passwordLabel setAlignment:NSRightTextAlignment];
    [contentView addSubview:passwordLabel];
    [passwordLabel release];
    
    // Password field: NSMakeRect(130, 73, 250, 24)
    NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(130, 73, 250, 24)];
    [[panel contentView] addSubview:passwordField];
    
    // Connect button: NSMakeRect(290, 20, 90, 24)
    NSButton *connectButton = [[NSButton alloc] initWithFrame:NSMakeRect(290, 20, 90, 24)];
    [connectButton setTitle:@"Connect"];
    [connectButton setTarget:NSApp];
    [connectButton setAction:@selector(stopModal)];
    [connectButton setKeyEquivalent:@"\r"];
    [contentView addSubview:connectButton];
    [connectButton release];
    
    // Cancel button: NSMakeRect(190, 20, 90, 24)
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, 20, 90, 24)];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setTarget:NSApp];
    [cancelButton setAction:@selector(abortModal)];
    [cancelButton setKeyEquivalent:@"\e"];
    [contentView addSubview:cancelButton];
    [cancelButton release];
    
    // Set up key view loop for Tab to work
    [passwordField setNextKeyView:connectButton];
    [connectButton setNextKeyView:cancelButton];
    [cancelButton setNextKeyView:passwordField];
    
    [panel setInitialFirstResponder:passwordField];
    [panel makeFirstResponder:passwordField];
    
    NSString *result = nil;
    NSDebugLLog(@"gwcomp", @"VNCWindow: Showing modal password dialog...");
    NSInteger response = [NSApp runModalForWindow:panel];
    NSDebugLLog(@"gwcomp", @"VNCWindow: Modal password dialog returned with response: %ld", (long)response);
    
    if (response == NSRunStoppedResponse) {
        result = [[passwordField stringValue] retain];
        NSDebugLLog(@"gwcomp", @"VNCWindow: Password provided (length: %lu)", (unsigned long)[result length]);
    } else {
        NSDebugLLog(@"gwcomp", @"VNCWindow: Password dialog cancelled");
    }
    
    [passwordField release];
    
    // Cancel any pending Eau theme timer callbacks on button cells before closing
    NSArray *subviews = [[panel contentView] subviews];
    for (NSView *view in subviews) {
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            [NSObject cancelPreviousPerformRequestsWithTarget:[button cell]];
        }
    }
    
    NSDebugLLog(@"gwcomp", @"VNCWindow: Closing password panel...");
    [panel orderOut:nil];
    [panel release];
    NSDebugLLog(@"gwcomp", @"VNCWindow: Password panel released");
    
    // Small delay to ensure modal state is fully cleaned up
    usleep(100000); // 100ms
    
    return [result autorelease];
}

- (NSDictionary *)vncClientNeedsCredentials:(VNCClient *)client
{
    NSDebugLLog(@"gwcomp", @"VNCWindow: Prompting for credentials");
    
    // Match Workspace credentials dialog geometry exactly
    // Panel: 400x200, centered
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                                styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [panel setTitle:@"VNC Credentials Required"];
    [panel center];
    
    NSView *contentView = [panel contentView];
    
    // Main label: NSMakeRect(20, 140, 360, 40)
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 140, 360, 40)];
    [label setStringValue:[NSString stringWithFormat:@"Enter credentials for %@:", [client hostname]]];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [contentView addSubview:label];
    [label release];
    
    // Username label: NSMakeRect(20, 110, 100, 17)
    NSTextField *usernameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 110, 100, 17)];
    [usernameLabel setStringValue:@"Username:"];
    [usernameLabel setBezeled:NO];
    [usernameLabel setDrawsBackground:NO];
    [usernameLabel setEditable:NO];
    [usernameLabel setSelectable:NO];
    [usernameLabel setAlignment:NSRightTextAlignment];
    [contentView addSubview:usernameLabel];
    [usernameLabel release];
    
    // Username field: NSMakeRect(130, 108, 250, 24)
    NSTextField *usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 108, 250, 24)];
    [usernameField setStringValue:NSUserName()];
    [[panel contentView] addSubview:usernameField];
    
    // Password label: NSMakeRect(20, 75, 100, 17)
    NSTextField *passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 75, 100, 17)];
    [passwordLabel setStringValue:@"Password:"];
    [passwordLabel setBezeled:NO];
    [passwordLabel setDrawsBackground:NO];
    [passwordLabel setEditable:NO];
    [passwordLabel setSelectable:NO];
    [passwordLabel setAlignment:NSRightTextAlignment];
    [[panel contentView] addSubview:passwordLabel];
    [passwordLabel release];
    
    // Password field: NSMakeRect(130, 73, 250, 24)
    NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(130, 73, 250, 24)];
    [[panel contentView] addSubview:passwordField];
    
    // Connect button: NSMakeRect(290, 20, 90, 24)
    NSButton *connectButton = [[NSButton alloc] initWithFrame:NSMakeRect(290, 20, 90, 24)];
    [connectButton setTitle:@"Connect"];
    [connectButton setTarget:NSApp];
    [connectButton setAction:@selector(stopModal)];
    [connectButton setKeyEquivalent:@"\r"];
    [contentView addSubview:connectButton];
    [connectButton release];
    
    // Cancel button: NSMakeRect(190, 20, 90, 24)
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, 20, 90, 24)];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setTarget:NSApp];
    [cancelButton setAction:@selector(abortModal)];
    [cancelButton setKeyEquivalent:@"\e"];
    [contentView addSubview:cancelButton];
    [cancelButton release];
    
    // Set up key view loop for Tab to work
    [usernameField setNextKeyView:passwordField];
    [passwordField setNextKeyView:connectButton];
    [connectButton setNextKeyView:cancelButton];
    [cancelButton setNextKeyView:usernameField];
    
    [panel setInitialFirstResponder:usernameField];
    [panel makeFirstResponder:usernameField];
    
    NSDictionary *result = nil;
    NSDebugLLog(@"gwcomp", @"VNCWindow: Showing modal credentials dialog...");
    NSInteger response = [NSApp runModalForWindow:panel];
    NSDebugLLog(@"gwcomp", @"VNCWindow: Modal credentials dialog returned with response: %ld", (long)response);
    
    if (response == NSRunStoppedResponse) {
        NSString *enteredUsername = [usernameField stringValue];
        NSString *enteredPassword = [passwordField stringValue];
        
        NSDebugLLog(@"gwcomp", @"VNCWindow: User entered credentials - username: '%@' (length: %lu), password: %@ (length: %lu)",
              enteredUsername ? enteredUsername : @"(nil)", 
              (unsigned long)[enteredUsername length],
              enteredPassword && [enteredPassword length] > 0 ? @"<provided>" : @"<empty>",
              (unsigned long)[enteredPassword length]);
        
        result = [NSDictionary dictionaryWithObjectsAndKeys:
                  enteredUsername, @"username",
                  enteredPassword, @"password",
                  nil];
    } else {
        NSDebugLLog(@"gwcomp", @"VNCWindow: User cancelled credential dialog");
    }
    
    [usernameField release];
    [passwordField release];
    
    // Cancel any pending Eau theme timer callbacks on button cells before closing
    NSArray *subviews = [[panel contentView] subviews];
    for (NSView *view in subviews) {
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            [NSObject cancelPreviousPerformRequestsWithTarget:[button cell]];
        }
    }
    
    NSDebugLLog(@"gwcomp", @"VNCWindow: Closing credentials panel...");
    [panel orderOut:nil];
    [panel release];
    NSDebugLLog(@"gwcomp", @"VNCWindow: Credentials panel released");
    
    // Small delay to ensure modal state is fully cleaned up
    usleep(100000); // 100ms
    
    return result;
}

@end
