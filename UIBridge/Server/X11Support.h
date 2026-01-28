/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface X11Support : NSObject

// Discovery
+ (NSArray *)windowList;
+ (NSDictionary *)windowInfo:(unsigned long)xid;

// Input Simulation
+ (void)simulateMouseMoveTo:(NSPoint)point;
+ (void)simulateClick:(int)button; // 1=left, 2=middle, 3=right
+ (void)simulateKeyStroke:(NSString *)keyString;

@end
