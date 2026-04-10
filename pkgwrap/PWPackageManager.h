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
- (BOOL)resolveDependenciesForLocalDeb:(NSString *)debPath;
- (BOOL)downloadPackages;
- (BOOL)extractPackages;
- (NSString *)findDesktopFile;
- (NSString *)rootPath;
- (void)setLocalRootPath:(NSString *)path;
- (NSArray *)resolvedPackageNames;
- (void)cleanup;

@end
