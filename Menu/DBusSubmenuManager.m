/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "DBusSubmenuManager.h"
#import "DBusConnection.h"
#import "DBusMenuParser.h"

// Static variables for submenu management
static NSMutableDictionary *submenuDelegates = nil;
static NSMutableSet *refreshedByAboutToShow = nil;

@implementation DBusSubmenuManager

+ (void)initialize
{
    if (self == [DBusSubmenuManager class]) {
        submenuDelegates = [[NSMutableDictionary alloc] init];
        refreshedByAboutToShow = [[NSMutableSet alloc] init];
    }
}

+ (void)setupSubmenu:(NSMenu *)submenu
         forMenuItem:(NSMenuItem *)menuItem
         serviceName:(NSString *)serviceName
          objectPath:(NSString *)objectPath
      dbusConnection:(GNUDBusConnection *)dbusConnection
              itemId:(NSNumber *)itemId
{
    if (!submenu || !menuItem || !serviceName || !objectPath || !dbusConnection || !itemId) {
        NSDebugLog(@"DBusSubmenuManager: ERROR: Missing required parameters for submenu setup");
        return;
    }
    
    NSDebugLog(@"DBusSubmenuManager: ===== SETTING UP SUBMENU DELEGATE =====");
    NSDebugLog(@"DBusSubmenuManager: Setting up submenu delegate for item ID %@", itemId);
    NSDebugLog(@"DBusSubmenuManager: Menu item title: '%@'", [menuItem title]);
    NSDebugLog(@"DBusSubmenuManager: Service: %@", serviceName);
    NSDebugLog(@"DBusSubmenuManager: Object path: %@", objectPath);
    NSDebugLog(@"DBusSubmenuManager: DBus connection: %@", dbusConnection ? @"available" : @"nil");
    NSDebugLog(@"DBusSubmenuManager: Submenu has %lu existing items", (unsigned long)[[submenu itemArray] count]);
    
    // Set up submenu delegate for AboutToShow handling
    DBusSubmenuDelegate *delegate = [[DBusSubmenuDelegate alloc] 
                                   initWithServiceName:serviceName 
                                            objectPath:objectPath 
                                        dbusConnection:dbusConnection 
                                                itemId:itemId];
    
    [submenu setDelegate:delegate];
    NSDebugLog(@"DBusSubmenuManager: Successfully set delegate for submenu");
    
    // Store the delegate to prevent it from being deallocated
    NSString *submenuKey = [NSString stringWithFormat:@"submenu_%p", submenu];
    [submenuDelegates setObject:delegate forKey:submenuKey];
    
    NSDebugLog(@"DBusSubmenuManager: Stored delegate with key '%@' for lazy loading (itemId=%@)", submenuKey, itemId);
    
    // Attach the submenu to the menu item
    [menuItem setSubmenu:submenu];
    
    // Verify the submenu was set
    NSMenu *verifySubmenu = [menuItem submenu];
    if (verifySubmenu) {
        NSDebugLog(@"DBusSubmenuManager: SUCCESS: Submenu verified - attached submenu has %lu items", 
              (unsigned long)[[verifySubmenu itemArray] count]);
        NSDebugLog(@"DBusSubmenuManager: Submenu delegate: %@", [verifySubmenu delegate]);
    } else {
        NSDebugLog(@"DBusSubmenuManager: ERROR: setSubmenu failed - menu item has no submenu!");
    }
    NSDebugLog(@"DBusSubmenuManager: ===== SUBMENU DELEGATE SETUP COMPLETE =====");
}

+ (void)cleanupDelegatesForService:(NSString *)serviceName
{
    if (!serviceName) {
        return;
    }
    
    NSDebugLog(@"DBusSubmenuManager: Cleaning up delegates for service: %@", serviceName);
    
    NSMutableArray *keysToRemove = [NSMutableArray array];
    
    for (NSString *key in [submenuDelegates allKeys]) {
        DBusSubmenuDelegate *delegate = [submenuDelegates objectForKey:key];
        if (delegate && [[delegate serviceName] isEqualToString:serviceName]) {
            [keysToRemove addObject:key];
        }
    }
    
    for (NSString *key in keysToRemove) {
        [submenuDelegates removeObjectForKey:key];
    }
    
    if ([keysToRemove count] > 0) {
        NSDebugLog(@"DBusSubmenuManager: Removed %lu stale delegates for service: %@", 
              (unsigned long)[keysToRemove count], serviceName);
    }
}

