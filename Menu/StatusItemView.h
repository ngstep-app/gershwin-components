/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "StatusItemProvider.h"

@class StatusItemManager;

/**
 * A fixed-width view that displays a single status item in the menu bar.
 *
 * Each StatusItemView maintains a constant width regardless of content changes,
 * preventing layout shifts when dynamic text (e.g., CPU percentages, clock) updates.
 * Text is drawn centered within the fixed-width bounds.
 *
 * This is analogous to NSStatusItem's view-based rendering where each item
 * occupies a fixed slot in the status bar area.
 */
@interface StatusItemView : NSView

/**
 * The status item provider this view displays.
 */
@property (nonatomic, weak) id<StatusItemProvider> provider;

/**
 * Reference to the status item manager for coordination.
 */
@property (nonatomic, weak) StatusItemManager *manager;

/**
 * The current title string to display. Updated by the manager on timer ticks.
 */
@property (nonatomic, copy) NSString *title;

/**
 * The fixed width of this item view. Does not change when content changes.
 */
@property (nonatomic, readonly) CGFloat fixedWidth;

/**
 * Whether this item is currently highlighted (mouse down state).
 */
@property (nonatomic, assign) BOOL highlighted;

/**
 * Initialize with a provider and fixed dimensions.
 *
 * @param provider The status item provider to display
 * @param width Fixed width for this item (should accommodate widest possible content)
 * @param height Height of the view (typically menu bar height)
 */
- (instancetype)initWithProvider:(id<StatusItemProvider>)provider
                      fixedWidth:(CGFloat)width
                          height:(CGFloat)height;

/**
 * Update the displayed title without changing the view's dimensions.
 * Only triggers a redraw if the title actually changed.
 *
 * @param title New title string to display
 */
- (void)updateTitle:(NSString *)title;

@end
