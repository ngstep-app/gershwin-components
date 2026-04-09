/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface PWBundleAssembler : NSObject
{
  NSString *_appName;
  NSString *_rootPath;
  NSString *_bundlePath;
  BOOL _verbose;
  BOOL _strip;
}

- (instancetype)initWithAppName:(NSString *)appName
                       rootPath:(NSString *)rootPath
                     bundlePath:(NSString *)bundlePath
                        verbose:(BOOL)verbose
                          strip:(BOOL)strip;
- (BOOL)assembleBundle;
- (BOOL)rewriteRPATH;
- (NSString *)findIconInRoot:(NSString *)iconName;

@end