+ (void)cleanup
{
    NSDebugLog(@"DBusSubmenuManager: Performing cleanup...");
    [submenuDelegates removeAllObjects];
    [refreshedByAboutToShow removeAllObjects];
}

@end

// MARK: - DBusSubmenuDelegate Implementation

@implementation DBusSubmenuDelegate

- (id)initWithServiceName:(NSString *)serviceName 
               objectPath:(NSString *)objectPath 
           dbusConnection:(GNUDBusConnection *)dbusConnection 
                   itemId:(NSNumber *)itemId
{
    self = [super init];
    if (self) {
        NSDebugLog(@"DBusSubmenuDelegate: ===== INITIALIZING DELEGATE =====");
        NSDebugLog(@"DBusSubmenuDelegate: Creating delegate for item ID %@", itemId);
        NSDebugLog(@"DBusSubmenuDelegate: Service: %@", serviceName);
        NSDebugLog(@"DBusSubmenuDelegate: Object path: %@", objectPath);
        NSDebugLog(@"DBusSubmenuDelegate: DBus connection: %@", dbusConnection ? @"available" : @"nil");
        
        self.serviceName = serviceName;
        self.objectPath = objectPath;
        self.dbusConnection = dbusConnection; // Weak reference
        self.itemId = itemId;
        
        NSDebugLog(@"DBusSubmenuDelegate: Delegate initialization complete for item ID %@", self.itemId);
        NSDebugLog(@"DBusSubmenuDelegate: ===== DELEGATE READY FOR ABOUTTOSHOW =====");
    }
    return self;
}

