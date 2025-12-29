/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class GNUDBusConnection;

// MARK: - DBusSubmenuDelegate Interface

@interface DBusSubmenuDelegate : NSObject <NSMenuDelegate>

@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *objectPath;
@property (nonatomic, strong) GNUDBusConnection *dbusConnection;
@property (nonatomic, strong) NSNumber *itemId;

- (id)initWithServiceName:(NSString *)serviceName 
               objectPath:(NSString *)objectPath 
           dbusConnection:(GNUDBusConnection *)dbusConnection 
                   itemId:(NSNumber *)itemId;
- (void)refreshSubmenu:(NSMenu *)submenu;

@end

// MARK: - DBusSubmenuManager Interface

@interface DBusSubmenuManager : NSObject

// Setup a submenu with lazy loading delegate
+ (void)setupSubmenu:(NSMenu *)submenu
         forMenuItem:(NSMenuItem *)menuItem
         serviceName:(NSString *)serviceName
          objectPath:(NSString *)objectPath
      dbusConnection:(GNUDBusConnection *)dbusConnection
              itemId:(NSNumber *)itemId;

// Cleanup method
+ (void)cleanup;

@end
