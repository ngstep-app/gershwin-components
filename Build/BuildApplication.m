/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BuildApplication.h"
#import "BuildController.h"

@implementation BuildApplication

@synthesize makefilePath;

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSDebugLLog(@"gwcomp", @"applicationDidFinishLaunching called");
    BuildController *controller = [[BuildController alloc] init];
    [controller setMakefilePath: self.makefilePath];
    [controller setExtraArgs: self.extraArgs];
    [controller showWindow];
}

@end