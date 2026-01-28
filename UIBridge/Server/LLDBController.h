/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface LLDBController : NSObject

// Run a single command attached to a PID and return output
+ (NSString *)runCommand:(NSString *)command forPID:(int)pid;

@end
