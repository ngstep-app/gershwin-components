/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface GWUtils : NSObject

+ (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message;
+ (NSString *)sanitizeFileName:(NSString *)name;
+ (NSString *)sanitizeExecCommand:(NSString *)command;
+ (NSString *)findExecutableInPath:(NSString *)name;
+ (BOOL)rasterizeSVG:(NSString *)svgPath toPNG:(NSString *)pngPath size:(int)size;
+ (NSArray *)extensionsForMIMEType:(NSString *)mimeType;

@end
