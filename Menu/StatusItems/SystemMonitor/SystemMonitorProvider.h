/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "../../StatusItemProvider.h"

/**
 * Provides CPU and RAM usage monitoring in the menu bar.
 * Cross-platform: supports Linux and BSD systems.
 */
@interface SystemMonitorProvider : NSObject <StatusItemProvider>

/**
 * Reference to the status item manager.
 */
@property (nonatomic, weak) id manager;

/**
 * Current CPU usage percentage (0-100).
 */
@property (nonatomic, assign) CGFloat cpuUsage;

/**
 * Current RAM usage percentage (0-100).
 */
@property (nonatomic, assign) CGFloat ramUsage;

/**
 * Per-core CPU usage for detailed menu.
 */
@property (nonatomic, strong) NSMutableArray<NSNumber *> *perCoreCPU;

/**
 * Previous CPU tick counts for calculating usage.
 */
@property (nonatomic, assign) unsigned long long lastTotalTicks;
@property (nonatomic, assign) unsigned long long lastIdleTicks;

/**
 * Menu to display system details.
 */
@property (nonatomic, strong) NSMenu *detailMenu;

/**
 * Cached fixed width computed at load time from the widest possible content string.
 */
@property (nonatomic, assign) CGFloat cachedFixedWidth;

/**
 * Read current CPU usage from system.
 */
- (void)updateCPUUsage;

/**
 * Read current RAM usage from system.
 */
- (void)updateRAMUsage;

/**
 * Update the detail menu with current stats.
 */
- (void)updateDetailMenu;

@end
