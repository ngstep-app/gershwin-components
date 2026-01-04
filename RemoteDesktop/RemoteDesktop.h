/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// RemoteDesktop.h
// Remote Desktop - Network service discovery and remote connection
//

#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSBox.h>
#import <AppKit/NSMenu.h>
#import <Foundation/NSNetServices.h>

#import "VNCWindow.h"
#import "RDPWindow.h"

// Service type enum
typedef enum {
    RemoteServiceTypeVNC,
    RemoteServiceTypeRDP,
    RemoteServiceTypeUnknown
} RemoteServiceType;

// Model class for discovered services
@interface RemoteService : NSObject
{
    NSString *_name;
    NSString *_hostname;
    NSInteger _port;
    RemoteServiceType _type;
    NSNetService *_netService;
}

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *hostname;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, assign) RemoteServiceType type;
@property (nonatomic, retain) NSNetService *netService;

- (NSString *)typeString;

@end

// Main application controller
@interface RemoteDesktop : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, 
                                      NSTableViewDataSource, NSTableViewDelegate,
                                      VNCWindowDelegate, RDPWindowDelegate>
{
    NSWindow *window;
    NSTableView *servicesTable;
    NSButton *connectButton;
    
    // Manual connection UI
    NSTextField *hostField;
    NSTextField *portField;
    NSPopUpButton *protocolPopup;
    
    // Network service discovery
    NSNetServiceBrowser *vncBrowser;
    NSNetServiceBrowser *rdpBrowser;
    NSMutableArray *discoveredServices;
    
    // Active connections
    NSMutableArray *vncWindows;
    NSMutableArray *rdpWindows;
    
    // CLI mode flag
    BOOL _cliMode;
}

// Application lifecycle
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApp;
- (void)windowWillClose:(NSNotification *)aNotification;

// UI actions
- (void)connectButtonClicked:(id)sender;
- (void)manualConnectButtonClicked:(id)sender;

// Service discovery
- (void)startServiceDiscovery;
- (void)stopServiceDiscovery;

// Connection management
- (void)connectToService:(RemoteService *)service;
- (void)connectToVNCHost:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password;
- (void)connectToRDPHost:(NSString *)hostname port:(NSInteger)port 
                username:(NSString *)username password:(NSString *)password;

// Command line connection
- (void)connectFromCommandLine:(NSString *)hostname protocol:(NSString *)protocol username:(NSString *)username password:(NSString *)password;
- (void)setCliMode:(BOOL)cliMode;

@end
