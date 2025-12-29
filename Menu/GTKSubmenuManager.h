/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>

@class GNUDBusConnection;

// GTK Submenu Manager for handling lazy loading of GTK menu groups
@interface GTKSubmenuManager : NSObject

+ (void)setupSubmenu:(NSMenu *)submenu
         forMenuItem:(NSMenuItem *)menuItem
         serviceName:(NSString *)serviceName
            menuPath:(NSString *)menuPath
          actionPath:(NSString *)actionPath
      dbusConnection:(GNUDBusConnection *)dbusConnection
             groupId:(NSNumber *)groupId
            menuDict:(NSMutableDictionary *)menuDict;

+ (void)cleanup;

@end

// GTK Submenu Delegate for handling menu events
@interface GTKSubmenuDelegate : NSObject <NSMenuDelegate>

@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *menuPath;
@property (nonatomic, strong) NSString *actionPath;
@property (nonatomic, strong) GNUDBusConnection *dbusConnection;
@property (nonatomic, strong) NSNumber *groupId;
@property (nonatomic, strong) NSMutableDictionary *menuDict;

- (id)initWithServiceName:(NSString *)serviceName
                 menuPath:(NSString *)menuPath
               actionPath:(NSString *)actionPath
           dbusConnection:(GNUDBusConnection *)dbusConnection
                  groupId:(NSNumber *)groupId
                 menuDict:(NSMutableDictionary *)menuDict;

@end
