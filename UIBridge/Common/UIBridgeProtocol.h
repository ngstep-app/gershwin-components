/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@protocol UIBridgeProtocol <NSObject>

- (NSString *)rootObjectsJSON;
- (NSString *)detailsForObjectJSON:(NSString *)objID;
- (NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args;

// Typed variants
- (id)rootObjects;
- (id)detailsForObject:(NSString *)objID;
- (id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args;

- (NSArray *)listMenus;
// JSON string variant used by some server implementations
- (NSString *)listMenusJSON;
- (BOOL)invokeMenuItem:(NSString *)objID;

@end
