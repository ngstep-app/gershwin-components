/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <X11/Xlib.h>
#import <X11/keysym.h>

@class MenuProtocolManager;

@interface AppMenuWidget : NSView <NSMenuDelegate>

@property (nonatomic, weak) MenuProtocolManager *protocolManager;
@property (nonatomic, strong) NSMenuView *menuView;
@property (nonatomic, strong) NSString *currentApplicationName;
@property (nonatomic, assign) unsigned long currentWindowId;
@property (nonatomic, strong) NSMenu *currentMenu;
@property (nonatomic, strong) NSTimer *updateTimer;

// Anti-flicker support - keep old menu visible until new one is ready
@property (nonatomic, strong) NSMenuView *oldMenuView;
@property (nonatomic, strong) NSTimer *antiFlickerTimer;

- (void)updateForActiveWindow;
- (void)clearMenu;
- (void)displayMenuForWindow:(unsigned long)windowId;
- (void)setupMenuViewWithMenu:(NSMenu *)menu;
- (void)loadMenu:(NSMenu *)menu forWindow:(unsigned long)windowId;
- (void)checkAndDisplayMenuForNewlyRegisteredWindow:(unsigned long)windowId;
- (BOOL)isPlaceholderMenu:(NSMenu *)menu;
- (NSMenu *)createFileMenuWithClose:(unsigned long)windowId;
- (void)closeWindow:(NSMenuItem *)sender;
- (void)closeActiveWindow:(NSMenuItem *)sender;
- (void)sendAltF4ToWindow:(unsigned long)windowId;

// Debug methods
- (void)debugLogCurrentMenuState;
- (void)menuItemClicked:(NSMenuItem *)sender;

// Anti-flicker support
- (void)startAntiFlickerProtection;
- (void)finishAntiFlickerTransition;
- (void)antiFlickerTimeoutExpired:(NSTimer *)timer;

@end
