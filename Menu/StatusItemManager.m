/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StatusItemManager.h"
#import "GNUstepGUI/GSTheme.h"
#import <dispatch/dispatch.h>

@implementation StatusItemManager

- (instancetype)initWithContainerView:(NSView *)container
                          screenWidth:(CGFloat)width
                        menuBarHeight:(CGFloat)height
{
    self = [super init];
    if (self) {
        self.containerView = container;
        self.screenWidth = width;
        self.menuBarHeight = height;
        self.statusItems = [NSMutableArray array];
        self.updateTimers = [NSMutableDictionary dictionary];
        self.menuItems = [NSMutableDictionary dictionary]; // Map provider ID -> NSMenuItem
        self.currentWidths = [NSMutableDictionary dictionary];
        
        // Create the status items menu at the right edge
        self.statusMenu = [[NSMenu alloc] initWithTitle:@"StatusItems"];
        
        NSLog(@"StatusItemManager: Initialized with screen width %.0f, height %.0f", width, height);
    }
    return self;
}

- (void)dealloc
{
    [self unloadAllStatusItems];
}

- (void)loadStatusItems
{
    NSLog(@"StatusItemManager: Loading status item bundles...");
    
    NSMutableArray *searchPaths = [NSMutableArray array];
    
    // Add search paths in priority order
    // 1. Development location (current build)
    NSString *devPath = [[NSBundle mainBundle] bundlePath];
    NSString *devStatusItemsPath = [[devPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"StatusItems"];
    [searchPaths addObject:devStatusItemsPath];
    
    // 2. System location
    [searchPaths addObject:@"/System/Library/Menu/StatusItems"];
    
    // 3. User location
    NSString *userPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Menu/StatusItems"];
    [searchPaths addObject:userPath];
    
    // 4. Bundle resources
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *bundlePath = [resourcePath stringByAppendingPathComponent:@"StatusItems"];
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
                NSString *bundlePath = [searchPath stringByAppendingPathComponent:item];
                [self loadStatusItemFromBundle:[NSBundle bundleWithPath:bundlePath] loadedIdentifiers:loadedIdentifiers];
            } else {
                // Also check subdirectories for bundles (e.g., StatusItems/TimeDisplay/TimeDisplay.bundle)
                NSString *itemPath = [searchPath stringByAppendingPathComponent:item];
                NSError *subError = nil;
                NSArray *subContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:itemPath error:&subError];
                if (!subError) {
                    for (NSString *subItem in subContents) {
                        if ([subItem hasSuffix:@".bundle"]) {
                            NSString *bundlePath = [itemPath stringByAppendingPathComponent:subItem];
                            [self loadStatusItemFromBundle:[NSBundle bundleWithPath:bundlePath] loadedIdentifiers:loadedIdentifiers];
                        }
                    }
                }
            }
        }
    }
    
    // Sort items by display priority (if provider implements it)
    [self.statusItems sortUsingComparator:^NSComparisonResult(id<StatusItemProvider> obj1, id<StatusItemProvider> obj2) {
        NSInteger p1 = 100;
        NSInteger p2 = 100;
        if ([obj1 respondsToSelector:@selector(displayPriority)]) {
            p1 = [obj1 displayPriority];
        }
        if ([obj2 respondsToSelector:@selector(displayPriority)]) {
            p2 = [obj2 displayPriority];
        }
        // Higher priority first
        return p2 - p1;
    }];
    
    NSLog(@"StatusItemManager: Loaded %lu status items", (unsigned long)[self.statusItems count]);
    
    // Layout items and create menu items
    [self layoutStatusItems];
    
    // Start the update timers
    [self startUpdateTimers];
}