- (void)menuWillOpen:(NSMenu *)menu
{
    NSDebugLog(@"DBusSubmenuDelegate: ===== MENU WILL OPEN =====");
    NSDebugLog(@"DBusSubmenuDelegate: menuWillOpen called for menu: '%@'", [menu title] ?: @"(no title)");
    NSDebugLog(@"DBusSubmenuDelegate: Menu object: %@", menu);
    NSDebugLog(@"DBusSubmenuDelegate: Menu has %lu items currently", (unsigned long)[[menu itemArray] count]);
    NSDebugLog(@"DBusSubmenuDelegate: Delegate item ID: %@", self.itemId);
    NSDebugLog(@"DBusSubmenuDelegate: Delegate service: %@", self.serviceName);
    NSDebugLog(@"DBusSubmenuDelegate: Delegate path: %@", self.objectPath);
    NSDebugLog(@"DBusSubmenuDelegate: Delegate connection: %@", self.dbusConnection ? @"available" : @"nil");
    
    if (!self.serviceName || !self.objectPath || !self.dbusConnection || !self.itemId) {
        NSDebugLog(@"DBusSubmenuDelegate: ERROR: Missing DBus info, cannot call AboutToShow");
        NSDebugLog(@"DBusSubmenuDelegate:   serviceName: %@", self.serviceName ?: @"MISSING");
        NSDebugLog(@"DBusSubmenuDelegate:   objectPath: %@", self.objectPath ?: @"MISSING");
        NSDebugLog(@"DBusSubmenuDelegate:   dbusConnection: %@", self.dbusConnection ? @"available" : @"MISSING");
        NSDebugLog(@"DBusSubmenuDelegate:   itemId: %@", self.itemId ?: @"MISSING");
        return;
    }
    
    // Check if this menu was already refreshed by AboutToShow to avoid duplicate calls
    NSString *itemIdKey = [NSString stringWithFormat:@"refreshed_%@", self.itemId];
    if ([refreshedByAboutToShow containsObject:itemIdKey]) {
        NSDebugLog(@"DBusSubmenuDelegate: Menu already refreshed by AboutToShow, skipping duplicate refresh");
        [refreshedByAboutToShow removeObject:itemIdKey];
        return;
    }
    
    NSDebugLog(@"DBusSubmenuDelegate: ===== CALLING ABOUTTOSHOW =====");
    NSDebugLog(@"DBusSubmenuDelegate: Calling AboutToShow for menu item ID %@ (service=%@, path=%@)", 
          self.itemId, self.serviceName, self.objectPath);
    
    // Call AboutToShow method to notify the application that this submenu is about to be displayed
    NSArray *arguments = [NSArray arrayWithObjects:self.itemId, nil];
    NSDebugLog(@"DBusSubmenuDelegate: AboutToShow arguments: %@", arguments);
    
    NSDebugLog(@"DBusSubmenuDelegate: Making DBus call...");
    id result = [self.dbusConnection callMethod:@"AboutToShow"
                                  onService:self.serviceName
                                 objectPath:self.objectPath
                                  interface:@"com.canonical.dbusmenu"
                                  arguments:arguments];
    
    NSDebugLog(@"DBusSubmenuDelegate: AboutToShow call completed");
    
    if (result) {
        NSDebugLog(@"DBusSubmenuDelegate: AboutToShow call succeeded, result: %@ (%@)", result, [result class]);
        
        // The result should be a boolean indicating whether the menu structure has changed
        BOOL needsRefresh = NO;
        if ([result isKindOfClass:[NSNumber class]]) {
            needsRefresh = [result boolValue];
            NSDebugLog(@"DBusSubmenuDelegate: Result is NSNumber, needsRefresh: %@", needsRefresh ? @"YES" : @"NO");
        } else if ([result isKindOfClass:[NSArray class]] && [result count] > 0) {
            // Some implementations might return an array with the boolean as first element
            id firstElement = [result objectAtIndex:0];
            NSDebugLog(@"DBusSubmenuDelegate: Result is array, first element: %@ (%@)", firstElement, [firstElement class]);
            if ([firstElement isKindOfClass:[NSNumber class]]) {
                needsRefresh = [firstElement boolValue];
                NSDebugLog(@"DBusSubmenuDelegate: First element is NSNumber, needsRefresh: %@", needsRefresh ? @"YES" : @"NO");
            }
        } else {
            NSDebugLog(@"DBusSubmenuDelegate: Unexpected result type: %@", [result class]);
        }
        
        NSDebugLog(@"DBusSubmenuDelegate: Final needsRefresh decision: %@", needsRefresh ? @"YES" : @"NO");
        NSDebugLog(@"DBusSubmenuDelegate: Current menu item count: %lu", (unsigned long)[[menu itemArray] count]);
        
        if (needsRefresh || [[menu itemArray] count] == 0) {
            NSDebugLog(@"DBusSubmenuDelegate: ===== MENU UPDATE NEEDED, REFRESHING SUBMENU =====");
            [refreshedByAboutToShow addObject:itemIdKey];
            [self refreshSubmenu:menu];
        } else {
            NSDebugLog(@"DBusSubmenuDelegate: No menu update needed, using existing content");
        }
    } else {
        NSDebugLog(@"DBusSubmenuDelegate: ERROR: AboutToShow call failed or returned nil");
        // If AboutToShow fails, still try to refresh if the menu is empty
        if ([[menu itemArray] count] == 0) {
            NSDebugLog(@"DBusSubmenuDelegate: Menu is empty, attempting refresh anyway");
            [self refreshSubmenu:menu];
        } else {
            NSDebugLog(@"DBusSubmenuDelegate: Menu has content (%lu items), not refreshing after failed AboutToShow", 
                  (unsigned long)[[menu itemArray] count]);
        }
    }
    
    NSDebugLog(@"DBusSubmenuDelegate: ===== MENU WILL OPEN COMPLETE =====");
}

- (void)menuDidClose:(NSMenu *)menu
{
    NSDebugLog(@"DBusSubmenuDelegate: menuDidClose called for menu: %@", [menu title]);
    // Nothing special needed on close for now
}

- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item
{
    // Called when an item is about to be highlighted
    // This could be used for additional dynamic loading if needed
}

- (NSRect)confinementRectForMenu:(NSMenu *)menu onScreen:(NSScreen *)screen
{
    // Return the screen frame - let the menu display anywhere on screen
    return [screen frame];
}

