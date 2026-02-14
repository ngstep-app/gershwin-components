/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class StatusItemManager;

/**
 * Protocol that all status item providers must implement.
 * Status items are loadable bundles that display information
 * in the menu bar (e.g., CPU usage, RAM usage, time, etc.)
 */
@protocol StatusItemProvider <NSObject>

@required

/**
 * Unique identifier for this status item.
 * Should be reverse-DNS style, e.g., "org.gershwin.menu.statusitem.cpu"
 */
- (NSString *)identifier;

/**
 * Current display title for the status item.
 * This can be dynamic and change with each update.
 */
- (NSString *)title;

/**
 * Fixed display width in pixels for this status item's cell in the menu bar.
 * The cell will always be exactly this width; content is centered within it.
 * Return a value large enough for the widest possible content string so that
 * the layout never shifts when text changes.
 */
- (CGFloat)width;

/**
 * Called when the status item is first loaded.
 * Use this to initialize resources and state.
 *
 * @param manager The StatusItemManager that loaded this item
 */
- (void)loadWithManager:(StatusItemManager *)manager;

/**
 * Called periodically to update the status item.
 * Update internal state and refresh title/icon if needed.
 * Called at the interval specified by updateInterval.
 */
- (void)update;

/**
 * Called when the user clicks on this status item.
 * Either implement this OR provide a menu via the menu method.
 */
- (void)handleClick;

@optional

/**
 * Menu to display when the status item is clicked.
 * If this returns a menu, it will be displayed instead of calling handleClick.
 */
- (NSMenu *)menu;

/**
 * Icon to display for this status item.
 * If nil, the title string will be used instead.
 */
- (NSImage *)icon;

/**
 * How often (in seconds) this status item should be updated.
 * Default is 1.0 second if not implemented.
 */
- (NSTimeInterval)updateInterval;

/**
 * Called when the status item is being unloaded (app shutdown).
 * Clean up resources, timers, file handles, etc.
 */
- (void)unload;

/**
 * Priority for positioning (higher numbers appear more to the right).
 * Default is 100 if not implemented.
 * Time is typically 1000, system monitors 500-600.
 */
- (NSInteger)displayPriority;

@end
