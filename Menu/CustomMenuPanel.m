/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "CustomMenuPanel.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation MenuGradientView

@synthesize gradient = _gradient;

- (void)drawRect:(NSRect)dirtyRect
{
    // Draw the gradient background
    if (_gradient) {
        [_gradient drawInRect:dirtyRect angle:-90];
    }
    
    // Draw top border line (bright line at top)
    NSRect bounds = [self bounds];
    NSBezierPath *linePath = [NSBezierPath bezierPath];
    [linePath moveToPoint:NSMakePoint(bounds.origin.x, bounds.origin.y + bounds.size.height)];
    [linePath lineToPoint:NSMakePoint(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height)];
    [linePath setLineWidth:1];
    
    NSColor *topLineColor = [NSColor colorWithCalibratedRed:1.0 
                                                     green:1.0 
                                                      blue:1.0 
                                                     alpha:0.8];
    [topLineColor setStroke];
    [linePath stroke];
}

- (BOOL)isOpaque
{
    return NO;
}

@end

@implementation CustomMenuPanel

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)styleMask
                  backing:(NSBackingStoreType)backingType
                    defer:(BOOL)flag
{
    // Create the panel with the specified parameters
    self = [super initWithContentRect:contentRect
                            styleMask:styleMask
                              backing:backingType
                                defer:flag];
    
    if (self) {
        // Apply the same gradient and opacity styling as the menu bar
        // Use the Eau theme menu colors
        NSColor *brightGrey = [NSColor colorWithCalibratedRed:0.95 
                                                        green:0.95 
                                                         blue:0.95 
                                                        alpha:0.80];
        NSColor *midGrey = [NSColor colorWithCalibratedRed:0.85 
                                                     green:0.85 
                                                      blue:0.85 
                                                     alpha:0.70];
        
        _menuGradient = [[NSGradient alloc] initWithStartingColor:brightGrey 
                                                       endingColor:midGrey];
        
        // Set window properties for menu appearance
        [self setBackgroundColor:[NSColor clearColor]];
        [self setOpaque:NO];
        [self setAlphaValue:1.0];
        
        NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Created with gradient and opacity styling");
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Draw the gradient background for the entire panel
    if (_menuGradient) {
        [_menuGradient drawInRect:dirtyRect angle:-90];
        
        // Draw top border line (bright line at top)
        NSRect bounds = dirtyRect;
        NSBezierPath *linePath = [NSBezierPath bezierPath];
        [linePath moveToPoint:NSMakePoint(bounds.origin.x, bounds.origin.y + bounds.size.height)];
        [linePath lineToPoint:NSMakePoint(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height)];
        [linePath setLineWidth:1];
        
        NSColor *topLineColor = [NSColor colorWithCalibratedRed:1.0 
                                                         green:1.0 
                                                          blue:1.0 
                                                         alpha:0.8];
        [topLineColor setStroke];
        [linePath stroke];
    }
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)dealloc
{
    // ARC handles deallocation automatically
}

@end

@implementation CustomMenuView

- (void)drawRect:(NSRect)dirtyRect
{
    // Draw with transparent background to let the panel's gradient show through
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);
    
    // Call the parent implementation which draws the menu items
    [super drawRect:dirtyRect];
}

- (BOOL)isOpaque
{
    return NO;
}

@end

/* Helper category to provide swizzleable methods for NSMenuView */
@interface NSMenuView (CustomMenuPanelHooks)
- (void)original_drawRect:(NSRect)dirtyRect;
- (BOOL)original_isOpaque;
- (NSWindow *)original_window;
@end

// Store original method implementations before swizzling
static IMP original_NSMenuView_drawRectIMP = NULL;
static IMP original_NSMenuView_windowIMP = NULL;

@implementation NSMenuView (CustomMenuPanelHooks)

- (void)original_drawRect:(NSRect)dirtyRect
{
    // Fill with transparent background so the window/parent gradient shows through
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    // Call original implementation which delegates to the theme's drawMenuRect:
    // The theme draws the gradient background and menu item cells.
    if (original_NSMenuView_drawRectIMP) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ((void (*)(id, SEL, NSRect))original_NSMenuView_drawRectIMP)(self, @selector(drawRect:), dirtyRect);
        #pragma clang diagnostic pop
    }
}

