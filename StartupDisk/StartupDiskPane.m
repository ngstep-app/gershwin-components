/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StartupDiskPane.h"
#import "StartupDiskController.h"

@implementation StartupDiskPane

- (id)initWithBundle:(NSBundle *)bundle
{
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: initWithBundle called with bundle = %@", bundle);
    self = [super initWithBundle:bundle];
    if (self) {
        NSDebugLLog(@"gwcomp", @"StartupDiskPane: initWithBundle succeeded, checking efibootmgr permissions");
        
        NSDebugLLog(@"gwcomp", @"StartupDiskPane: efibootmgr permissions check passed");
    } else {
        NSDebugLLog(@"gwcomp", @"StartupDiskPane: initWithBundle failed - super initWithBundle returned nil");
    }
    return self;
}

- (NSView *)loadMainView
{
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: loadMainView called");
    
    // Create the main view if it doesn't exist
    if (![self mainView]) {
        NSDebugLLog(@"gwcomp", @"StartupDiskPane: No main view exists, creating one");
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
        [self setMainView:view];
        [view release];
        NSDebugLLog(@"gwcomp", @"StartupDiskPane: Created main view with frame: %@", NSStringFromRect([view frame]));
    }
    
    NSView *mainView = [super loadMainView];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: super loadMainView completed, returned view = %@", mainView);
    [self mainViewDidLoad];
    return mainView;
}

- (void)mainViewDidLoad
{
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: mainViewDidLoad called");
    
    NSView *mainView = [self mainView];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: mainView = %@", mainView);
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: mainView frame = %@", NSStringFromRect([mainView frame]));
    
    startupDiskController = [[StartupDiskController alloc] init];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: Created startupDiskController = %@", startupDiskController);
    
    [startupDiskController setMainView:mainView];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: Set main view on controller");
    
    // Set up a timer to refresh the boot entries periodically
    refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                    target:self
                                                  selector:@selector(refreshBootEntries)
                                                  userInfo:nil
                                                   repeats:YES];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: Created refresh timer = %@", refreshTimer);
    
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: About to call refreshBootEntries");
    [self refreshBootEntries];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: mainViewDidLoad completed");
}

- (void)refreshBootEntries
{
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: refreshBootEntries called");
    [startupDiskController refreshBootEntries];
    NSDebugLLog(@"gwcomp", @"StartupDiskPane: refreshBootEntries completed");
}

- (void)willUnselect
{
    [refreshTimer invalidate];
    refreshTimer = nil;
}

- (void)dealloc
{
    [refreshTimer invalidate];
    [startupDiskController release];
    [super dealloc];
}

@end
