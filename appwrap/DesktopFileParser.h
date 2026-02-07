/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface DesktopFileParser : NSObject
{
  NSMutableDictionary *entries;
}

- (id)initWithFile:(NSString *)path;
- (NSString *)stringForKey:(NSString *)key;
- (NSArray *)arrayForKey:(NSString *)key;
- (BOOL)parseFile:(NSString *)path;

@end
