/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "UIBridgeAgent.h"
#import "../Common/UIBridgeProtocol.h"
#import <GNUstepBase/GSObjCRuntime.h>
#import <pthread.h>
#import <AppKit/AppKit.h>

@interface UIBridgeResultContainer : NSObject
@property (retain) id result;
@end
@implementation UIBridgeResultContainer
@synthesize result;
- (void)dealloc { [result release]; [super dealloc]; }
@end

@interface UIBridgeAgent () <UIBridgeProtocol>
@end

@implementation UIBridgeAgent {
    NSConnection *_connection;
}

#pragma mark - JSON safety helpers

- (id)jsonSafeObject:(id)obj {
    return [self jsonSafeObject:obj depth:0];
}

- (id)jsonSafeObject:(id)obj depth:(int)depth {
    if (depth > 5) return @"<Reached Max Depth>";
    if (!obj || obj == [NSNull null]) return [NSNull null];
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) return obj;
    if ([obj isKindOfClass:[NSData class]]) {
        // Try decode as UTF-8
        NSString *s = [[NSString alloc] initWithData:obj encoding:NSUTF8StringEncoding];
        if (s) {
            NSString *ret = [s copy];
            [s release];
            return ret;
        }
        // Fallback to base64 representation
        NSString *b64 = [obj base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"<NSData:%@>", b64];
    }
    if ([obj isKindOfClass:[NSAttributedString class]]) {
        return [(NSAttributedString *)obj string];
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:[(NSArray*)obj count]];
        for (id sub in (NSArray*)obj) {
            [arr addObject:[self jsonSafeObject:sub depth:depth + 1]];
        }
        return arr;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary*)obj count]];
        for (id key in (NSDictionary*)obj) {
            id val = [(NSDictionary*)obj objectForKey:key];
            NSString *k = [NSString stringWithFormat:@"%@", key];
            d[k] = [self jsonSafeObject:val depth:depth + 1];
        }
        return d;
    }
    // Fallback: string description
    return [NSString stringWithFormat:@"<%@: %@>", NSStringFromClass([obj class]), [obj description]];
}

#pragma mark - Initialization

static void *LiveLogThread(void *arg) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSLog(@"[UIBridge] Live Log thread started");
    UIBridgeAgent *agent = [UIBridgeAgent sharedAgent];
    
    while (1) {
        NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
        [NSThread sleepForTimeInterval:1.0];
        @try {
            // Snapshot the UI state autonomously. We use the modes that include modal dialogs.
            NSDictionary *tree = [agent runOnMainThread:@selector(_main_fullTreeForObject:) withObject:nil];
            if (tree) {
                NSString *json = [agent jsonStringForObject:tree];
                if (json) {
                    [json writeToFile:@"/tmp/uibridge_live_ui.json" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UIBridge] Exception in live log loop: %@", e);
        }
        [innerPool release];
    }
    [pool release];
    return NULL;
}

static void *RegistrationThread(void *arg) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSLog(@"[UIBridge] Registration thread started");
    
    UIBridgeAgent *agent = [UIBridgeAgent sharedAgent];
    
    // Poly indefinitely until successful
    while (![agent valueForKey:@"_connection"]) {
        [NSThread sleepForTimeInterval:1.0];
        [agent performSelectorOnMainThread:@selector(startConnection) 
                                                 withObject:nil 
                                              waitUntilDone:NO];
    }
    
    NSLog(@"[UIBridge] Background DO RunLoop starting...");
    
    // Spawn live log thread separately so it doesn't block the DO thread
    pthread_t logThread;
    pthread_create(&logThread, NULL, LiveLogThread, NULL);
    pthread_detach(logThread);

    while (1) {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:1.0];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
    }
    [pool release];
    return NULL;
}

+ (void)load {
    NSString *procName = [[NSProcessInfo processInfo] processName];
    char *target = getenv("UIBRIDGE_TARGET");
    NSString *targetName = target ? [NSString stringWithUTF8String:target] : @"TestApp";
    if ([procName isEqualToString:targetName]) {
        NSLog(@"[UIBridge] Match! Spawning registration thread for %@", targetName);
        pthread_t thread;
        pthread_create(&thread, NULL, RegistrationThread, NULL);
        pthread_detach(thread);
    }
}

+ (instancetype)sharedAgent {
    static UIBridgeAgent *agent = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        agent = [[UIBridgeAgent alloc] init];
    });
    return agent;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"[UIBridge] Agent Instance Initialized");
    }
    return self;
}

