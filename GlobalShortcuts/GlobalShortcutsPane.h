/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <PreferencePanes/PreferencePanes.h>

@class GlobalShortcutsController;

@interface GlobalShortcutsPane : NSPreferencePane
{
    GlobalShortcutsController *shortcutsController;
    NSTimer *refreshTimer;
}

@end
