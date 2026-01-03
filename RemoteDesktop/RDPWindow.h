/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// RDPWindow.h
// Remote Desktop - RDP Viewer Window
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "RDPClient.h"

@class RDPWindow;

@protocol RDPWindowDelegate <NSObject>
@optional
- (void)rdpWindowWillClose:(RDPWindow *)window;
@end

@interface RDPWindow : NSWindow <RDPClientDelegate>
{
    RDPClient *_rdpClient;
    NSImageView *_imageView;
    NSString *_hostname;
    NSInteger _port;
    NSString *_username;
    NSString *_password;
    NSString *_domain;
    
    // Display state
    BOOL _connected;
    NSSize _framebufferSize;
    NSImage *_currentImage;
    
    // Input handling
    NSTrackingArea *_trackingArea;
    BOOL _mouseInside;
    
    id<RDPWindowDelegate> _rdpDelegate;
}

@property (nonatomic, retain) RDPClient *rdpClient;
@property (nonatomic, retain) NSString *hostname;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;
@property (nonatomic, retain) NSString *domain;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) id<RDPWindowDelegate> rdpDelegate;

// Initialization
- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port;
- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port
                 username:(NSString *)username password:(NSString *)password;
- (id)initWithContentRect:(NSRect)contentRect hostname:(NSString *)hostname port:(NSInteger)port
                 username:(NSString *)username password:(NSString *)password domain:(NSString *)domain;

// Connection management
- (BOOL)connectToRDP;
- (void)disconnectFromRDP;

// Display management
- (void)updateDisplay;
- (void)resizeWindowToFitFramebuffer;

@end
