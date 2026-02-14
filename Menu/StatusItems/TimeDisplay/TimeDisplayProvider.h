/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "../../StatusItemProvider.h"

/**
 * Displays current time in the menu bar.
 */
@interface TimeDisplayProvider : NSObject <StatusItemProvider>

/**
 * Reference to the status item manager.
 */
@property (nonatomic, weak) id manager;

/**
 * Formatter for time display (HH:MM).
 */
@property (nonatomic, strong) NSDateFormatter *timeFormatter;

/**
 * Current title being displayed.
 */
@property (nonatomic, strong) NSString *currentTitle;

/**
 * Cached fixed width computed at load time from the widest possible time string.
 */
@property (nonatomic, assign) CGFloat cachedFixedWidth;

/**
 * Update the displayed time.
 */
- (void)updateTime;

@end
