/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class StatusItemView;

/**
 * Container view for status items displayed at the right edge of the menu bar.
 *
 * Manages an ordered array of fixed-width StatusItemView instances laid out
 * right-to-left.  Items are ordered by their provider's displayPriority so
 * that the highest-priority item (e.g., the clock) is always rightmost.
 *
 * This is analogous to NSStatusBar: a system-provided area that hosts an
 * ordered collection of individually-sized status items.
 */
@interface StatusItemsView : NSView

/**
 * Ordered array of StatusItemView instances (ascending displayPriority,
 * so the last element is rightmost).
 */
@property (nonatomic, strong, readonly) NSMutableArray<StatusItemView *> *itemViews;

/**
 * Horizontal spacing between adjacent status items (pixels).
 */
@property (nonatomic, assign) CGFloat interItemSpacing;

/**
 * Inset from the right edge of the container to the first (rightmost) item.
 */
@property (nonatomic, assign) CGFloat rightInset;

/**
 * Initialize the status items container.
 * @param frame The initial frame (typically right-aligned within the menu bar)
 */
- (instancetype)initWithFrame:(NSRect)frame;

/**
 * Append a status item view.  Views should be added in ascending
 * displayPriority order (lowest first, highest last = rightmost).
 *
 * @param itemView The StatusItemView to add
 */
- (void)addItemView:(StatusItemView *)itemView;

/**
 * Recalculate positions of all item views within the container.
 * Call after adding all views or when the container frame changes.
 */
- (void)layoutItemViews;

/**
 * Compute the total width required for all items, inter-item spacing
 * and the right inset.  Use this to size the container before adding
 * it to the menu bar.
 */
- (CGFloat)totalRequiredWidth;

@end
