/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <PreferencePanes/PreferencePanes.h>

@class DisplayController;

@interface DisplayPane : NSPreferencePane
{
    DisplayController *displayController;
    NSTimer *refreshTimer;
}

@end
