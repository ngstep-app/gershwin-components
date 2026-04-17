/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MenuBarView.h"
#import "MenuProfiler.h"

@implementation MenuBarView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        // Use the theme's menubar background color instead of hardcoded values
        self.backgroundColor = [[GSTheme theme] menuItemBackgroundColor];
        _cachedBackgroundColor = self.backgroundColor;
        _needsRedraw = YES;
    }
    return self;
}

- (void)setNeedsRedraw
{
    _needsRedraw = YES;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    MENU_PROFILE_BEGIN(MenuBarViewDraw);
    
    // Skip drawing if color hasn't changed and we don't need redraw
    if (!_needsRedraw && _cachedBackgroundColor == self.backgroundColor) {
        MENU_PROFILE_END(MenuBarViewDraw);
        return;
    }
    
    _needsRedraw = NO;
    _cachedBackgroundColor = self.backgroundColor;
    
    // Fill with theme background color - this provides the base for the entire menu bar
    if (self.backgroundColor) {
        [self.backgroundColor set];
        NSRectFill([self bounds]);
    } else {
        // Fallback to light gray if theme color is unavailable
        [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] set];
        NSRectFill([self bounds]);
    }
    
    MENU_PROFILE_END(MenuBarViewDraw);
}

- (BOOL)isOpaque
{
    return YES;
}

@end
