/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "GNUStepMenuImporter.h"
#import "GNUStepMenuActionHandler.h"
#import "AppMenuWidget.h"
#import "MenuUtils.h"
#import <Foundation/NSConnection.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <dispatch/dispatch.h>

static NSString *const kGershwinMenuServerName = @"org.gnustep.Gershwin.MenuServer";

@interface GNUStepMenuImporter ()
@property (nonatomic, strong) NSMutableDictionary *menusByWindow;
@property (nonatomic, strong) NSMutableDictionary *clientNamesByWindow;
@property (nonatomic, strong) NSMutableDictionary *lastMenuDataByWindow;
@property (nonatomic, strong) NSMutableDictionary *lastMenuUpdateTimeByWindow;
@property (nonatomic, strong) NSConnection *menuServerConnection;
// Workaround: retry attempts when registering DO server fails
@property (nonatomic) NSInteger registerRetryAttempts;
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
    if (self.menuServerConnection && [self.menuServerConnection isValid]) {
        return YES;
    }

    NSConnection *connection = [NSConnection defaultConnection];
    [connection setRootObject:self];

    BOOL registered = NO;
    @try {
        registered = [connection registerName:kGershwinMenuServerName];
    } @catch (NSException *e) {
        registered = NO;
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception while registering server name: %@", e);
    }

    // Keep the connection reference even if registration failed. We'll retry and use
    // a polling fallback so menus can still be imported when we can't register the DO server.
    self.menuServerConnection = connection;

    if (!registered) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Failed to register GNUstep menu server name %@", kGershwinMenuServerName);
        // Schedule retries with exponential backoff and proactively scan clients as a fallback
        [self scheduleRegisterRetryWithAttempt:1];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scanForExistingMenuServices];
        });
        return NO;
    }

    // Safely add receive port to run loop in common modes only (avoid adding many specific modes)
    NSPort *receivePort = [connection receivePort];
    if (receivePort && [receivePort isKindOfClass:[NSPort class]]) {
        @try {
            [[NSRunLoop currentRunLoop] addPort:receivePort forMode:NSRunLoopCommonModes];
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception adding receive port to run loop: %@", e);
        }
    }

    NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Registered GNUstep menu server as %@ with receive port added to run loop", kGershwinMenuServerName);

    // Immediately attempt to import menus for already-mapped windows (Desktop, etc.)
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scanForExistingMenuServices];
    });

    return YES;
}

#pragma mark - Register retry fallback

- (void)scheduleRegisterRetryWithAttempt:(NSInteger)attempt
{
    const NSInteger MAX_ATTEMPTS = 6;
    if (attempt > MAX_ATTEMPTS) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Abandoning register retries after %ld attempts", (long)attempt - 1);
        return;
    }

    NSTimeInterval delay = MIN(30.0, pow(2.0, attempt));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self attemptRegisterRetry:attempt];
    });
}

- (void)attemptRegisterRetry:(NSInteger)attempt
{
    @try {
        // If already have a valid connection, avoid re-registering
        if (self.menuServerConnection && [self.menuServerConnection isValid]) {
            // It may still not be registered; try a lightweight register to be safe
            NSConnection *conn = self.menuServerConnection;
            BOOL registered = NO;
            @try {
                registered = [conn registerName:kGershwinMenuServerName];
            } @catch (NSException *e) {
                registered = NO;
            }
            if (registered) {
                // Add receive port on main thread
                NSPort *receivePort = [conn receivePort];
                if (receivePort && [receivePort isKindOfClass:[NSPort class]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            [[NSRunLoop currentRunLoop] addPort:receivePort forMode:NSRunLoopCommonModes];
                        } @catch (NSException *ex) {
                            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception adding receive port during retry: %@", ex);
                        }
                    });
                }
                NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Successfully registered GNUstep menu server after %ld attempts", (long)attempt);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self scanForExistingMenuServices];
                });
                return;
            }
        }

        NSConnection *connection = self.menuServerConnection ?: [NSConnection defaultConnection];
        [connection setRootObject:self];

        BOOL registered = NO;
        @try {
            registered = [connection registerName:kGershwinMenuServerName];
        } @catch (NSException *e) {
            registered = NO;
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception while retrying register: %@", e);
        }

        if (registered) {
            self.menuServerConnection = connection;
            NSPort *receivePort = [connection receivePort];
            if (receivePort && [receivePort isKindOfClass:[NSPort class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        [[NSRunLoop currentRunLoop] addPort:receivePort forMode:NSRunLoopCommonModes];
                    } @catch (NSException *e) {
                        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception adding receive port during retry: %@", e);
                    }
                });
            }
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Successfully registered GNUstep menu server after %ld attempts", (long)attempt);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self scanForExistingMenuServices];
            });
            return;
        } else {
            [self scheduleRegisterRetryWithAttempt:attempt + 1];
        }
    } @catch (NSException *e) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception in attemptRegisterRetry: %@", e);
        [self scheduleRegisterRetryWithAttempt:attempt + 1];
    }
}

