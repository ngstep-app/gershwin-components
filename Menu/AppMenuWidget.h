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
@property (nonatomic, assign) BOOL isWaitingForMenu;
@property (nonatomic, assign) BOOL cachedIsWaitingForMenu;
@property (nonatomic, assign) BOOL cachedHasMenu;
@property (nonatomic, assign) BOOL needsRedraw;

// Delayed fallback timers keyed by window id -> NSTimer
@property (nonatomic, strong) NSMutableDictionary *fallbackTimers;

// The system submenu (contains Search, System Preferences, and dynamic application list)
@property (nonatomic, strong) NSMenu *systemMenu;
// Guard flag to prevent reentrant / repeated updates while we're populating the system menu
@property (nonatomic, assign) BOOL isUpdatingSystemMenu;
// Timestamp (CFAbsoluteTime) of the last system menu population — used to throttle frequent updates
@property (nonatomic, assign) NSTimeInterval lastSystemMenuUpdateTime;

// Tight-loop prevention guards
@property (nonatomic, assign) BOOL isInsideDisplayMenuForWindow;   // re-entrance guard
@property (nonatomic, assign) BOOL isInsideDesktopFallback;        // re-entrance guard for desktop fallback
@property (nonatomic, assign) NSTimeInterval lastUpdateForActiveWindowTime; // rate limit updateForActiveWindowId
@property (nonatomic, assign) unsigned long lastUpdateForActiveWindowId;    // dedup repeated calls
@property (nonatomic, assign) NSUInteger noMenuGracePeriodFireCount;        // prevent infinite grace period retries
@property (nonatomic, assign) unsigned long lastLoadedMenuWindowId;          // tracks which window we last loaded a menu for

- (void)updateForActiveWindow;
- (void)updateForActiveWindowId:(unsigned long)windowId;
- (void)clearMenu;
- (void)clearMenuAndHideView;
- (void)displayMenuForWindow:(unsigned long)windowId;
- (void)setupMenuViewWithMenu:(NSMenu *)menu;
- (void)loadMenu:(NSMenu *)menu forWindow:(unsigned long)windowId;
- (void)checkAndDisplayMenuForNewlyRegisteredWindow:(unsigned long)windowId;
- (BOOL)isPlaceholderMenu:(NSMenu *)menu;
- (NSMenu *)createFileMenuWithClose:(unsigned long)windowId;
- (void)closeWindow:(NSMenuItem *)sender;
- (void)closeActiveWindow:(NSMenuItem *)sender;
- (void)sendAltF4ToWindow:(unsigned long)windowId;

// Open system utilities and apps from System submenu
- (void)openSystemPreferences:(NSMenuItem *)sender;
- (void)openApplicationBundle:(NSMenuItem *)sender;

// Debug methods
- (void)debugLogCurrentMenuState;
- (void)menuItemClicked:(NSMenuItem *)sender;

// Window validation methods
+ (BOOL)isWindowStillValid:(Window)windowId;
+ (BOOL)safelyCheckWindow:(Window)windowId withDisplay:(Display *)display;

// Error handling and cleanup
+ (void)setCurrentWidget:(AppMenuWidget *)widget;
- (void)handleWindowDisappeared:(Window)windowId;

@end
