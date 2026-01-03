/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// VNCWindow.h
// Remote Desktop - VNC Viewer Window
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "VNCClient.h"

@class VNCWindow;

@protocol VNCWindowDelegate <NSObject>
@optional
- (void)vncWindowWillClose:(VNCWindow *)window;
@end

@interface VNCWindow : NSWindow <VNCClientDelegate>
{
    VNCClient *_vncClient;
    NSImageView *_imageView;
    NSScrollView *_scrollView;
    NSString *_hostname;
    NSInteger _port;
    NSString *_username;
    NSString *_password;
    
    // Display state
    BOOL _connected;
    NSSize _framebufferSize;
    NSImage *_currentImage;
    
    // Input handling
    NSTrackingArea *_trackingArea;
    BOOL _mouseInside;
    
    // CLI mode
    BOOL _headlessMode;
    
    id<VNCWindowDelegate> _vncDelegate;
}

@property (nonatomic, retain) VNCClient *vncClient;
@property (nonatomic, retain) NSString *hostname;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL headlessMode;
@property (nonatomic, assign) id<VNCWindowDelegate> vncDelegate;

// Initialization
- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port;
- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port password:(NSString *)password;
- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password;

// Connection management
- (BOOL)connectToVNC;
- (void)disconnectFromVNC;

// Display management
- (void)updateDisplay;
- (void)resizeWindowToFitFramebuffer;

@end
