/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "StatusItemProvider.h"

@class StatusItemView;
@class StatusItemsView;

/**
 * Manages all status items displayed in the menu bar.
 *
 * Responsible for:
 *   - Loading provider bundles from standard search paths
 *   - Sorting providers by displayPriority (highest = rightmost)
 *   - Creating fixed-width StatusItemView instances for each provider
 *   - Scheduling update timers grouped by interval
 *   - Forwarding title changes to views without altering layout
 *
 * The resulting StatusItemsView is a transparent container that can be
 * placed at the right edge of the menu bar.
 */
@interface StatusItemManager : NSObject

/**
 * Array of loaded status item providers, sorted by ascending displayPriority.
 */
@property (nonatomic, strong) NSMutableArray<id<StatusItemProvider>> *statusItems;

/**
 * Dictionary mapping update intervals (NSNumber) to NSTimer instances.
 */
@property (nonatomic, strong) NSMutableDictionary *updateTimers;

/**
 * Dictionary mapping provider identifiers to their StatusItemView.
 */
@property (nonatomic, strong) NSMutableDictionary<NSString *, StatusItemView *> *itemViews;

/**
 * The status items container view (created by -createStatusItemsView).
 */
@property (nonatomic, weak) StatusItemsView *statusItemsView;

/**
 * Screen width (used for sizing calculations).
 */
@property (nonatomic, assign) CGFloat screenWidth;

/**
 * Menu bar height.
 */
@property (nonatomic, assign) CGFloat menuBarHeight;

/**
 * Initialize the manager.
 *
 * @param width  Screen width in pixels
 * @param height Menu bar height in pixels
 */
- (instancetype)initWithScreenWidth:(CGFloat)width
                      menuBarHeight:(CGFloat)height;

/**
 * Load all status item bundles from standard locations and sort by priority.
 */
- (void)loadStatusItems;

/**
 * Create and return a StatusItemsView populated with fixed-width
 * StatusItemView instances for every loaded provider.
 * Call this after -loadStatusItems.
 */
- (StatusItemsView *)createStatusItemsView;

/**
 * Start coalesced update timers for all providers.
 */
- (void)startUpdateTimers;

/**
 * Stop all update timers.
 */
- (void)stopUpdateTimers;

/**
 * Unload all status items, stop timers, and release resources.
 */
- (void)unloadAllStatusItems;

@end