- (void)startConnection {
    if (_connection) return;
    int pid = [[NSProcessInfo processInfo] processIdentifier];
    NSString *connName = [NSString stringWithFormat:@"UIBridgeAgent%d", pid];
    _connection = [[NSConnection alloc] init];
    [_connection setRootObject:self];
    if ([_connection registerName:connName]) {
        NSLog(@"[UIBridge] Registered Distributed Object: %@", connName);
    } else {
        NSLog(@"[UIBridge] FAILED to register Distributed Object: %@", connName);
        [_connection release];
        _connection = nil;
    }
}

#pragma mark - Helper Methods

// Return nil for null objects, not string "null"
- (NSString *)objectIDForObject:(id)obj {
    if (!obj) return nil;
    return [NSString stringWithFormat:@"objc:%p", obj];
}

- (id)objectForID:(NSString *)objID {
    if (![objID hasPrefix:@"objc:"]) return nil;
    unsigned long long ptrVal;
    NSScanner *scanner = [NSScanner scannerWithString:[objID substringFromIndex:5]];
    if ([scanner scanHexLongLong:&ptrVal]) {
        return (__bridge id)(void *)ptrVal;
    }
    return nil;
}

// Return NSNull for null, and robustly handle serialization
- (id)serializeObject:(id)obj detailed:(BOOL)detailed {
    if (!obj || obj == [NSNull null]) return [NSNull null];
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj isKindOfClass:[NSNumber class]]) return obj;
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (id item in (NSArray *)obj) {
            [arr addObject:[self serializeObject:item detailed:NO]];
        }
        return arr;
    }
    
    NSString *className = @"Unknown";
    @try { className = NSStringFromClass([obj class]); } @catch (NSException *e) { }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"object_id"] = [self objectIDForObject:obj];
    dict[@"class"] = className;
    
    if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        NSRect frame = [view frame];
        dict[@"frame"] = NSStringFromRect(frame);
        dict[@"hidden"] = @([view isHidden]);
        
        // Always include title for buttons and text for text fields (not just detailed mode)
        if ([view respondsToSelector:@selector(title)]) {
            id title = [view performSelector:@selector(title)];
            if (title && ![title isEqual:@""]) dict[@"title"] = title;
        }
        if ([view isKindOfClass:[NSTextField class]]) {
            NSTextField *tf = (NSTextField *)view;
            dict[@"stringValue"] = [tf stringValue] ?: @"";
        }
        
        // Computed coordinates
        @try {
            if ([view window]) {
                NSRect winRect = [view convertRect:[view bounds] toView:nil];
                dict[@"window_frame"] = NSStringFromRect(winRect);
                
                NSRect screenRect = [[view window] convertRectToScreen:winRect];
                dict[@"screen_frame"] = NSStringFromRect(screenRect);
            }
        } @catch (NSException *e) { }
    }
    
    if (detailed && [obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        if ([view isKindOfClass:[NSControl class]]) {
            NSControl *control = (NSControl *)view;
            dict[@"enabled"] = @([control isEnabled]);
            dict[@"tag"] = @([control tag]);
        }
        
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            dict[@"keyEquivalent"] = [button keyEquivalent] ?: @"";
            dict[@"keyModifiers"] = @([button keyEquivalentModifierMask]);
        }

        NSMutableArray *subviews = [NSMutableArray array];
        for (NSView *sub in [view subviews]) {
            [subviews addObject:[self serializeObject:sub detailed:NO]];
        }
        dict[@"subviews"] = subviews;
        
        // Extra details for common view types
        if ([view respondsToSelector:@selector(string)]) {
             dict[@"string"] = [view performSelector:@selector(string)];
        } else if ([view respondsToSelector:@selector(stringValue)]) {
             dict[@"string"] = [view performSelector:@selector(stringValue)];
        }
        
        if ([view respondsToSelector:@selector(title)]) {
             dict[@"title"] = [view performSelector:@selector(title)];
        }
    }
    
    if (detailed && [obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;
        dict[@"title"] = [win title];
        dict[@"frame"] = NSStringFromRect([win frame]);
        dict[@"hidden"] = @(![win isVisible]);
        dict[@"contentView"] = [self serializeObject:[win contentView] detailed:NO];
    }
    if (detailed && [obj isKindOfClass:[NSApplication class]]) {
        NSApplication *app = (NSApplication *)obj;
        NSMutableArray *wins = [NSMutableArray array];
        for (NSWindow *win in [app windows]) {
            [wins addObject:[self serializeObject:win detailed:NO]];
        }
        dict[@"windows"] = wins;
    }
    if (detailed && [obj isKindOfClass:[NSMenu class]]) {
        NSMenu *menu = (NSMenu *)obj;
        NSMutableArray *items = [NSMutableArray array];
        for (NSMenuItem *item in [menu itemArray]) {
            [items addObject:[self serializeObject:item detailed:YES]];
        }
        dict[@"items"] = items;
        dict[@"title"] = [menu title];
    }
    if (detailed && [obj isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)obj;
        dict[@"title"] = [item title];
        dict[@"enabled"] = @([item isEnabled]);
        dict[@"hasSubmenu"] = @([item hasSubmenu]);
        // Add common menu item metadata
        if ([item respondsToSelector:@selector(action)]) {
            SEL sel = [item action];
            dict[@"action"] = sel ? NSStringFromSelector(sel) : @"";
        }
        if ([item respondsToSelector:@selector(keyEquivalent)]) {
            dict[@"keyEquivalent"] = [item keyEquivalent] ?: @"";
        }
        if ([item respondsToSelector:@selector(keyEquivalentModifierMask)]) {
            dict[@"keyModifiers"] = @([item keyEquivalentModifierMask]);
        }
        if ([item respondsToSelector:@selector(tag)]) {
            dict[@"tag"] = @([item tag]);
        }
        if ([item respondsToSelector:@selector(state)]) {
            dict[@"state"] = @([item state]);
        }
        if ([item respondsToSelector:@selector(representedObject)]) {
            id rep = [item representedObject];
            if (rep) dict[@"representedObject"] = [self jsonSafeObject:rep];
        }
        if ([item respondsToSelector:@selector(target)]) {
            id tgt = [item target];
            if (tgt) dict[@"target"] = [self objectIDForObject:tgt];
        }
        if ([item hasSubmenu]) {
            dict[@"submenu"] = [self serializeObject:[item submenu] detailed:NO];
        }
    }
    return dict;
}

