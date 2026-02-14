/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StatusItemManager.h"
#import "StatusItemView.h"
#import "StatusItemsView.h"
#import <dispatch/dispatch.h>

@implementation StatusItemManager

- (instancetype)initWithScreenWidth:(CGFloat)width
                      menuBarHeight:(CGFloat)height
{
    self = [super init];
    if (self) {
        _screenWidth = width;
        _menuBarHeight = height;
        _statusItems = [NSMutableArray array];
        _updateTimers = [NSMutableDictionary dictionary];
        _itemViews = [NSMutableDictionary dictionary];

        NSLog(@"StatusItemManager: Initialized with screen width %.0f, height %.0f",
              width, height);
    }
    return self;
}

- (void)dealloc
{
    [self unloadAllStatusItems];
}

#pragma mark - Bundle loading

- (void)loadStatusItems
{
    NSLog(@"StatusItemManager: Loading status item bundles...");

    NSMutableArray *searchPaths = [NSMutableArray array];

    /* 1. Development location (next to Menu.app) */
    NSString *devPath = [[NSBundle mainBundle] bundlePath];
    NSString *devStatusItemsPath =
        [[devPath stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"StatusItems"];
    [searchPaths addObject:devStatusItemsPath];

    /* 2. System location */
    [searchPaths addObject:@"/System/Library/Menu/StatusItems"];

    /* 3. User location */
    NSString *userPath =
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Menu/StatusItems"];
    [searchPaths addObject:userPath];

    /* 4. Bundle resources */
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *bundlePath =
        [resourcePath stringByAppendingPathComponent:@"StatusItems"];
    [searchPaths addObject:bundlePath];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet *loadedIdentifiers = [NSMutableSet set];

    for (NSString *searchPath in searchPaths) {
        NSLog(@"StatusItemManager: Searching for bundles in: %@", searchPath);

        if (![fm fileExistsAtPath:searchPath]) {
            NSLog(@"StatusItemManager: Path does not exist: %@", searchPath);
            continue;
        }

        NSError *error = nil;
        NSArray *contents = [fm contentsOfDirectoryAtPath:searchPath error:&error];
        if (error) {
            NSLog(@"StatusItemManager: Error reading directory %@: %@", searchPath, error);
            continue;
        }

        for (NSString *item in contents) {
            if ([item hasSuffix:@".bundle"]) {
                NSString *bp = [searchPath stringByAppendingPathComponent:item];
                [self loadStatusItemFromBundle:[NSBundle bundleWithPath:bp]
                            loadedIdentifiers:loadedIdentifiers];
            } else {
                /* Check subdirectories for bundles */
                NSString *itemPath = [searchPath stringByAppendingPathComponent:item];
                NSError *subError = nil;
                NSArray *subContents =
                    [fm contentsOfDirectoryAtPath:itemPath error:&subError];
                if (!subError) {
                    for (NSString *subItem in subContents) {
                        if ([subItem hasSuffix:@".bundle"]) {
                            NSString *bp =
                                [itemPath stringByAppendingPathComponent:subItem];
                            [self loadStatusItemFromBundle:[NSBundle bundleWithPath:bp]
                                        loadedIdentifiers:loadedIdentifiers];
                        }
                    }
                }
            }
        }
    }

    /* Sort by ascending displayPriority so highest-priority ends up rightmost */
    [_statusItems sortUsingComparator:
        ^NSComparisonResult(id<StatusItemProvider> a, id<StatusItemProvider> b) {
            NSInteger pa = 100, pb = 100;
            if ([a respondsToSelector:@selector(displayPriority)]) pa = [a displayPriority];
            if ([b respondsToSelector:@selector(displayPriority)]) pb = [b displayPriority];
            if (pa < pb) return NSOrderedAscending;
            if (pa > pb) return NSOrderedDescending;
            return NSOrderedSame;
        }];

    NSLog(@"StatusItemManager: Loaded %lu status items",
          (unsigned long)[_statusItems count]);
}

- (BOOL)loadStatusItemFromBundle:(NSBundle *)bundle
               loadedIdentifiers:(NSMutableSet *)loadedIdentifiers
{
    if (!bundle) {
        NSLog(@"StatusItemManager: Bundle is nil");
        return NO;
    }

    NSLog(@"StatusItemManager: Loading bundle: %@", [bundle bundlePath]);

    Class principalClass = [bundle principalClass];
    if (!principalClass) {
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) {
            NSLog(@"StatusItemManager: Failed to load bundle: %@",
                  error ? (id)error : @"unknown error");
            return NO;
        }
        principalClass = [bundle principalClass];
    }

    if (!principalClass) {
        NSLog(@"StatusItemManager: No principal class in bundle: %@",
              [bundle bundlePath]);
        return NO;
    }

    id instance = [[principalClass alloc] init];
    if (!instance) {
        NSLog(@"StatusItemManager: Failed to instantiate: %@", principalClass);
        return NO;
    }

    if (![instance conformsToProtocol:@protocol(StatusItemProvider)]) {
        NSLog(@"StatusItemManager: %@ does not conform to StatusItemProvider",
              instance);
        return NO;
    }

    id<StatusItemProvider> provider = (id<StatusItemProvider>)instance;
    NSString *identifier = [provider identifier];

    if ([loadedIdentifiers containsObject:identifier]) {
        return NO;
    }

    [loadedIdentifiers addObject:identifier];
    [provider loadWithManager:self];
    [_statusItems addObject:provider];

    NSLog(@"StatusItemManager: Loaded provider '%@' (priority %ld, width %.0f)",
          identifier,
          (long)([provider respondsToSelector:@selector(displayPriority)]
                     ? [provider displayPriority] : 100),
          [provider width]);

    return YES;
}

