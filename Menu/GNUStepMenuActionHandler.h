/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface GNUStepMenuActionHandler : NSObject
+ (void)performMenuAction:(id)sender;

// Returns a cached (or newly created) NSConnection to the given client.
// The connection is shared across action and validation calls.
+ (NSConnection *)cachedConnectionForClient:(NSString *)clientName;
@end