- (BOOL)hasMenuForWindow:(unsigned long)windowId
{
    NSNumber *key = [NSNumber numberWithUnsignedLong:windowId];
    if ([self.menusByWindow objectForKey:key]) {
        return YES;
    }

    /* Also check with alternative NSNumber representations —
     * Distributed Objects may store the key with a different
     * underlying numeric type. */
    for (NSNumber *storedKey in self.menusByWindow) {
        if ([storedKey unsignedLongValue] == windowId) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Found menu for window %lu via numeric comparison (key type mismatch: stored=%@ lookup=%@)",
                  windowId, [storedKey className], [key className]);
            /* Re-store under the canonical key so future lookups are fast */
            self.menusByWindow[key] = self.menusByWindow[storedKey];
            self.clientNamesByWindow[key] = self.clientNamesByWindow[storedKey];
            return YES;
        }
    }
    
    // Proactively probe the client for this window if we don't have a menu
    // This handles the case where a new GNUstep app window appears but hasn't pushed its menu yet
    pid_t pid = [MenuUtils getWindowPID:windowId];
    if (pid != 0) {
        NSString *clientName = [NSString stringWithFormat:@"org.gnustep.Gershwin.MenuClient.%d", pid];
        
        // Log the probe attempt to help debug why Processes.app might fail
        // Using static to avoid spamming the log every frame/check
        static unsigned long lastProbedWindow = 0;
        if (lastProbedWindow != windowId) {
             NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Probing GNUstep client %@ for window %lu", clientName, windowId);
             lastProbedWindow = windowId;
        }

        // Use background queue to avoid blocking main thread during window switch
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                NSConnection *connection = [NSConnection connectionWithRegisteredName:clientName host:nil];
                if (connection && [connection isValid]) {
                    id proxy = [connection rootProxy];
                    if (proxy) {
                        // Log success if we connect
                        static unsigned long lastConnectedWindow = 0;
                        if (lastConnectedWindow != windowId) {
                             NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Connected to %@ for window %lu", clientName, windowId);
                             lastConnectedWindow = windowId;
                        }

                        @try {
                            [proxy setProtocolForProxy:@protocol(GSGNUstepMenuClient)];
                        } @catch (NSException *e) {
                            // Protocol might not be known or needed depending on runtime
                        }
                        
                        // Request update
                        [(id)proxy requestMenuUpdateForWindow:@(windowId)];
                    } else {
                        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Failed to get root proxy for client %@", clientName);
                    }
                } else {
                    // Only log connection failure once per window to avoid spam
                    // (Scanning logic might retry, so we want to see it at least once)
                     static unsigned long lastFailedWindow = 0;
                     if (lastFailedWindow != windowId) {
                          NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Failed to connect to client name %@", clientName);
                          lastFailedWindow = windowId;
                     }
                }
            } @catch (NSException *e) {
                NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception probing client %@: %@", clientName, e);
            }
        });
    } else {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Could not determine PID for window %lu", windowId);
    }
    
    return NO;
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
    [self.lastMenuDataByWindow removeObjectForKey:windowKey];
    [self.lastMenuUpdateTimeByWindow removeObjectForKey:windowKey];

    if (self.appMenuWidget && self.appMenuWidget.currentWindowId == windowId) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Current menu window %lu unregistered - refreshing menu", windowId);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.appMenuWidget updateForActiveWindow];
        });
    }
}