- (id)serializeObject:(id)obj recursiveWithDepth:(int)depth {
    if (!obj || obj == [NSNull null] || depth < 0) return [NSNull null];
    
    // Base serialization with standard details
    NSMutableDictionary *dict = [[self serializeObject:obj detailed:YES] mutableCopy];
    
    if ([obj isKindOfClass:[NSApplication class]]) {
        NSApplication *app = (NSApplication *)obj;
        NSMutableArray *fullWins = [NSMutableArray array];
        for (NSWindow *win in [app windows]) {
            [fullWins addObject:[self serializeObject:win recursiveWithDepth:depth - 1]];
        }
        dict[@"windows"] = fullWins;
    }

    if ([obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        NSMutableArray *fullSubviews = [NSMutableArray array];
        for (NSView *sub in [view subviews]) {
            [fullSubviews addObject:[self serializeObject:sub recursiveWithDepth:depth - 1]];
        }
        dict[@"subviews"] = fullSubviews;
    }
    
    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;
        id cv = [win contentView];
        if (cv) {
            dict[@"contentView"] = [self serializeObject:cv recursiveWithDepth:depth - 1];
        }
    }

    if ([obj isKindOfClass:[NSMenu class]]) {
        NSMenu *menu = (NSMenu *)obj;
        NSMutableArray *itemsArr = [NSMutableArray array];
        for (NSMenuItem *item in [menu itemArray]) {
            [itemsArr addObject:[self serializeObject:item recursiveWithDepth:depth - 1]];
        }
        dict[@"items"] = itemsArr;
    }
    if ([obj isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)obj;
        if ([item hasSubmenu]) {
            dict[@"submenu"] = [self serializeObject:[item submenu] recursiveWithDepth:depth - 1];
        }
    }

    return [dict autorelease];
}

// List all menus in the app (main menu and submenus)
- (bycopy NSArray *)listMenus {
    // Ensure menu inspection happens on the main thread to safely access AppKit objects
    id res = [self runOnMainThread:@selector(_main_listMenus:) withObject:nil];
    return [self jsonSafeObject:res];
}

