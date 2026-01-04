/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MenuBarView.h"

@implementation MenuBarView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
         // Use the theme's menubar background color instead of hardcoded values
        self.backgroundColor = [[GSTheme theme] menuItemBackgroundColor];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSLog(@"MenuBarView: drawRect called with rect: %.0f,%.0f %.0fx%.0f", 
          dirtyRect.origin.x, dirtyRect.origin.y, dirtyRect.size.width, dirtyRect.size.height);
    
    // Fill with theme background color - this provides the gradient for the entire menu bar
    if (self.backgroundColor) {
        [self.backgroundColor set];
        NSRectFill([self bounds]);
        NSLog(@"MenuBarView: Drew theme background color: %@", self.backgroundColor);
    } else {
        // Fallback to light gray if theme color is unavailable
        [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] set];
        NSRectFill([self bounds]);
        NSLog(@"MenuBarView: Warning - used fallback background color");
    }
    
    // Draw bottom border
    NSRect borderRect = NSMakeRect(0, 0, [self bounds].size.width, 1);
    [[NSColor colorWithCalibratedWhite:0.5 alpha:1.0] set];
    NSRectFill(borderRect);
    NSLog(@"MenuBarView: Drew bottom border");
}

- (BOOL)isOpaque
{
    return NO;
}

@end
