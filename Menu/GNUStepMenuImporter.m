/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "GNUStepMenuImporter.h"
#import "GNUStepMenuActionHandler.h"
#import "AppMenuWidget.h"
#import <Foundation/NSConnection.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

static NSString *const kGershwinMenuServerName = @"org.gnustep.Gershwin.MenuServer";

@interface GNUStepMenuImporter ()
@property (nonatomic, strong) NSMutableDictionary *menusByWindow;
@property (nonatomic, strong) NSMutableDictionary *clientNamesByWindow;
@property (nonatomic, strong) NSMutableDictionary *lastMenuDataByWindow;
@property (nonatomic, strong) NSMutableDictionary *lastMenuUpdateTimeByWindow;
@property (nonatomic, strong) NSConnection *menuServerConnection;
@end

@implementation GNUStepMenuImporter

- (instancetype)init
{
    self = [super init];
    if (self) {
        _menusByWindow = [[NSMutableDictionary alloc] init];
        _clientNamesByWindow = [[NSMutableDictionary alloc] init];
        _lastMenuDataByWindow = [[NSMutableDictionary alloc] init];
        _lastMenuUpdateTimeByWindow = [[NSMutableDictionary alloc] init];
        
        // Register the GNUstep menu server immediately so apps can connect
        // This must happen early, before any GNUstep apps try to connect
        [self registerService];
    }
    return self;
}

#pragma mark - MenuProtocolHandler

- (BOOL)connectToDBus
{
    return [self registerService];
}

- (BOOL)registerService
{
    if (self.menuServerConnection) {
        return YES;
    }

    NSConnection *connection = [NSConnection defaultConnection];
    [connection setRootObject:self];

    BOOL registered = [connection registerName:kGershwinMenuServerName];
    if (!registered) {
        NSLog(@"GNUStepMenuImporter: Failed to register GNUstep menu server name %@", kGershwinMenuServerName);
        return NO;
    }

    // CRITICAL: Add receive port to run loop so we can receive incoming messages
    NSPort *receivePort = [connection receivePort];
    [[NSRunLoop currentRunLoop] addPort:receivePort forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addPort:receivePort forMode:NSModalPanelRunLoopMode];
    [[NSRunLoop currentRunLoop] addPort:receivePort forMode:NSEventTrackingRunLoopMode];

    self.menuServerConnection = connection;
    NSLog(@"GNUStepMenuImporter: Registered GNUstep menu server as %@ with receive port added to run loop", kGershwinMenuServerName);
    return YES;
}

- (BOOL)hasMenuForWindow:(unsigned long)windowId
{
    return [self.menusByWindow objectForKey:@(windowId)] != nil;
}

- (NSMenu *)getMenuForWindow:(unsigned long)windowId
{
    return [self.menusByWindow objectForKey:@(windowId)];
}

- (void)activateMenuItem:(NSMenuItem *)menuItem forWindow:(unsigned long)windowId
{
    if (!menuItem) {
        return;
    }

    [GNUStepMenuActionHandler performMenuAction:menuItem];
}

- (void)registerWindow:(unsigned long)windowId
           serviceName:(NSString *)serviceName
            objectPath:(NSString *)objectPath
{
    (void)windowId;
    (void)serviceName;
    (void)objectPath;
    // GNUstep menus are pushed via updateMenuForWindow:menuData:clientName:
}

- (void)unregisterWindow:(unsigned long)windowId
{
    NSNumber *windowKey = @(windowId);
    [self.menusByWindow removeObjectForKey:windowKey];
    [self.clientNamesByWindow removeObjectForKey:windowKey];
}

- (void)scanForExistingMenuServices
{
    // GNUstep menus are pushed directly by clients; nothing to scan.
}

- (NSString *)getMenuServiceForWindow:(unsigned long)windowId
{
    return [self.clientNamesByWindow objectForKey:@(windowId)];
}

- (NSString *)getMenuObjectPathForWindow:(unsigned long)windowId
{
    (void)windowId;
    return nil;
}

- (void)setAppMenuWidget:(AppMenuWidget *)appMenuWidget
{
    _appMenuWidget = appMenuWidget;
}

#pragma mark - GNUstep Menu Server