- (void)scanForExistingMenuServices
{
    NSDebugLog(@"GNUStepMenuImporter: scanForExistingMenuServices STARTED");

    // Get all visible windows; attempt to contact any GNUstep clients that may be
    // associated with those windows by PID. If we can reach a client, ask it to
    // push its current menu for that window via requestMenuUpdateForWindow:
    NSArray *allWindows = [MenuUtils getAllWindows];
    if (!allWindows || [allWindows count] == 0) {
        NSDebugLog(@"GNUStepMenuImporter: No windows to scan");
        return;
    }

    int found = 0;
    for (NSNumber *windowNum in allWindows) {
        unsigned long windowId = [windowNum unsignedLongValue];

        // Skip if we already have a menu for this window
        if ([self.menusByWindow objectForKey:windowNum]) {
            continue;
        }

        // Try to determine PID for the window
        pid_t pid = [MenuUtils getWindowPID:windowId];
        if (pid == 0) {
            // Not all windows provide PID - skip
            continue;
        }

        NSString *clientName = [NSString stringWithFormat:@"org.gnustep.Gershwin.MenuClient.%d", pid];
        NSDebugLog(@"GNUStepMenuImporter: Found window %@ (pid: %d) - probing client %@", windowNum, pid, clientName);

        @try {
            NSConnection *connection = [NSConnection connectionWithRegisteredName:clientName host:nil];
            if (connection && [connection isValid]) {
                id proxy = [connection rootProxy];
                if (proxy) {
                    // Tell the proxy which protocol it implements so selectors are known
                    @try {
                        [proxy setProtocolForProxy:@protocol(GSGNUstepMenuClient)];
                    } @catch (NSException *e) {
                        NSDebugLog(@"GNUStepMenuImporter: Failed to set protocol for proxy of %@: %@", clientName, e);
                    }

                    // Ask client to send its menu for this window
                    @try {
                        NSDebugLog(@"GNUStepMenuImporter: Requesting menu update from client %@ for window %lu", clientName, windowId);
                        [(id)proxy requestMenuUpdateForWindow:@(windowId)];
                        found++;
                    } @catch (NSException *e) {
                        NSDebugLog(@"GNUStepMenuImporter: Exception requesting menu update from %@: %@", clientName, e);
                    }
                }
            }
        }
        @catch (NSException *ex) {
            NSDebugLog(@"GNUStepMenuImporter: Exception probing client %@: %@", clientName, ex);
        }
    }

    if (found == 0) {
        NSDebugLog(@"GNUStepMenuImporter: No GNUstep menu clients discovered during scan.");
        // Do NOT reschedule automatically. Scans are triggered by window-change events
        // and registration retries, so there is no need for an unbounded polling loop.
    } else {
        NSDebugLog(@"GNUStepMenuImporter: Requested menu updates from %d clients", found);
    }

    NSDebugLog(@"GNUStepMenuImporter: scanForExistingMenuServices COMPLETED");
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
    // IMMEDIATE PROTECTION: Wrap entire method in try/catch to handle corrupted DO proxies
    // The objc_retainAutoreleasedReturnValue crash happens at the runtime level and may not be catchable
    // as an NSException, so we need to prevent any proxy access that could trigger it
    @try {
        // First check if parameters are distributed objects proxies and validate their connections
        BOOL hasInvalidProxies = NO;
        
        @try {
            if (windowId && [(id)windowId isProxy]) {
                NSConnection *conn = [(NSDistantObject *)windowId connectionForProxy];
                if (!conn || [conn isValid] == NO) {
                    NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: windowId proxy has invalid connection");
                    hasInvalidProxies = YES;
                }
            }
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception validating windowId proxy: %@", e);
            hasInvalidProxies = YES;
        }
        
        @try {
            if (menuData && [(id)menuData isProxy]) {
                NSConnection *conn = [(NSDistantObject *)menuData connectionForProxy];
                if (!conn || [conn isValid] == NO) {
                    NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: menuData proxy has invalid connection");
                    hasInvalidProxies = YES;
                }
            }
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception validating menuData proxy: %@", e);
            hasInvalidProxies = YES;
        }
        
        @try {
            if (clientName && [(id)clientName isProxy]) {
                NSConnection *conn = [(NSDistantObject *)clientName connectionForProxy];
                if (!conn || [conn isValid] == NO) {
                    NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: clientName proxy has invalid connection");
                    hasInvalidProxies = YES;
                }
            }
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception validating clientName proxy: %@", e);
            hasInvalidProxies = YES;
        }
        
        if (hasInvalidProxies) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Rejecting updateMenuForWindow call due to invalid proxy connections");
            return;
        }

        // Defensive checks for remote calls - wrapped in try/catch for DO safety
        @try {
            if (!windowId || ![windowId isKindOfClass:[NSNumber class]] ||
                !menuData || ![menuData isKindOfClass:[NSDictionary class]] ||
                !clientName || ![clientName isKindOfClass:[NSString class]]) {
                NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Invalid update payload (types) - windowId:%@ menuData:%@ clientName:%@", windowId, [menuData class], [clientName class]);
                return;
            }
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception in parameter validation: %@", e);
            return;
        }

        // Make thread-safe, non-proxy copies before hopping threads.
        NSNumber *safeWindowId = nil;
        @try {
            safeWindowId = [windowId copy];
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception copying windowId: %@", e);
            return;
        }
        
        NSString *safeClientName = nil;
        @try {
            safeClientName = [clientName copy];
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception copying clientName: %@", e);
            return;
        }
        
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
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Failed to copy menuData safely: %@", ex);
            @try {
                safeMenuData = [menuData copy];
            } @catch (NSException *e2) {
                NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception copying menuData as fallback: %@", e2);
                return;
            }
        }

        // Bundle payload and dispatch to main thread; AppKit types must be created on main thread
        NSDictionary *payload = @{ @"windowId": safeWindowId ?: windowId,
                                   @"menuData": safeMenuData ?: menuData,
                                   @"clientName": safeClientName ?: clientName };
        if ([NSThread isMainThread]) {
            [self processMenuUpdateWithPayload:payload];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self processMenuUpdateWithPayload:payload];
            });
        }
    }
    @catch (NSException *exception) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception in updateMenuForWindow:menuData:clientName: - %@", exception);
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: This is likely a distributed objects issue with corrupted proxies");
        // Don't re-throw - just log and return to prevent crashes
    }
}