- (BOOL)loadStatusItemFromBundle:(NSBundle *)bundle loadedIdentifiers:(NSMutableSet *)loadedIdentifiers
{
    if (!bundle) {
        NSLog(@"StatusItemManager: Bundle is nil");
        return NO;
    }
    
    NSLog(@"StatusItemManager: Loading bundle: %@", [bundle bundlePath]);
    
    // Try to get the principal class without explicitly loading
    // GNUstep bundles may load automatically when accessing the principal class
    Class principalClass = [bundle principalClass];
    
    if (!principalClass) {
        // If that didn't work, try explicit load
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) {
            if (error) {
                NSLog(@"StatusItemManager: Failed to load bundle: %@", error);
            } else {
                NSLog(@"StatusItemManager: Failed to load bundle (unknown error) at path: %@", [bundle bundlePath]);
            }
            return NO;
        }
        principalClass = [bundle principalClass];
    }
    
    if (!principalClass) {
        NSLog(@"StatusItemManager: No principal class in bundle: %@", [bundle bundlePath]);
        return NO;
    }
    
    // Instantiate it
    id instance = [[principalClass alloc] init];
    if (!instance) {
        NSLog(@"StatusItemManager: Failed to instantiate principal class: %@", principalClass);
        return NO;
    }
    
    if (![instance conformsToProtocol:@protocol(StatusItemProvider)]) {
        NSLog(@"StatusItemManager: Instance does not conform to StatusItemProvider protocol: %@", instance);
        return NO;
    }
    
    id<StatusItemProvider> provider = (id<StatusItemProvider>)instance;
    
    // Check if we already loaded a provider with this identifier
    NSString *identifier = [provider identifier];
    if ([loadedIdentifiers containsObject:identifier]) {
        return NO;
    }
    
    // Mark as loaded
    [loadedIdentifiers addObject:identifier];
    
    // Load the provider
    [provider loadWithManager:self];
    
    // Add to our list
    [self.statusItems addObject:provider];
    
    return YES;
}

- (void)layoutStatusItems
{
    NSLog(@"StatusItemManager: Laying out %lu status items", (unsigned long)[self.statusItems count]);
    
    // Remove existing menu items
    while ([self.statusMenu numberOfItems] > 0) {
        [self.statusMenu removeItemAtIndex:0];
    }
    
    // Create right-aligned paragraph style
    NSMutableParagraphStyle *rightAlign = [[NSMutableParagraphStyle alloc] init];
    [rightAlign setAlignment:NSRightTextAlignment];
    
    // Add menu items from providers in reverse order (right to left in menu)
    for (NSInteger i = [self.statusItems count] - 1; i >= 0; i--) {
        id<StatusItemProvider> item = [self.statusItems objectAtIndex:i];
        
        NSString *title = [item title];
        if (!title) {
            title = [NSString stringWithFormat:@"[%@]", [item identifier]];
        }
        
        // Create attributed string with right alignment
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont menuFontOfSize:0],
            NSParagraphStyleAttributeName: rightAlign
        };
        NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:title attributes:attrs];
        
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
                                                          action:@selector(statusItemClicked:)
                                                   keyEquivalent:@""];
        [menuItem setAttributedTitle:attrTitle];
        [menuItem setTarget:self];
        [menuItem setRepresentedObject:[item identifier]];
        [menuItem setTag:0]; // Initial tag, can be used for state
        
        // Set the menu if the provider provides one
        if ([item respondsToSelector:@selector(menu)]) {
            NSMenu *itemMenu = [item menu];
            if (itemMenu) {
                [menuItem setSubmenu:itemMenu];
            }
        }
        
        [self.statusMenu addItem:menuItem];
        [self.menuItems setObject:menuItem forKey:[item identifier]];
    }
}

