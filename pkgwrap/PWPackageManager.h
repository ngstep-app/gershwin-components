/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface PWPackageManager : NSObject
{
  NSString *_packageName;
  NSString *_rootPath;
  NSMutableSet *_skipPackages;
  NSString *_arch;
  BOOL _verbose;
}

- (instancetype)initWithPackage:(NSString *)package verbose:(BOOL)verbose;
- (BOOL)loadSkipList:(NSString *)path;
- (BOOL)setupStagingRoot;
- (BOOL)resolveDependencies;
- (BOOL)downloadPackages;
- (BOOL)extractPackages;
- (NSString *)findDesktopFile;
- (NSString *)rootPath;
- (NSArray *)resolvedPackageNames;
- (void)cleanup;

@end