- (oneway void)updateMenuForWindow:(NSNumber *)windowId
                          menuData:(NSDictionary *)menuData
                        clientName:(NSString *)clientName
{
    // Defensive checks for remote calls
    if (!windowId || ![windowId isKindOfClass:[NSNumber class]] ||
        !menuData || ![menuData isKindOfClass:[NSDictionary class]] ||
        !clientName || ![clientName isKindOfClass:[NSString class]]) {
        NSLog(@"GNUStepMenuImporter: Invalid update payload (types) - windowId:%@ menuData:%@ clientName:%@", windowId, [menuData class], [clientName class]);
        return;
    }

    // Make thread-safe, non-proxy copies before hopping threads.
    NSNumber *safeWindowId = [windowId copy];
    NSString *safeClientName = [clientName copy];
    NSDictionary *safeMenuData = nil;

    @try {
        NSError *plistError = nil;
        NSData *plist = [NSPropertyListSerialization dataWithPropertyList:menuData
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:&plistError];
        if (plist && !plistError) {
            safeMenuData = [NSPropertyListSerialization propertyListWithData:plist
                                                                      options:NSPropertyListImmutable
                                                                       format:nil
                                                                        error:&plistError];
        }
        if (!safeMenuData || plistError) {
            safeMenuData = [menuData copy];
        }
    } @catch (NSException *ex) {
        NSLog(@"GNUStepMenuImporter: Failed to copy menuData safely: %@", ex);
        safeMenuData = [menuData copy];
    }

    // Bundle payload and dispatch to main thread; AppKit types must be created on main thread
    NSDictionary *payload = @{ @"windowId": safeWindowId ?: windowId,
                               @"menuData": safeMenuData ?: menuData,
                               @"clientName": safeClientName ?: clientName };
    if ([NSThread isMainThread]) {
        [self processMenuUpdateWithPayload:payload];
    } else {
        [self performSelectorOnMainThread:@selector(processMenuUpdateWithPayload:) withObject:payload waitUntilDone:NO];
    }
}

