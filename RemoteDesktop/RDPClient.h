/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// RDPClient.h
// Remote Desktop - RDP Client using FreeRDP
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class RDPClient;

@protocol RDPClientDelegate <NSObject>
@optional
- (void)rdpClient:(RDPClient *)client didConnect:(BOOL)success;
- (void)rdpClient:(RDPClient *)client didDisconnect:(NSString *)reason;
- (void)rdpClient:(RDPClient *)client didReceiveError:(NSString *)error;
- (void)rdpClient:(RDPClient *)client framebufferDidUpdate:(NSRect)rect;
@end

@interface RDPClient : NSObject
{
    void *_rdpContext;  // rdpContext pointer from FreeRDP
    NSString *_hostname;
    NSInteger _port;
    NSString *_username;
    NSString *_password;
    NSString *_domain;
    BOOL _connected;
    BOOL _connecting;
    
    // Framebuffer data
    NSInteger _width;
    NSInteger _height;
    NSInteger _depth;
    unsigned char *_framebuffer;
    NSSize _framebufferSize;
    
    // Threading
    NSThread *_connectionThread;
    BOOL _shouldStop;
    
    // Delegate
    id<RDPClientDelegate> _delegate;
}

@property (nonatomic, retain) NSString *hostname;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;
@property (nonatomic, retain) NSString *domain;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL connecting;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, assign) id<RDPClientDelegate> delegate;

// Connection management
- (BOOL)connectToHost:(NSString *)hostname port:(NSInteger)port;
- (BOOL)connectToHost:(NSString *)hostname port:(NSInteger)port 
             username:(NSString *)username password:(NSString *)password;
- (BOOL)connectToHost:(NSString *)hostname port:(NSInteger)port 
             username:(NSString *)username password:(NSString *)password 
               domain:(NSString *)domain;
- (void)disconnect;

// Input handling
- (void)sendKeyboardEvent:(NSUInteger)key pressed:(BOOL)pressed;
- (void)sendMouseEvent:(NSPoint)position buttons:(NSUInteger)buttonMask;
- (void)sendMouseMoveEvent:(NSPoint)position;
- (void)sendMouseButtonEvent:(NSUInteger)button pressed:(BOOL)pressed position:(NSPoint)position;

// Framebuffer access
- (NSData *)framebufferData;
- (NSImage *)framebufferImage;

// Utility
+ (BOOL)isFreeRDPAvailable;

@end