- (BOOL)original_isOpaque
{
    return NO;
}

- (NSWindow *)original_window
{
    // Get the actual window using the original implementation
    NSWindow *window = NULL;
    if (original_NSMenuView_windowIMP) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        window = ((NSWindow * (*)(id, SEL))original_NSMenuView_windowIMP)(self, @selector(window));
        #pragma clang diagnostic pop
    }

    if (window && ![window isKindOfClass:[CustomMenuPanel class]]) {
        // Apply gradient styling to the window
        [window setBackgroundColor:[NSColor clearColor]];
        [window setOpaque:NO];

        // Quick check: if the content view is already a MenuGradientView, we've already wrapped it
        NSView *contentView = [window contentView];
        if (!contentView || [contentView isKindOfClass:[MenuGradientView class]]) {
            return window;
        }

        // Apply gradient styling to the window (first time only)
        NSRect contentBounds = [contentView bounds];
        MenuGradientView *gradientView = [[MenuGradientView alloc] initWithFrame:contentBounds];

        // Set up the gradient
        NSColor *brightGrey = [NSColor colorWithCalibratedRed:0.95
                                                        green:0.95
                                                         blue:0.95
                                                        alpha:0.80];
        NSColor *midGrey = [NSColor colorWithCalibratedRed:0.85
                                                     green:0.85
                                                      blue:0.85
                                                     alpha:0.70];

        NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:brightGrey
                                                             endingColor:midGrey];
        [gradientView setGradient:gradient];

        // Ensure gradient view fills the content area
        [gradientView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        // Adjust contentView to fill the gradient view
        [contentView setFrame:contentBounds];
        [contentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        // Set as background and bring content view to front
        [contentView removeFromSuperview];
        [window setContentView:gradientView];
        [gradientView addSubview:contentView];

        NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Wrapped window %@ content view with gradient", window);
    }

    return window;
}

@end

void HookNSMenuPanelCreation(void)
{
    NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Setting up hooks for menu window styling");
    
    // Hook NSMenuView to make it transparent and apply gradient styling
    Class nsMenuViewClass = NSClassFromString(@"NSMenuView");
    if (nsMenuViewClass) {
        // Swizzle drawRect:
        Method originalDrawMethod = class_getInstanceMethod(nsMenuViewClass, @selector(drawRect:));
        Method newDrawMethod = class_getInstanceMethod([NSMenuView class], @selector(original_drawRect:));
        
        if (originalDrawMethod && newDrawMethod) {
            // Save the original implementation
            original_NSMenuView_drawRectIMP = method_getImplementation(originalDrawMethod);
            method_exchangeImplementations(originalDrawMethod, newDrawMethod);
            NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Swizzled NSMenuView.drawRect for transparent background");
        }
        
        // Swizzle isOpaque:
        Method originalOpaqueMethod = class_getInstanceMethod(nsMenuViewClass, @selector(isOpaque));
        Method newOpaqueMethod = class_getInstanceMethod([NSMenuView class], @selector(original_isOpaque));
        
        if (originalOpaqueMethod && newOpaqueMethod) {
            method_exchangeImplementations(originalOpaqueMethod, newOpaqueMethod);
            NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Swizzled NSMenuView.isOpaque");
        }
        
        // Swizzle window:
        Method originalWindowMethod = class_getInstanceMethod(nsMenuViewClass, @selector(window));
        Method newWindowMethod = class_getInstanceMethod([NSMenuView class], @selector(original_window));
        
        if (originalWindowMethod && newWindowMethod) {
            // Save the original implementation
            original_NSMenuView_windowIMP = method_getImplementation(originalWindowMethod);
            method_exchangeImplementations(originalWindowMethod, newWindowMethod);
            NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Swizzled NSMenuView.window for gradient styling");
        }
    }
    
    NSDebugLLog(@"gwcomp", @"CustomMenuPanel: Menu window styling hooks complete");
}


