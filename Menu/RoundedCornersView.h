/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@interface RoundedCornersView : NSView
{
    CGFloat _cornerRadius;
}

- (id)initWithFrame:(NSRect)frameRect cornerRadius:(CGFloat)radius;
- (void)drawRect:(NSRect)dirtyRect;

@end
