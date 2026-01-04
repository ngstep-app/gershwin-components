/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// RDPWindow.m
// Remote Desktop - RDP Viewer Window
//

#import "RDPWindow.h"

@implementation RDPWindow

@synthesize rdpClient = _rdpClient;
@synthesize hostname = _hostname;
@synthesize port = _port;
@synthesize username = _username;
@synthesize password = _password;
@synthesize domain = _domain;
@synthesize connected = _connected;
@synthesize rdpDelegate = _rdpDelegate;

#pragma mark - Initialization

- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port
{
    return [self initWithContentRect:contentRect hostname:hostname port:port username:nil password:nil domain:nil];
}

- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port
                 username:(NSString *)username password:(NSString *)password
{
    return [self initWithContentRect:contentRect hostname:hostname port:port username:username password:password domain:nil];
}

- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port
                 username:(NSString *)username password:(NSString *)password domain:(NSString *)domain
{
    self = [super initWithContentRect:contentRect
                            styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    
    if (self) {
        _hostname = [hostname copy];
        _port = port;
        _username = [username copy];
        _password = [password copy];
        _domain = [domain copy];
        _connected = NO;
        _framebufferSize = NSZeroSize;
        _currentImage = nil;
        _mouseInside = NO;
        
        [self setTitle:[NSString stringWithFormat:@"RDP: %@:%ld", hostname, (long)port]];
        [self setMinSize:NSMakeSize(320, 240)];
        [self setDelegate:self];
        
        [self setupRDPClient];
        [self setupUserInterface];
        [self setupEventHandling];
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnectFromRDP];
    [_hostname release];
    [_username release];
    [_password release];
    [_domain release];
    [_currentImage release];
    [super dealloc];
}

#pragma mark - Setup Methods

- (void)setupRDPClient
{
    _rdpClient = [[RDPClient alloc] init];
    [_rdpClient setDelegate:self];
}

- (void)setupUserInterface
{
    NSRect contentRect = [[self contentView] bounds];
    
    // Create image view for RDP display
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
    
    NSString *message = @"Connecting to RDP server...";
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

- (BOOL)connectToRDP
{
    if (_connected) {
        NSLog(@"RDPWindow: Already connected");
        return YES;
    }
    
    NSLog(@"RDPWindow: Connecting to %@:%ld", _hostname, (long)_port);
    
    BOOL result = [_rdpClient connectToHost:_hostname port:_port username:_username password:_password domain:_domain];
    if (!result) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"RDP Connection Failed"];
        [alert setInformativeText:@"Failed to connect to RDP server. Please check that the server is running and the address is correct."];
        [alert runModal];
        [alert release];
    }
    
    return result;
}

- (void)disconnectFromRDP
{
    NSLog(@"RDPWindow: Disconnecting from RDP");
    
    [self orderOut:nil];
    
    if (_rdpClient) {
        [_rdpClient setDelegate:nil];
        [_rdpClient disconnect];
        [_rdpClient release];
        _rdpClient = nil;
    }
    
    _connected = NO;
}

#pragma mark - Display Management

- (void)updateDisplay
{
    if (!_rdpClient || !_connected) {
        return;
    }
    
    NSImage *newImage = [_rdpClient framebufferImage];
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
    
    NSLog(@"RDPWindow: Resizing window to fit framebuffer: %.0fx%.0f", _framebufferSize.width, _framebufferSize.height);
    
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
    if (!_connected || !_rdpClient) {
        [super keyDown:event];
        return;
    }
    
    NSUInteger keyCode = [event keyCode];
    [_rdpClient sendKeyboardEvent:keyCode pressed:YES];
}

- (void)keyUp:(NSEvent *)event
{
    if (!_connected || !_rdpClient) {
        [super keyUp:event];
        return;
    }
    
    NSUInteger keyCode = [event keyCode];
    [_rdpClient sendKeyboardEvent:keyCode pressed:NO];
}

