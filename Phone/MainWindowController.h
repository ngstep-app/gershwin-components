/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "SIPManager.h"

@interface MainWindowController : NSWindowController <SIPManagerDelegate, NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithSIPManager:(SIPManager *)manager;

// Close any active alert sheets safely
- (void)closeActiveAlert;

@end
