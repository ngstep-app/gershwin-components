/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface PWLauncherGenerator : NSObject

+ (BOOL)generateLauncherAtPath:(NSString *)launcherPath
                       appName:(NSString *)appName
                      mainExec:(NSString *)mainExec
                 chromiumBased:(BOOL)chromiumBased
                 needsRedirect:(BOOL)needsRedirect
                    launchArgs:(NSString *)launchArgs;

@end
