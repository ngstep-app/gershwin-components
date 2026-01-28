/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface UIBridgeAgent : NSObject

+ (instancetype)sharedAgent;

// Menu helpers
- (NSArray *)listMenus;
- (NSDictionary *)menuItemDetails:(id)item;
- (BOOL)invokeMenuItem:(NSString *)objectID;

@end