- (void)_main_listMenus:(NSDictionary *)params {
    UIBridgeResultContainer *container = params[@"container"];
    NSMutableArray *menus = [NSMutableArray array];
    NSMenu *mainMenu = [NSApp mainMenu];
    if (mainMenu) {
        NSLog(@"[UIBridge] Traversing menus starting from %@", mainMenu);
        // Iterative traversal to avoid stack overflow and cycles
        NSMutableSet *visited = [NSMutableSet setWithObject:[NSValue valueWithPointer:mainMenu]];
        NSMutableArray *queue = [NSMutableArray arrayWithObject:mainMenu];
        int count = 0;
        while ([queue count] > 0 && count < 200) {
            NSMenu *menu = [[queue firstObject] retain];
            [queue removeObjectAtIndex:0];
            count++;
            
            NSLog(@"[UIBridge] Processing menu %d: %@", count, [menu title]);
            
            // Serialize menu
            NSMutableDictionary *menuDict = [[self serializeObject:menu detailed:YES] mutableCopy];
            // Traverse items for submenus
            NSMutableArray *submenuIDs = [NSMutableArray array];
            for (NSMenuItem *item in [menu itemArray]) {
                if ([item hasSubmenu]) {
                    NSMenu *submenu = [item submenu];
                    if (submenu) {
                        NSValue *val = [NSValue valueWithPointer:submenu];
                        if (![visited containsObject:val]) {
                            [visited addObject:val];
                            [queue addObject:submenu];
                        }
                        [submenuIDs addObject:[self objectIDForObject:submenu]];
                    }
                }
            }
            menuDict[@"submenus"] = submenuIDs;
            [menus addObject:menuDict];
            [menuDict release];
            [menu release];
        }
        if (count >= 200) {
            NSLog(@"[UIBridge] WARNING: Reached menu traversal limit (200)");
        }
    }
    NSLog(@"[UIBridge] Menu traversal complete. Found %lu menus.", (unsigned long)[menus count]);
    [container setResult:menus];
}

- (bycopy NSString *)listMenusJSON {
    return [self jsonStringForObject:[self listMenus]];
}

// Get details for a menu item
- (NSDictionary *)menuItemDetails:(id)item {
    if (![item isKindOfClass:[NSMenuItem class]]) return @{};
    return [self serializeObject:item detailed:YES];
}

- (void)_deferredInvoke:(NSMenuItem *)item {
    [NSApp sendAction:[item action] to:[item target] from:item];
}

- (void)_main_invokeMenuItem:(NSDictionary *)params {
    UIBridgeResultContainer *container = params[@"container"];
    NSMenuItem *item = params[@"arg"];
    
    SEL action = [item action];
    id target = [item target];
    
    // Use dispatch_async to ensure we return the DO result to the server immediately,
    // rather than waiting for the entire modal session (like an alert) to finish.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp sendAction:action to:target from:item];
    });
    
    [container setResult:@YES];
}

// Invoke a menu item by objectID
- (BOOL)invokeMenuItem:(NSString *)objectID {
    id obj = [self objectForID:objectID];
    if ([obj isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)obj;
        if ([item isEnabled]) {
                SEL action = [item action];
                NSString *selName = NSStringFromSelector(action);
                // For quit actions, don't wait for execution because the process will exit
                // and break the DO connection before we can return.
                if (action == @selector(terminate:) || [selName containsString:@"terminate"] || [[item title] isEqualToString:@"Quit"]) {
                    NSLog(@"[UIBridge] Quit/Terminate detected (%@), using deferred invoke", selName);
                    // Use a small delay even on main thread to be extra safe
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [NSApp sendAction:action to:[item target] from:item];
                    });
                    return YES;
                }
            id res = [self runOnMainThread:@selector(_main_invokeMenuItem:) withObject:item];
            return [res boolValue];
        }
    }
    return NO;
}