- (void)flagsChanged:(NSEvent *)event
{
    if (!_connected || !_rdpClient) {
        [super flagsChanged:event];
        return;
    }
    
    // Handle modifier key changes
    NSUInteger currentFlags = [event modifierFlags];
    static NSUInteger previousFlags = 0;
    
    // Control key
    if ((currentFlags & NSControlKeyMask) != (previousFlags & NSControlKeyMask)) {
        BOOL pressed = (currentFlags & NSControlKeyMask) != 0;
        [_rdpClient sendKeyboardEvent:0x1D pressed:pressed]; // Left Control scancode
    }
    
    // Alt key
    if ((currentFlags & NSAlternateKeyMask) != (previousFlags & NSAlternateKeyMask)) {
        BOOL pressed = (currentFlags & NSAlternateKeyMask) != 0;
        [_rdpClient sendKeyboardEvent:0x38 pressed:pressed]; // Left Alt scancode
    }
    
    // Shift key
    if ((currentFlags & NSShiftKeyMask) != (previousFlags & NSShiftKeyMask)) {
        BOOL pressed = (currentFlags & NSShiftKeyMask) != 0;
        [_rdpClient sendKeyboardEvent:0x2A pressed:pressed]; // Left Shift scancode
    }
    
    previousFlags = currentFlags;
}

- (void)mouseDown:(NSEvent *)event
{
    if (!_connected || !_rdpClient) {
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
    
    [_rdpClient sendMouseButtonEvent:1 pressed:YES position:imagePoint];
}

- (void)mouseUp:(NSEvent *)event
{
    if (!_connected || !_rdpClient) {
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
    
    [_rdpClient sendMouseButtonEvent:1 pressed:NO position:imagePoint];
}

- (void)rightMouseDown:(NSEvent *)event
{
    if (!_connected || !_rdpClient) {
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
    
    [_rdpClient sendMouseButtonEvent:3 pressed:YES position:imagePoint];
}

- (void)rightMouseUp:(NSEvent *)event
{
    if (!_connected || !_rdpClient) {
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
    
    [_rdpClient sendMouseButtonEvent:3 pressed:NO position:imagePoint];
}

- (void)mouseMoved:(NSEvent *)event
{
    if (!_connected || !_rdpClient || !_mouseInside) {
        return;
    }
    
    NSPoint location = [event locationInWindow];
    NSPoint imagePoint = [_imageView convertPoint:location fromView:nil];
    
    NSSize imageSize = [_imageView bounds].size;
    if (_framebufferSize.width > 0 && _framebufferSize.height > 0) {
        imagePoint.x = (imagePoint.x / imageSize.width) * _framebufferSize.width;
        imagePoint.y = (imagePoint.y / imageSize.height) * _framebufferSize.height;
    }
    
    [_rdpClient sendMouseMoveEvent:imagePoint];
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
    [self disconnectFromRDP];
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
    NSLog(@"RDPWindow: Window closing, notifying delegate");
    if (_rdpDelegate && [_rdpDelegate respondsToSelector:@selector(rdpWindowWillClose:)]) {
        [_rdpDelegate rdpWindowWillClose:self];
    }
    [self disconnectFromRDP];
}

#pragma mark - RDPClient Delegate

- (void)rdpClient:(RDPClient *)client didConnect:(BOOL)success
{
    NSLog(@"RDPWindow: RDP connection result: %@", success ? @"SUCCESS" : @"FAILED");
    
    if (success) {
        _connected = YES;
        [self updateDisplay];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"RDP Connection Failed"];
        [alert setInformativeText:@"Could not connect to the RDP server. Please ensure the server is running and accessible."];
        [alert runModal];
        [alert release];
    }
}

- (void)rdpClient:(RDPClient *)client didDisconnect:(NSString *)reason
{
    NSLog(@"RDPWindow: RDP disconnected: %@", reason);
    _connected = NO;
    
    NSImage *disconnectedImage = [[NSImage alloc] initWithSize:NSMakeSize(640, 480)];
    [disconnectedImage lockFocus];
    [[NSColor darkGrayColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 640, 480));
    
    NSString *message = @"RDP Connection Lost";
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

- (void)rdpClient:(RDPClient *)client didReceiveError:(NSString *)error
{
    NSLog(@"RDPWindow: RDP error: %@", error);
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"RDP Error"];
    [alert setInformativeText:error];
    [alert runModal];
    [alert release];
}

- (void)rdpClient:(RDPClient *)client framebufferDidUpdate:(NSRect)rect
{
    [self performSelectorOnMainThread:@selector(updateDisplay)
                           withObject:nil
                        waitUntilDone:NO];
}

@end
