/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class MainWindowController;
@class SIPManager;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) MainWindowController *mainWindowController;
@property (strong) SIPManager *sipManager;

@end
