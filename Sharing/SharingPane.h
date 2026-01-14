/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sharing Preference Pane
 */

#import <PreferencePanes/PreferencePanes.h>

@class SharingController;

@interface SharingPane : NSPreferencePane
{
    SharingController *controller;
    NSTimer *refreshTimer;
}

@end
