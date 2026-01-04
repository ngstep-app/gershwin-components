/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "GNUstepGUI/GSTheme.h"

/**
 * Custom view that draws a gradient background for menu panels
 */
@interface MenuGradientView : NSView
{
    NSGradient *_gradient;
}

@property (nonatomic, strong) NSGradient *gradient;

@end

/**
 * Custom NSMenuPanel subclass that applies gradient and opacity styling
 * similar to the horizontal menu bar, ensuring consistent appearance
 * across all menu popups.
 */
@interface CustomMenuPanel : NSPanel
{
    NSGradient *_menuGradient;
}

@end

/**
 * Custom NSMenuView that renders with a transparent background,
 * allowing the panel's gradient background to show through.
 */
@interface CustomMenuView : NSMenuView
{
}

@end

// Global function to hook NSMenu panel creation
void HookNSMenuPanelCreation(void);