// Always return valid JSON, never string "null"
- (NSString *)jsonStringForObject:(id)obj {
    id safeObj = obj ?: [NSNull null];
    @try {
        NSData *data = [NSJSONSerialization dataWithJSONObject:safeObj options:0 error:nil];
        if (data) {
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    } @catch (NSException *e) {
        NSLog(@"[UIBridge] JSON Serialization failed: %@", e);
    }
    return @"null";
}

#pragma mark - UI Thread Execution

- (id)runOnMainThread:(SEL)sel withObject:(id)arg {
    UIBridgeResultContainer *container = [[UIBridgeResultContainer alloc] init];
    NSDictionary *params = arg ? @{@"container": container, @"arg": arg} : @{@"container": container};
    
    // We must include NSModalPanelRunLoopMode and GSRunLoopModalMode so that 
    // requests are processed even while the application is showing a modal 
    // dialog (like a save alert) or tracking a menu.
    NSArray *modes = @[NSDefaultRunLoopMode, NSModalPanelRunLoopMode, 
                      NSEventTrackingRunLoopMode, @"GSRunLoopModalMode"];
    
    [self performSelector:sel 
                 onThread:[NSThread mainThread] 
               withObject:params 
            waitUntilDone:YES 
                    modes:modes];

    id res = [[container result] retain];
    [container release];
    return [res autorelease];
}

- (void)_main_rootObjects:(NSDictionary *)params {
    UIBridgeResultContainer *container = params[@"container"];
    id winList = [NSApp windows];
    NSDictionary *dict = @{
        @"NSApp": [self objectIDForObject:NSApp],
        @"windows": [self serializeObject:winList detailed:NO]
    };
    NSLog(@"[UIBridge] _main_rootObjects returning object of class: %@", NSStringFromClass([dict class]));
    [container setResult:dict];
}

- (void)_main_detailsForObject:(NSDictionary *)params {
    UIBridgeResultContainer *container = params[@"container"];
    id obj = [self objectForID:params[@"arg"]];
    id ser = [self serializeObject:obj detailed:YES];
    NSLog(@"[UIBridge] _main_detailsForObject returning class: %@", NSStringFromClass([ser class]));
    [container setResult:ser];
}

- (void)_main_fullTreeForObject:(NSDictionary *)params {
    UIBridgeResultContainer *container = params[@"container"];
    id obj = [self objectForID:params[@"arg"]];
    if (!obj) obj = NSApp;
    id ser = [self serializeObject:obj recursiveWithDepth:15];
    NSLog(@"[UIBridge] _main_fullTreeForObject returning class: %@", NSStringFromClass([ser class]));
    [container setResult:ser];
}

- (void)_main_invokeSelector:(NSDictionary *)params {
    UIBridgeResultContainer *container = params[@"container"];
    NSDictionary *callParams = params[@"arg"];
    id obj = [self objectForID:callParams[@"object_id"]];
    if (!obj) {
        [container setResult:@{ @"error": @{ @"code": @-32000, @"message": @"Object not found" } }];
        return;
    }
    SEL sel = NSSelectorFromString(callParams[@"selector"]);
    if (![obj respondsToSelector:sel]) {
        [container setResult:@{ @"error": @{ @"code": @-32601, @"message": @"Selector not found" } }];
        return;
    }

    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];

    NSArray *args = callParams[@"args"];
    if (args && [args isKindOfClass:[NSArray class]]) {
        for (NSUInteger i = 0; i < [args count]; i++) {
            if (i + 2 >= [sig numberOfArguments]) break;
            id arg = args[i];
            if (arg == [NSNull null]) arg = nil;
            [inv setArgument:&arg atIndex:i + 2];
        }
    }

    @try {
        [inv invoke];
    } @catch (NSException *e) {
        [container setResult:@{ @"error": @{ @"code": @-32001, @"message": [e description] } }];
        return;
    }

    id result = nil;
    if ([sig methodReturnLength] > 0) {
        const char *retType = [sig methodReturnType];
        if (retType[0] == '@' || retType[0] == '#') {
            [inv getReturnValue:&result];
        } else {
            result = @"OK";
        }
    } else {
        result = @"OK";
    }

    id serres = [self serializeObject:result detailed:NO];
    [container setResult:serres];
}

#pragma mark - UIBridgeProtocol

- (bycopy NSString *)rootObjectsJSON {
    return [self jsonStringForObject:[self runOnMainThread:@selector(_main_rootObjects:) withObject:nil]];
}

- (bycopy NSString *)detailsForObjectJSON:(NSString *)objID {
    return [self jsonStringForObject:[self runOnMainThread:@selector(_main_detailsForObject:) withObject:objID]];
}

- (bycopy NSString *)fullTreeForObjectJSON:(NSString *)objID {
     return [self jsonStringForObject:[self runOnMainThread:@selector(_main_fullTreeForObject:) withObject:objID]];
}

- (bycopy NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
    NSDictionary *p = @{@"selector": selectorName, @"object_id": objID, @"args": args};
    return [self jsonStringForObject:[self runOnMainThread:@selector(_main_invokeSelector:) withObject:p]];
}

// Typed (non-JSON) variants — return JSON-compatible Foundation objects directly to avoid NSData confusion
- (bycopy id)rootObjects {
    id raw = [self runOnMainThread:@selector(_main_rootObjects:) withObject:nil];
    return [self jsonSafeObject:raw];
}

- (bycopy id)detailsForObject:(NSString *)objID {
    id raw = [self runOnMainThread:@selector(_main_detailsForObject:) withObject:objID];
    return [self jsonSafeObject:raw];
}

- (bycopy id)fullTreeForObject:(NSString *)objID {
    id raw = [self runOnMainThread:@selector(_main_fullTreeForObject:) withObject:objID];
    return [self jsonSafeObject:raw];
}

- (bycopy id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
    NSDictionary *p = @{@"selector": selectorName, @"object_id": objID, @"args": args};
    id raw = [self runOnMainThread:@selector(_main_invokeSelector:) withObject:p];
    return [self jsonSafeObject:raw];
}

@end