- (void)refreshSubmenu:(NSMenu *)submenu
{
    NSDebugLog(@"DBusSubmenuDelegate: ===== REFRESHING SUBMENU CONTENT =====");
    NSDebugLog(@"DBusSubmenuDelegate: Refreshing submenu content for item ID %@", self.itemId);
    NSDebugLog(@"DBusSubmenuDelegate: Submenu object: %@", submenu);
    NSDebugLog(@"DBusSubmenuDelegate: Submenu title: '%@'", [submenu title] ?: @"(no title)");
    NSDebugLog(@"DBusSubmenuDelegate: Submenu current item count: %lu", (unsigned long)[[submenu itemArray] count]);
    NSDebugLog(@"DBusSubmenuDelegate: Service: %@", self.serviceName);
    NSDebugLog(@"DBusSubmenuDelegate: Object path: %@", self.objectPath);
    NSDebugLog(@"DBusSubmenuDelegate: DBus connection: %@", self.dbusConnection);
    
    // Call GetLayout specifically for this submenu item with optimized property filtering
    // Include shortcut-related properties so keyboard shortcuts are displayed in menus
    NSArray *essentialProperties = [NSArray arrayWithObjects:
                                    @"label", @"enabled", @"visible", @"type",
                                    @"shortcut", @"accel", @"accelerator", @"key-binding",
                                    @"children-display", nil];
    NSArray *arguments = [NSArray arrayWithObjects:
                         self.itemId,                   // parentId (this submenu's ID)
                         [NSNumber numberWithInt:2], // recursionDepth (2 levels for lazy loading)
                         essentialProperties,       // propertyNames (including shortcuts for display)
                         nil];
    
    NSDebugLog(@"DBusSubmenuDelegate: Calling GetLayout with optimized arguments: %@", arguments);
    NSDebugLog(@"DBusSubmenuDelegate: GetLayout call details:");
    NSDebugLog(@"DBusSubmenuDelegate:   method: GetLayout");
    NSDebugLog(@"DBusSubmenuDelegate:   service: %@", self.serviceName);
    NSDebugLog(@"DBusSubmenuDelegate:   path: %@", self.objectPath);
    NSDebugLog(@"DBusSubmenuDelegate:   interface: com.canonical.dbusmenu");
    NSDebugLog(@"DBusSubmenuDelegate:   using filtered properties (including shortcuts) for performance");
    
    id result = [self.dbusConnection callMethod:@"GetLayout"
                                  onService:self.serviceName
                                 objectPath:self.objectPath
                                  interface:@"com.canonical.dbusmenu"
                                  arguments:arguments];
    
    NSDebugLog(@"DBusSubmenuDelegate: GetLayout call completed");
    
    if (!result) {
        NSDebugLog(@"DBusSubmenuDelegate: ERROR: Failed to refresh submenu layout from %@%@ - result is nil", self.serviceName, self.objectPath);
        return;
    }
    
    NSDebugLog(@"DBusSubmenuDelegate: Received updated submenu layout: %@ (%@)", result, [result class]);
    
    // Parse the result and update the submenu
    if ([result isKindOfClass:[NSArray class]] && [result count] >= 2) {
        NSArray *resultArray = (NSArray *)result;
        NSDebugLog(@"DBusSubmenuDelegate: Result is array with %lu elements", (unsigned long)[resultArray count]);
        
        // Extract the layout item from the result (skip revision number)
        NSNumber *revision = [resultArray objectAtIndex:0];
        id layoutItem = [resultArray objectAtIndex:1];
        
        NSDebugLog(@"DBusSubmenuDelegate: GetLayout revision: %@", revision);
        NSDebugLog(@"DBusSubmenuDelegate: GetLayout layout item: %@ (%@)", layoutItem, [layoutItem class]);
        
        // Parse the layout item to get the children
        if ([layoutItem isKindOfClass:[NSArray class]] && [layoutItem count] >= 3) {
            NSArray *layoutArray = (NSArray *)layoutItem;
            NSDebugLog(@"DBusSubmenuDelegate: Layout item is array with %lu elements", (unsigned long)[layoutArray count]);
            
            NSNumber *layoutItemId = [layoutArray objectAtIndex:0];
            id layoutProperties = [layoutArray objectAtIndex:1];
            id childrenObj = [layoutArray objectAtIndex:2];
            
            NSDebugLog(@"DBusSubmenuDelegate: Layout item ID: %@", layoutItemId);
            NSDebugLog(@"DBusSubmenuDelegate: Layout properties: %@ (%@)", layoutProperties, [layoutProperties class]);
            NSDebugLog(@"DBusSubmenuDelegate: Children object: %@ (%@)", childrenObj, [childrenObj class]);
            
            NSArray *children = nil;
            if ([childrenObj isKindOfClass:[NSArray class]]) {
                children = (NSArray *)childrenObj;
            } else {
                NSDebugLog(@"DBusSubmenuDelegate: ERROR: Children object is not an array: %@ (%@)", 
                      childrenObj, [childrenObj class]);
                children = [NSArray array];
            }
            
            NSDebugLog(@"DBusSubmenuDelegate: ===== UPDATING SUBMENU WITH %lu CHILDREN =====", (unsigned long)[children count]);
            
            // Store current items count for comparison
            NSUInteger oldItemCount = [[submenu itemArray] count];
            NSDebugLog(@"DBusSubmenuDelegate: Clearing %lu existing submenu items", oldItemCount);
            
            // Clear existing submenu items
            [submenu removeAllItems];
            NSDebugLog(@"DBusSubmenuDelegate: Submenu cleared, now has %lu items", (unsigned long)[[submenu itemArray] count]);
            
            // Create menu items from the updated children
            NSUInteger newItemCount = 0;
            NSUInteger failedItems = 0;
            for (NSUInteger childIndex = 0; childIndex < [children count]; childIndex++) {
                id childItem = [children objectAtIndex:childIndex];
                NSDebugLog(@"DBusSubmenuDelegate: Processing refreshed child %lu: %@ (%@)", 
                      childIndex, childItem, [childItem class]);
                
                NSMenuItem *childMenuItem = [DBusMenuParser createMenuItemFromLayoutItem:childItem 
                                                                             serviceName:self.serviceName 
                                                                              objectPath:self.objectPath 
                                                                          dbusConnection:self.dbusConnection];
                if (childMenuItem) {
                    [submenu addItem:childMenuItem];
                    newItemCount++;
                    NSDebugLog(@"DBusSubmenuDelegate: Successfully added refreshed child menu item '%@' (total: %lu)", 
                          [childMenuItem title], newItemCount);
                } else {
                    failedItems++;
                    NSDebugLog(@"DBusSubmenuDelegate: ERROR: Failed to create child menu item %lu from layout", childIndex);
                }
            }
            
            NSDebugLog(@"DBusSubmenuDelegate: ===== SUBMENU REFRESH SUMMARY =====");
            NSDebugLog(@"DBusSubmenuDelegate: %lu old items -> %lu new items", oldItemCount, newItemCount);
            NSDebugLog(@"DBusSubmenuDelegate: %lu items created successfully, %lu failed", newItemCount, failedItems);
            NSDebugLog(@"DBusSubmenuDelegate: Final submenu item count: %lu", (unsigned long)[[submenu itemArray] count]);
            
            // Log the final menu items
            if (newItemCount > 0) {
                NSDebugLog(@"DBusSubmenuDelegate: Final submenu items:");
                NSArray *finalItems = [submenu itemArray];
                for (NSUInteger i = 0; i < [finalItems count]; i++) {
                    NSMenuItem *item = [finalItems objectAtIndex:i];
                    NSDebugLog(@"DBusSubmenuDelegate:   [%lu] '%@' (submenu: %@)", 
                          i, [item title], [item submenu] ? @"YES" : @"NO");
                }
            }
        } else {
            NSDebugLog(@"DBusSubmenuDelegate: ERROR: Invalid layout item structure: %@ (count: %lu)", 
                  layoutItem, [layoutItem isKindOfClass:[NSArray class]] ? (unsigned long)[layoutItem count] : 0UL);
        }
    } else {
        NSDebugLog(@"DBusSubmenuDelegate: ERROR: Invalid layout result for submenu refresh: %@ (count: %lu)", 
              result, [result isKindOfClass:[NSArray class]] ? (unsigned long)[result count] : 0UL);
    }
    
    NSDebugLog(@"DBusSubmenuDelegate: ===== SUBMENU REFRESH COMPLETE =====");
}

@end
