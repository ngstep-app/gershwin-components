/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TimeDisplayProvider.h"

@implementation TimeDisplayProvider

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.currentTitle = @"--:--";
        self.cachedFixedWidth = 0.0;
    }
    return self;
}

- (NSString *)identifier
{
    return @"org.gershwin.menu.statusitem.time";
}

- (NSString *)title
{
    return self.currentTitle;
}

- (CGFloat)width
{
    /*
     * Return a fixed width large enough for the widest possible time string.
     * Computed once at load time and cached so it never changes.
     */
    return self.cachedFixedWidth;
}

- (NSInteger)displayPriority
{
    /* Highest priority — always appears at the far right */
    return 1000;
}

- (NSTimeInterval)updateInterval
{
    return 1.0;
}

- (void)loadWithManager:(id)manager
{
    NSLog(@"TimeDisplayProvider: Loading time display");
    self.manager = manager;

    /* Create time formatter */
    self.timeFormatter = [[NSDateFormatter alloc] init];
    [self.timeFormatter setDateFormat:@"HH:mm"];

    /*
     * Compute fixed width from the widest possible time string.
     * "00:00" uses wide digits; add generous padding (8 px each side).
     */
    NSFont *font = [NSFont menuBarFontOfSize:0];
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    NSSize size = [@"00:00" sizeWithAttributes:attrs];
    self.cachedFixedWidth = ceil(size.width) + 16.0;

    NSLog(@"TimeDisplayProvider: Computed fixed width: %.0f", self.cachedFixedWidth);

    /* Initial update */
    [self update];
}

- (void)update
{
    [self updateTime];
}

- (void)handleClick
{
    /* Click handler — no action needed, time is display-only */
}

- (NSMenu *)menu
{
    return nil;
}

- (void)unload
{
    NSLog(@"TimeDisplayProvider: Unloading");
    self.timeFormatter = nil;
}

#pragma mark - Time Display

- (void)updateTime
{
    NSDate *now = [NSDate date];
    NSString *timeString = [self.timeFormatter stringFromDate:now];
    self.currentTitle = timeString;
}

@end