- (void)processMenuUpdateWithPayload:(NSDictionary *)payload
{
    NSNumber *windowId = payload[@"windowId"];
    NSDictionary *menuData = payload[@"menuData"];
    NSString *clientName = payload[@"clientName"];

    // Safety: ensure this runs on main thread
    if (![NSThread isMainThread]) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: WARNING - processMenuUpdateWithPayload executing off main thread!");
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    static NSTimeInterval startupTime = 0;
    if (startupTime == 0) {
        startupTime = now;
    }
    if ((now - startupTime) < 15.0 && [self.lastMenuDataByWindow objectForKey:windowId]) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Suppressing repeated menu updates during startup for window %@", windowId);
        return;
    }

    NSNumber *lastTime = [self.lastMenuUpdateTimeByWindow objectForKey:windowId];
    if (lastTime && (now - [lastTime doubleValue]) < 1.0) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Throttling rapid menu update for window %@", windowId);
        return;
    }

    NSDictionary *lastMenuData = [self.lastMenuDataByWindow objectForKey:windowId];
    if (lastMenuData && [lastMenuData isEqual:menuData]) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Skipping duplicate menu update for window %@", windowId);
        return;
    }

    unsigned long windowValue = [windowId unsignedLongValue];
    // NSLog(@"GNUStepMenuImporter: Building menu for window %lu", windowValue);
    NSMenu *menu = [self menuFromData:menuData
                             windowId:windowValue
                           clientName:clientName
                                path:@[]];
    if (!menu) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Failed to build menu for window %@", windowId);
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
    @try {
        // Check if parameters are distributed objects proxies and validate their connections
        BOOL hasInvalidProxies = NO;
        
        @try {
            if (windowId && [(id)windowId isProxy]) {
                NSConnection *conn = [(NSDistantObject *)windowId connectionForProxy];
                if (!conn || [conn isValid] == NO) {
                    NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: unregisterWindow windowId proxy has invalid connection");
                    hasInvalidProxies = YES;
                }
            }
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception validating unregisterWindow windowId proxy: %@", e);
            hasInvalidProxies = YES;
        }
        
        @try {
            if (clientName && [(id)clientName isProxy]) {
                NSConnection *conn = [(NSDistantObject *)clientName connectionForProxy];
                if (!conn || [conn isValid] == NO) {
                    NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: unregisterWindow clientName proxy has invalid connection");
                    hasInvalidProxies = YES;
                }
            }
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception validating unregisterWindow clientName proxy: %@", e);
            hasInvalidProxies = YES;
        }
        
        if (hasInvalidProxies) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Rejecting unregisterWindow call due to invalid proxy connections");
            return;
        }

        @try {
            (void)clientName;
            if (!windowId) {
                return;
            }

            [self unregisterWindow:[windowId unsignedLongValue]];
        } @catch (NSException *e) {
            NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception in unregisterWindow parameter processing: %@", e);
            return;
        }
    }
    @catch (NSException *exception) {
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: Exception in unregisterWindow:clientName: - %@", exception);
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: This is likely a distributed objects issue with corrupted proxies");
        // Don't re-throw - just log and return to prevent crashes
    }
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
        NSDebugLLog(@"gwcomp", @"GNUStepMenuImporter: menuFromData exceeded max depth (%lu) for window %lu", (unsigned long)MAX_DEPTH, windowId);
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