#pragma mark - View creation

- (StatusItemsView *)createStatusItemsView
{
    StatusItemsView *container =
        [[StatusItemsView alloc] initWithFrame:NSMakeRect(0, 0, 1, _menuBarHeight)];

    for (id<StatusItemProvider> provider in _statusItems) {
        CGFloat fixedWidth = [provider width];

        StatusItemView *view =
            [[StatusItemView alloc] initWithProvider:provider
                                          fixedWidth:fixedWidth
                                              height:_menuBarHeight];
        view.manager = self;

        [container addItemView:view];
        [_itemViews setObject:view forKey:[provider identifier]];
    }

    /* Size container to fit all items and lay them out */
    CGFloat totalWidth = [container totalRequiredWidth];
    [container setFrame:NSMakeRect(0, 0, totalWidth, _menuBarHeight)];
    [container layoutItemViews];

    _statusItemsView = container;

    NSLog(@"StatusItemManager: Created StatusItemsView (%.0f x %.0f) with %lu items",
          totalWidth, _menuBarHeight, (unsigned long)[_statusItems count]);

    return container;
}

#pragma mark - Update timers

- (void)startUpdateTimers
{
    NSMutableDictionary *intervalGroups = [NSMutableDictionary dictionary];

    for (id<StatusItemProvider> item in _statusItems) {
        NSTimeInterval interval = 1.0;
        if ([item respondsToSelector:@selector(updateInterval)]) {
            interval = [item updateInterval];
        }
        if (interval < 0.5) interval = 0.5;

        NSNumber *key = @(interval);
        NSMutableArray *group = [intervalGroups objectForKey:key];
        if (!group) {
            group = [NSMutableArray array];
            [intervalGroups setObject:group forKey:key];
        }
        [group addObject:item];
    }

    for (NSNumber *intervalKey in intervalGroups) {
        NSTimeInterval interval = [intervalKey doubleValue];
        NSArray *items = [intervalGroups objectForKey:intervalKey];

        NSTimer *timer =
            [NSTimer scheduledTimerWithTimeInterval:interval
                                             target:self
                                           selector:@selector(updateTimerFired:)
                                           userInfo:items
                                            repeats:YES];
        [_updateTimers setObject:timer forKey:intervalKey];

        /* Fire once immediately for initial display */
        [self updateTimerFired:timer];
    }
}

- (void)updateTimerFired:(NSTimer *)timer
{
    NSArray *items = [timer userInfo];

    for (id<StatusItemProvider> item in items) {
        @try {
            [item update];

            NSString *title = [item title];
            if (!title) {
                title = [NSString stringWithFormat:@"[%@]", [item identifier]];
            }

            StatusItemView *view = [_itemViews objectForKey:[item identifier]];
            if (view) {
                [view updateTitle:title];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"StatusItemManager: Exception updating %@: %@",
                  [item identifier], exception);
        }
    }
}

- (void)stopUpdateTimers
{
    NSLog(@"StatusItemManager: Stopping all update timers");
    for (NSTimer *timer in [_updateTimers allValues]) {
        [timer invalidate];
    }
    [_updateTimers removeAllObjects];
}

#pragma mark - Cleanup

- (void)unloadAllStatusItems
{
    NSLog(@"StatusItemManager: Unloading all status items");

    [self stopUpdateTimers];

    for (id<StatusItemProvider> item in _statusItems) {
        @try {
            if ([item respondsToSelector:@selector(unload)]) {
                [item unload];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"StatusItemManager: Exception unloading %@: %@",
                  [item identifier], exception);
        }
    }

    [_itemViews removeAllObjects];
    [_statusItems removeAllObjects];
}

@end