- (void)startUpdateTimers
{
    // Group items by update interval
    NSMutableDictionary *intervalGroups = [NSMutableDictionary dictionary];
    
    for (id<StatusItemProvider> item in self.statusItems) {
        NSTimeInterval interval = 1.0; // default
        if ([item respondsToSelector:@selector(updateInterval)]) {
            interval = [item updateInterval];
        }
        
        NSNumber *key = @(interval);
        NSMutableArray *group = [intervalGroups objectForKey:key];
        if (!group) {
            group = [NSMutableArray array];
            [intervalGroups setObject:group forKey:key];
        }
        [group addObject:item];
    }
    
    // Create one timer per interval
    for (NSNumber *intervalKey in intervalGroups) {
        NSTimeInterval interval = [intervalKey doubleValue];
        NSArray *items = [intervalGroups objectForKey:intervalKey];
        
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                          target:self
                                                        selector:@selector(updateTimerFired:)
                                                        userInfo:items
                                                         repeats:YES];
        
        [self.updateTimers setObject:timer forKey:intervalKey];
        
        // Fire immediately for initial update
        [self updateTimerFired:timer];
    }
}

- (void)updateTimerFired:(NSTimer *)timer
{
    NSArray *items = [timer userInfo];
    
    for (id<StatusItemProvider> item in items) {
        @try {
            [item update];
            
            // Update the menu item title
            NSMenuItem *menuItem = [self.menuItems objectForKey:[item identifier]];
            if (menuItem) {
                NSString *title = [item title];
                if (!title) {
                    title = [NSString stringWithFormat:@"[%@]", [item identifier]];
                }
                
                // Only update if title actually changed
                // NSMenuItem setTitle will automatically trigger display update if needed
                if (![[menuItem title] isEqualToString:title]) {
                    [menuItem setTitle:title];
                }
            }
            
            // Track width changes but don't trigger relayout
            // NSMenuView handles sizing automatically
            CGFloat newWidth = [item width];
            [self.currentWidths setObject:@(newWidth) forKey:[item identifier]];
        }
        @catch (NSException *exception) {
            NSLog(@"StatusItemManager: Exception updating %@: %@", [item identifier], exception);
        }
    }
}

- (void)stopUpdateTimers
{
    NSLog(@"StatusItemManager: Stopping all update timers");
    
    for (NSTimer *timer in [self.updateTimers allValues]) {
        [timer invalidate];
    }
    
    [self.updateTimers removeAllObjects];
}

- (void)unloadAllStatusItems
{
    NSLog(@"StatusItemManager: Unloading all status items");
    
    [self stopUpdateTimers];
    
    for (id<StatusItemProvider> item in self.statusItems) {
        @try {
            if ([item respondsToSelector:@selector(unload)]) {
                [item unload];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"StatusItemManager: Exception unloading %@: %@", [item identifier], exception);
        }
    }
    
    // Clear menu
    while ([self.statusMenu numberOfItems] > 0) {
        [self.statusMenu removeItemAtIndex:0];
    }
    
    [self.menuItems removeAllObjects];
    [self.statusItems removeAllObjects];
}

- (void)statusItemClicked:(id)sender
{
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    NSString *identifier = [menuItem representedObject];
    
    NSLog(@"StatusItemManager: Click on status item: %@", identifier);
    
    for (id<StatusItemProvider> item in self.statusItems) {
        if ([[item identifier] isEqualToString:identifier]) {
            @try {
                if ([item respondsToSelector:@selector(handleClick)]) {
                    [item handleClick];
                }
            }
            @catch (NSException *exception) {
                NSLog(@"StatusItemManager: Exception handling click for %@: %@", identifier, exception);
            }
            break;
        }
    }
}

- (NSMenu *)statusMenu
{
    return _statusMenu;
}

- (void)requestRelayoutForProvider:(id<StatusItemProvider>)provider
{
    // Deprecated - use requestRelayout instead
    [self requestRelayout];
}

- (void)requestRelayout
{
    // Throttle relayout requests - coalesce multiple rapid calls into one
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self requestRelayout];
        });
        return;
    }
    
    // Cancel any pending relayout and schedule a new one after a short delay
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performRelayout) object:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self performRelayout];
    });
}

- (void)performRelayout
{
    // NSMenuView automatically updates when menu item titles change via setTitle:
    // No manual relayout needed - this is just a placeholder for future enhancements
}

@end
