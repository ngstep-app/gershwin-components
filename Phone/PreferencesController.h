/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface PreferencesController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

+ (PreferencesController *)sharedController;

@end