- (void)processMenuUpdateWithPayload:(NSDictionary *)payload
{
    NSNumber *windowId = payload[@"windowId"];
    NSDictionary *menuData = payload[@"menuData"];
    NSString *clientName = payload[@"clientName"];

    // Safety: ensure this runs on main thread
    if (![NSThread isMainThread]) {
        NSLog(@"GNUStepMenuImporter: WARNING - processMenuUpdateWithPayload executing off main thread!");
    }

    // Attempt to capture the incoming menuData to /tmp for reproduction if something goes wrong
    @try {
        NSData *json = [NSJSONSerialization dataWithJSONObject:menuData options:NSJSONWritingPrettyPrinted error:nil];
        if (json) {
            NSString *fname = [NSString stringWithFormat:@"/tmp/menu-update-%@-window-%@.json", [[NSUUID UUID] UUIDString], windowId];
            [json writeToFile:fname atomically:YES];
            NSLog(@"GNUStepMenuImporter: Saved incoming menuData to %@", fname);
        }
    } @catch (NSException *ex) {
        NSLog(@"GNUStepMenuImporter: Could not serialize menuData: %@", ex);
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    static NSTimeInterval startupTime = 0;
    if (startupTime == 0) {
        startupTime = now;
    }
    if ((now - startupTime) < 15.0 && [self.lastMenuDataByWindow objectForKey:windowId]) {
        NSLog(@"GNUStepMenuImporter: Suppressing repeated menu updates during startup for window %@", windowId);
        return;
    }

    NSNumber *lastTime = [self.lastMenuUpdateTimeByWindow objectForKey:windowId];
    if (lastTime && (now - [lastTime doubleValue]) < 1.0) {
        NSLog(@"GNUStepMenuImporter: Throttling rapid menu update for window %@", windowId);
        return;
    }

    NSDictionary *lastMenuData = [self.lastMenuDataByWindow objectForKey:windowId];
    if (lastMenuData && [lastMenuData isEqual:menuData]) {
        NSLog(@"GNUStepMenuImporter: Skipping duplicate menu update for window %@", windowId);
        return;
    }

    unsigned long windowValue = [windowId unsignedLongValue];
    // NSLog(@"GNUStepMenuImporter: Building menu for window %lu", windowValue);
    NSMenu *menu = [self menuFromData:menuData
                             windowId:windowValue
                           clientName:clientName
                                path:@[]];
    if (!menu) {
        NSLog(@"GNUStepMenuImporter: Failed to build menu for window %@", windowId);
        return;
    }

    // NSLog(@"GNUStepMenuImporter: Successfully built menu with %ld top-level items", (long)[menu numberOfItems]);
    self.menusByWindow[windowId] = menu;
    self.clientNamesByWindow[windowId] = clientName;
    self.lastMenuDataByWindow[windowId] = [menuData copy];
    self.lastMenuUpdateTimeByWindow[windowId] = @(now);
    // NSLog(@"GNUStepMenuImporter: Stored menu for window %@ (client: %@)", windowId, clientName);

    if (self.appMenuWidget) {
        NSDictionary *userInfo = @{@"windowId": windowId};
        [NSTimer scheduledTimerWithTimeInterval:0.15
                                         target:self
                                       selector:@selector(deferredMenuCheck:)
                                       userInfo:userInfo
                                        repeats:NO];
    }
}

- (oneway void)unregisterWindow:(NSNumber *)windowId
                       clientName:(NSString *)clientName
{
    (void)clientName;
    if (!windowId) {
        return;
    }

    [self unregisterWindow:[windowId unsignedLongValue]];
}

#pragma mark - Menu Construction

- (NSMenu *)menuFromData:(NSDictionary *)menuData
                windowId:(unsigned long)windowId
              clientName:(NSString *)clientName
                   path:(NSArray *)path
{
    // Defensive checks: limit recursion depth to avoid stack overflows and avoid bad types
    const NSUInteger MAX_DEPTH = 64;
    if ([path count] > MAX_DEPTH) {
        NSLog(@"GNUStepMenuImporter: menuFromData exceeded max depth (%lu) for window %lu", (unsigned long)MAX_DEPTH, windowId);
        return nil;
    }

    NSString *title = @"";
    id rawTitle = [menuData objectForKey:@"title"];
    if ([rawTitle isKindOfClass:[NSString class]]) {
        title = rawTitle;
    }

    NSArray *itemsData = [menuData objectForKey:@"items"];
    if (![itemsData isKindOfClass:[NSArray class]]) {
        itemsData = @[];
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    [menu setAutoenablesItems:NO];

    for (NSUInteger i = 0; i < [itemsData count]; i++) {
        id itemObj = [itemsData objectAtIndex:i];
        if (![itemObj isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *itemData = (NSDictionary *)itemObj;

        NSNumber *isSeparator = [itemData objectForKey:@"isSeparator"];
        if ([isSeparator boolValue]) {
            [menu addItem:[NSMenuItem separatorItem]];
            continue;
        }

        NSString *itemTitle = @"";
        id rawItemTitle = [itemData objectForKey:@"title"];
        if ([rawItemTitle isKindOfClass:[NSString class]]) {
            itemTitle = rawItemTitle;
        }
        NSString *keyEquivalent = @"";
        id rawKey = [itemData objectForKey:@"keyEquivalent"];
        if ([rawKey isKindOfClass:[NSString class]]) {
            keyEquivalent = rawKey;
        }

        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:itemTitle
                                                         action:nil
                                                  keyEquivalent:keyEquivalent];

        NSNumber *enabled = [itemData objectForKey:@"enabled"];
        NSNumber *state = [itemData objectForKey:@"state"];
        NSNumber *modifierMask = [itemData objectForKey:@"keyEquivalentModifierMask"];

        if ([enabled isKindOfClass:[NSNumber class]]) {
            [menuItem setEnabled:[enabled boolValue]];
        }
        if ([state isKindOfClass:[NSNumber class]]) {
            [menuItem setState:[state integerValue]];
        }
        if ([modifierMask isKindOfClass:[NSNumber class]]) {
            [menuItem setKeyEquivalentModifierMask:[modifierMask unsignedIntegerValue]];
        }

        id submenuData = [itemData objectForKey:@"submenu"];
        NSArray *itemPath = [path arrayByAddingObject:@(i)];

        if ([submenuData isKindOfClass:[NSDictionary class]]) {
            NSMenu *submenu = [self menuFromData:submenuData
                                         windowId:windowId
                                       clientName:clientName
                                            path:itemPath];
            if (submenu) {
                [menuItem setSubmenu:submenu];
            }
        } else {
            [menuItem setTarget:[GNUStepMenuActionHandler class]];
            [menuItem setAction:@selector(performMenuAction:)];

            // Build a safe representedObject using simple types
            NSArray *safeIndexPath = [NSArray arrayWithArray:itemPath];
            NSDictionary *repObj = @{ @"windowId": @(windowId),
                                      @"clientName": clientName ?: @"",
                                      @"indexPath": safeIndexPath };
            [menuItem setRepresentedObject:repObj];
        }

        [menu addItem:menuItem];
    }

    return menu;
}

- (void)deferredMenuCheck:(NSTimer *)timer
{
    NSDictionary *userInfo = [timer userInfo];
    NSNumber *windowIdNum = [userInfo objectForKey:@"windowId"];
    if (!windowIdNum) {
        return;
    }

    unsigned long windowId = [windowIdNum unsignedLongValue];

    if ([self hasMenuForWindow:windowId] && self.appMenuWidget) {
        [self.appMenuWidget checkAndDisplayMenuForNewlyRegisteredWindow:windowId];
    }
}

@end
