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
            [arr addObject:[self jsonSafeObject:sub]];
        }
        return arr;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary*)obj count]];
        for (id key in (NSDictionary*)obj) {
            id val = [(NSDictionary*)obj objectForKey:key];
            NSString *k = [NSString stringWithFormat:@"%@", key];
            d[k] = [self jsonSafeObject:val];
        }
        return d;
    }
    // Fallback: string description
    return [NSString stringWithFormat:@"<%@: %@>", NSStringFromClass([obj class]), [obj description]];
}

#pragma mark - Initialization

static void *RegistrationThread(void *arg) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSLog(@"[UIBridge] Registration thread started");
    
    // Poly indefinitely until successful
    while (![[UIBridgeAgent sharedAgent] valueForKey:@"_connection"]) {
        [NSThread sleepForTimeInterval:1.0];
        [[UIBridgeAgent sharedAgent] performSelectorOnMainThread:@selector(startConnection) 
                                                 withObject:nil 
                                              waitUntilDone:NO];
    }
    
    NSLog(@"[UIBridge] Background RunLoop starting...");
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
    
    if (detailed && [obj isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)obj;
        dict[@"frame"] = NSStringFromRect([view frame]);
        NSMutableArray *subviews = [NSMutableArray array];
        for (NSView *sub in [view subviews]) {
            [subviews addObject:[self serializeObject:sub detailed:NO]];
        }
        dict[@"subviews"] = subviews;
    }
    
    if (detailed && [obj isKindOfClass:[NSWindow class]]) {
        NSWindow *win = (NSWindow *)obj;
        dict[@"title"] = [win title];
        dict[@"contentView"] = [self serializeObject:[win contentView] detailed:NO];
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
        if ([item hasSubmenu]) {
            dict[@"submenu"] = [self serializeObject:[item submenu] detailed:YES];
        }
    }
    return dict;
}

// List all menus in the app (main menu and submenus)
- (NSArray *)listMenus {
    NSMutableArray *menus = [NSMutableArray array];
    NSMenu *mainMenu = [NSApp mainMenu];
    if (mainMenu) {
        [menus addObject:[self serializeObject:mainMenu detailed:YES]];
    }
    return menus;
}

- (NSString *)listMenusJSON {
    return [self jsonStringForObject:[self listMenus]];
}

// Get details for a menu item
- (NSDictionary *)menuItemDetails:(id)item {
    if (![item isKindOfClass:[NSMenuItem class]]) return @{};
    return [self serializeObject:item detailed:YES];
}

// Invoke a menu item by objectID
- (BOOL)invokeMenuItem:(NSString *)objectID {
    id obj = [self objectForID:objectID];
    if ([obj isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)obj;
        if ([item isEnabled]) {
            [NSApp sendAction:[item action] to:[item target] from:item];
            return YES;
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
    [self performSelectorOnMainThread:sel withObject:params waitUntilDone:YES];
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
    id result = nil; 
    NSLog(@"[UIBridge] _main_invokeSelector will call selector %@ on object %@", callParams[@"selector"], obj);
    @try {
        NSArray *args = callParams[@"args"];
        if ([args count] == 0) {
            result = [obj performSelector:sel];
        } else {
            result = [obj performSelector:sel withObject:args[0]];
        }
    } @catch (NSException *e) {
        [container setResult:@{ @"error": @{ @"code": @-32001, @"message": [e description] } }];
        return;
    }
    id serres = [self serializeObject:result detailed:NO];
    NSLog(@"[UIBridge] _main_invokeSelector returning class: %@", NSStringFromClass([serres class]));
    [container setResult:serres];
}

#pragma mark - UIBridgeProtocol

- (NSString *)rootObjectsJSON {
    return [self jsonStringForObject:[self runOnMainThread:@selector(_main_rootObjects:) withObject:nil]];
}

- (NSString *)detailsForObjectJSON:(NSString *)objID {
    return [self jsonStringForObject:[self runOnMainThread:@selector(_main_detailsForObject:) withObject:objID]];
}

- (NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
    NSDictionary *p = @{@"selector": selectorName, @"object_id": objID, @"args": args};
    return [self jsonStringForObject:[self runOnMainThread:@selector(_main_invokeSelector:) withObject:p]];
}

// Typed (non-JSON) variants — return JSON-compatible Foundation objects directly to avoid NSData confusion
- (id)rootObjects {
    id raw = [self runOnMainThread:@selector(_main_rootObjects:) withObject:nil];
    return [self jsonSafeObject:raw];
}

- (id)detailsForObject:(NSString *)objID {
    id raw = [self runOnMainThread:@selector(_main_detailsForObject:) withObject:objID];
    return [self jsonSafeObject:raw];
}

- (id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
    NSDictionary *p = @{@"selector": selectorName, @"object_id": objID, @"args": args};
    id raw = [self runOnMainThread:@selector(_main_invokeSelector:) withObject:p];
    return [self jsonSafeObject:raw];
}

@end
