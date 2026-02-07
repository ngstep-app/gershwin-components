/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

 #import <Foundation/Foundation.h>

@class DesktopFileParser;

@interface GWBundleCreator : NSObject

- (BOOL)createBundleFromDesktopFile:(NSString *)desktopPath
                           outputDir:(NSString *)outputDir;
- (BOOL)createBundleFromCommand:(NSString *)command
                        appName:(NSString *)appName
                        iconPath:(NSString *)iconPath
                        outputDir:(NSString *)outputDir;
- (BOOL)createBundleStructure:(NSString *)appPath
                  withAppName:(NSString *)appName;
- (BOOL)createInfoPlist:(NSString *)appPath
            desktopInfo:(DesktopFileParser *)parser
                appName:(NSString *)appName
              execPath:(NSString *)execPath
          iconFilename:(NSString *)iconFilename;
- (BOOL)createLauncherScript:(NSString *)appPath
                 execCommand:(NSString *)command
                 iconPath:(NSString *)iconPath
                 scriptName:(NSString *)scriptName;
- (NSString *)resolveIconPath:(NSString *)iconName;
- (NSString *)copyIconToBundle:(NSString *)iconPath
                      toBundleResources:(NSString *)resourcesPath
                      appName:(NSString *)appName;

@end
