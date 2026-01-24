/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "GNUstepGUI/GSTheme.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>

@class MenuBarView;
@class AppMenuWidget;
@class MenuProtocolManager;
@class RoundedCornersView;
@class ActionSearchMenuView;
@class StatusItemManager;
@class WindowMonitor;

@interface MenuController : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) NSWindow *menuBar;
@property (nonatomic, assign) NSRect screenFrame;
@property (nonatomic, assign) NSSize screenSize;
@property (nonatomic, strong) MenuBarView *menuBarView;
@property (nonatomic, strong) AppMenuWidget *appMenuWidget;
@property (nonatomic, strong) MenuProtocolManager *protocolManager;
@property (nonatomic, strong) RoundedCornersView *roundedCornersView;
@property (nonatomic, strong) ActionSearchMenuView *actionSearchView;
@property (nonatomic, strong) StatusItemManager *statusItemManager;
@property (nonatomic, strong) NSMenuView *timeMenuView;
@property (nonatomic, strong) NSMenu *timeMenu;
@property (nonatomic, strong) NSMenuItem *timeMenuItem;
@property (nonatomic, strong) NSMenuItem *dateMenuItem;
@property (nonatomic, strong) NSTimer *timeUpdateTimer;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) WindowMonitor *windowMonitor;
@property (nonatomic, assign) unsigned long lastProcessedWindowId;
@property (nonatomic, assign) NSTimeInterval lastProcessedTime;
@property (nonatomic, assign) int dbusFileDescriptor;
@property (nonatomic, strong) NSFileHandle *dbusFileHandle;
@property (nonatomic, strong) NSTimer *dbusPollingTimer;
@property (nonatomic, assign) Display *strutDisplay;
@property (nonatomic, assign) Window strutWindow;
@property (nonatomic, strong) NSTimer *slideInAnimationTimer;
@property (nonatomic, assign) NSTimeInterval slideInStartTime;
@property (nonatomic, assign) CGFloat slideInStartY;
@property (nonatomic, assign) NSTimeInterval lastActiveWindowScanTime;
@property (nonatomic, strong) NSTimer *windowValidationTimer; // Watchdog timer to hide stale menus

// Track the last-cleared window id and timestamp so we can throttle repeated clears
@property (nonatomic, assign) unsigned long lastClearedWindowId;
@property (nonatomic, assign) NSTimeInterval lastClearedTime;

// Throttle window clear operations globally - when set prevents repeated clears for a short interval
@property (nonatomic, assign) NSTimeInterval lastClearSuppressUntil;

- (id)init;
- (NSColor *)backgroundColor;
- (NSColor *)transparentColor;
- (void)createPersistentStrutWindow;
- (void)createMenuBar;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (void)setupMenuBar;
- (void)updateActiveWindow;
- (void)createProtocolManager;
- (void)initializeProtocols;
- (void)setupWindowMonitoring;
- (void)announceGlobalMenuSupport;
- (void)scanForNewMenus;
- (AppMenuWidget *)appMenuWidget;

- (void)createTimeMenu;
- (void)updateTimeMenu;

@end
