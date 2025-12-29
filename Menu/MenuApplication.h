/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@interface MenuApplication : NSApplication <NSApplicationDelegate>
{
}

+ (MenuApplication *)sharedApplication;
- (void)sendEvent:(NSEvent *)event;
- (BOOL)checkForExistingMenuApplication;

@end
