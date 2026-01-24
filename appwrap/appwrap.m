/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


/*
 * appwrap - Create GNUstep application bundles from .desktop files or raw commands
 * 
 * Usage: appwrap [OPTIONS] /path/to/application.desktop [output_dir]
 *        appwrap [OPTIONS] -c|--command "command to run" [-i|--icon /path/to/icon.png] [output_dir]
 * 
 * Options:
 *   -c, --command  Provide a command line to execute instead of a .desktop file
 *   -i, --icon     Path to an icon file to use (overrides .desktop Icon resolution)
 *   -f, --force    Overwrite existing app bundle without asking
 *   -h, --help     Show this help message
 *
 * This tool takes a freedesktop .desktop file (default) or a command line and creates
 * a GNUstep application bundle that can be launched from the system.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>

// Show an NSAlert if possible; otherwise log and print to stderr.
// If APPWRAP_NO_GUI=1 or we're not attached to a TTY, avoid modal alerts to allow
// batch, non-interactive usage.
static void ShowErrorAlert(NSString *title, NSString *message)
{
  NSLog(@"%@: %@", title, message);
  fprintf(stderr, "%s\n", [message UTF8String]);

  const char *noGui = getenv("APPWRAP_NO_GUI");
  if (noGui && strcmp(noGui, "1") == 0)
    return;

  if (!isatty(fileno(stderr)))
    return;

  Class NSAlertClass = NSClassFromString(@"NSAlert");
  if (NSAlertClass)
    {
      NSAlert *alert = [[NSAlertClass alloc] init];
      [alert setMessageText:title];
      [alert setInformativeText:message];
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
      [alert release];
    }
}


// Desktop file parser
@interface DesktopFileParser : NSObject
{
  NSMutableDictionary *entries;
}

- (id)initWithFile:(NSString *)path;
- (NSString *)stringForKey:(NSString *)key;
- (NSArray *)arrayForKey:(NSString *)key;
- (BOOL)parseFile:(NSString *)path;

@end

@implementation DesktopFileParser

- (id)init
{
  self = [super init];
  if (self)
    {
      entries = [[NSMutableDictionary alloc] init];
    }
  return self;
}

- (id)initWithFile:(NSString *)path
{
  self = [self init];
  if (self && ![self parseFile:path])
    {
      [self release];
      return nil;
    }
  return self;
}

- (BOOL)parseFile:(NSString *)path
{
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path 
                                                  encoding:NSUTF8StringEncoding 
                                                     error:&error];
  if (!content)
    {
      NSString *msg = [NSString stringWithFormat:@"Error reading file: %@", [error localizedDescription]];
      ShowErrorAlert(@"Error reading desktop file", msg);
      return NO;
    }

  NSArray *lines = [content componentsSeparatedByString:@"\n"];
  NSString *currentSection = nil;

  for (NSString *line in lines)
    {
      // Skip empty lines and comments
      NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceCharacterSet]];
      if ([trimmed length] == 0 || [trimmed hasPrefix:@"#"])
        continue;

      // Handle sections
      if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"])
        {
          currentSection = [trimmed substringWithRange:NSMakeRange(1, [trimmed length] - 2)];
          continue;
        }

      // Skip lines that are not in Desktop Entry section
      if (![currentSection isEqualToString:@"Desktop Entry"])
        continue;

      // Parse key=value pairs
      NSArray *parts = [trimmed componentsSeparatedByString:@"="];
      if ([parts count] >= 2)
        {
          NSString *key = [[parts objectAtIndex:0] stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
          NSString *value = [[parts objectAtIndex:1] stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
          
          // Handle values with '=' in them
          if ([parts count] > 2)
            {
              NSMutableArray *valueParts = [NSMutableArray arrayWithArray:
                                            [parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)]];
              value = [valueParts componentsJoinedByString:@"="];
              value = [value stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
            }

          [entries setObject:value forKey:key];
        }
    }

  return YES;
}

- (NSString *)stringForKey:(NSString *)key
{
  return [entries objectForKey:key];
}

- (NSArray *)arrayForKey:(NSString *)key
{
  NSString *value = [entries objectForKey:key];
  if (!value)
    return nil;
  
  // Handle semicolon-separated values (freedesktop standard)
  return [value componentsSeparatedByString:@";"];
}

- (void)dealloc
{
  [entries release];
  [super dealloc];
}

@end

// App bundle creator
@interface AppBundleCreator : NSObject

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

// Sanitize freedesktop Exec field by removing field codes so the POSIX script
// contains a plain executable command without % codes.
- (NSString *)sanitizeExecCommand:(NSString *)command;

// Return an array of file extensions (without dot) for a given MIME type when possible.
- (NSArray *)extensionsForMIMEType:(NSString *)mimeType;

// Find an executable in PATH (returns full path) or nil
- (NSString *)findExecutableInPath:(NSString *)name;

// Rasterize an SVG file to PNG using GNUstep drawing APIs or external tools as fallback
- (BOOL)rasterizeSVG:(NSString *)svgPath toPNG:(NSString *)pngPath size:(int)size;

// Sanitize a string for use as a filename: remove control chars and slash, collapse whitespace
- (NSString *)sanitizeFileName:(NSString *)name;

// Create a composite document icon by using the generic GNUstep document picture and overlaying
// a small version of the app icon. Returns the filename (basename) created in resourcesPath or nil.
- (NSString *)createDocumentIconWithAppName:(NSString *)appName
                              resourcesPath:(NSString *)resourcesPath
                           appIconFilename:(NSString *)appIconFilename
                                    mimeType:(NSString *)mimeType
                                    typeName:(NSString *)typeName
                                        size:(int)size;

@end

@implementation AppBundleCreator

- (NSString *)sanitizeFileName:(NSString *)name
{
  if (!name) return @"";
  // Replace path-separators with dashes
  NSString *s = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];

  // Replace control characters with spaces
  NSCharacterSet *ctrl = [NSCharacterSet controlCharacterSet];
  NSMutableString *out = [NSMutableString stringWithCapacity:[s length]];
  for (NSUInteger i = 0; i < [s length]; i++)
    {
      unichar c = [s characterAtIndex:i];
      if ([ctrl characterIsMember:c])
        {
          [out appendString:@" "];
        }
      else
        {
          [out appendFormat:@"%C", c];
        }
    }

  // Collapse whitespace and newlines to single spaces
  NSArray *parts = [out componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSPredicate *notEmpty = [NSPredicate predicateWithFormat:@"length > 0"];
  NSArray *filtered = [parts filteredArrayUsingPredicate:notEmpty];
  NSString *result = [filtered componentsJoinedByString:@" "];
  // Trim leading/trailing whitespace
  result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

  if ([result length] == 0)
    return @"application";
  return result;
}

- (NSString *)createDocumentIconWithAppName:(NSString *)appName
                              resourcesPath:(NSString *)resourcesPath
                           appIconFilename:(NSString *)appIconFilename
                                    mimeType:(NSString *)mimeType
                                    typeName:(NSString *)typeName
                                        size:(int)size
{
  if (!appName || !resourcesPath) return nil;

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *sanApp = [self sanitizeFileName:appName];
  NSString *sanType = [self sanitizeFileName:typeName ? typeName : mimeType];

  NSString *docFilename = [NSString stringWithFormat:@"%@-doc-%@.%@", sanApp, sanType, @"png"];
  NSString *docPath = [resourcesPath stringByAppendingPathComponent:docFilename];

  // If it already exists, reuse it
  if ([fm fileExistsAtPath:docPath])
    {
      NSLog(@"Document icon already exists: %@", docPath);
      return docFilename;
    }

  // Load app icon from bundle resources
  NSString *appIconFull = nil;
  if (appIconFilename && [appIconFilename length] > 0)
    appIconFull = [resourcesPath stringByAppendingPathComponent:appIconFilename];

  NSImage *appIcon = nil;
  BOOL appIconFileExists = NO;
  if (appIconFull && [fm fileExistsAtPath:appIconFull])
    {
      appIconFileExists = YES;
      appIcon = [[NSImage alloc] initWithContentsOfFile:appIconFull];
    }
  NSLog(@"createDocumentIcon: appIconFull=%@ exists=%d appIconLoaded=%d", appIconFull, appIconFileExists, (appIcon != nil));

  // Try to load generic document icon from the theme / GNUstep images
  NSImage *docBase = [NSImage imageNamed:@"NSDocument"];
  if (!docBase) docBase = [NSImage imageNamed:@"common_document"];

  // Fallback: we'll draw a simple rounded-rect document shape if no base image

  // Create alpha-enabled bitmap
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                   pixelsWide:size
                                                                   pixelsHigh:size
                                                                bitsPerSample:8
                                                              samplesPerPixel:4
                                                                     hasAlpha:YES
                                                                     isPlanar:NO
                                                               colorSpaceName:NSDeviceRGBColorSpace
                                                                 bytesPerRow:0
                                                                  bitsPerPixel:0];
  if (!rep)
    return nil;

  NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
  if (ctx)
    {
      [NSGraphicsContext saveGraphicsState];
      [NSGraphicsContext setCurrentContext:ctx];

      // Start with transparent background
      [[NSColor clearColor] set];
      NSRectFill(NSMakeRect(0,0,size,size));

      // Draw docBase or fallback shape
      if (docBase)
        {
          [docBase drawInRect:NSMakeRect(0,0,size,size) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        }
      else
        {
          // Draw basic document with folded corner
          NSRect r = NSMakeRect(size*0.06, size*0.06, size*0.88, size*0.88);
          [[NSColor colorWithCalibratedWhite:0.98 alpha:1.0] setFill];
          NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:size*0.02 yRadius:size*0.02];
          [path fill];
          // folded corner
          NSPoint p1 = NSMakePoint(NSMaxX(r)-size*0.12, NSMaxY(r));
          NSPoint p2 = NSMakePoint(NSMaxX(r), NSMaxY(r)-size*0.12);
          NSBezierPath *fold = [NSBezierPath bezierPath];
          [fold moveToPoint:p1];
          [fold lineToPoint: NSMakePoint(NSMaxX(r), NSMaxY(r))];
          [fold lineToPoint:p2];
          [[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] setFill];
          [fold fill];
        }

      // Draw small app icon overlay if available
      if (appIcon)
        {
          CGFloat overlaySize = size * 0.40; // 40% of doc icon
          CGFloat inset = size * 0.08;
          NSRect overlayRect = NSMakeRect(size - inset - overlaySize, inset, overlaySize, overlaySize);
          // Optional: draw a rounded rect background for the overlay to make it pop
          NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(overlayRect, -4, -4) xRadius:6 yRadius:6];
          [[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] setFill];
          [bg fill];

          [appIcon drawInRect:overlayRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
          [appIcon release];
        }

      [NSGraphicsContext restoreGraphicsState];

      // Write a base PNG (without external-tool overlay)
      NSData *baseData = [rep representationUsingType:NSPNGFileType properties:nil];
      [rep release];

      if (!(baseData && [baseData writeToFile:docPath atomically:YES]))
        {
          NSLog(@"Failed to write base document icon to %@", docPath);
          return nil;
        }

      // If an app icon exists, try to composite it onto the base with ImageMagick (centered 64x64 overlay).
      if (appIcon)
        {
          NSString *convertExe = [self findExecutableInPath:@"convert"];
          if (!convertExe)
            {
              NSString *msg = @"ImageMagick 'convert' was not found in PATH. To get file-type icons with an overlayed app icon, install ImageMagick.\n\nCommon commands:\n  Debian/Ubuntu: sudo apt install imagemagick\n  Fedora/RHEL: sudo dnf install ImageMagick\n  Arch Linux: sudo pacman -S imagemagick\n  FreeBSD: sudo pkg install ImageMagick\n  OpenBSD: doas pkg_add ImageMagick\n\nFalling back to the base document icon (no overlay).";
              ShowErrorAlert(@"ImageMagick 'convert' not found", msg);
            }
          else
            {
              NSString *tmpBase = [docPath stringByAppendingString:@".base.png"];
              // Move base to a temp file and produce final composited PNG using convert
              [[NSFileManager defaultManager] moveItemAtPath:docPath toPath:tmpBase error:NULL];

              NSTask *task = [[NSTask alloc] init];
              [task setLaunchPath:convertExe];

              // Centered overlay: resize app icon to 64x64 and composite at center
              NSArray *args = @[
                tmpBase,
                @"(",
                [resourcesPath stringByAppendingPathComponent:appIconFilename],
                @"-resize",
                @"64x64",
                @")",
                @"-gravity",
                @"center",
                @"-composite",
                docPath
              ];

              [task setArguments:args];
              @try
                {
                  NSLog(@"Running convert to composite app icon: %@ %@", convertExe, args);
                  [task launch];
                  [task waitUntilExit];
                  int status = [task terminationStatus];
                  [task release];
                  if (status != 0)
                    {
                      NSLog(@"ImageMagick 'convert' failed (status %d); keeping base PNG: %@", status, tmpBase);
                      [[NSFileManager defaultManager] moveItemAtPath:tmpBase toPath:docPath error:NULL];
                    }
                  else
                    {
                      // Success: remove tmpBase
                      [[NSFileManager defaultManager] removeItemAtPath:tmpBase error:NULL];
                      NSLog(@"Composited app icon using convert: %@", docPath);
                    }
                }
              @catch (NSException *e)
                {
                  NSLog(@"Exception running convert: %@", e);
                  [[NSFileManager defaultManager] moveItemAtPath:tmpBase toPath:docPath error:NULL];
                }
            }
        }
    }
  else
    {
      // Fallback: some backends can't create a graphics context for the bitmap; use lockFocus on an NSImage
      NSLog(@"createDocumentIcon: bitmap context unavailable, falling back to lockFocus drawing");
      NSImage *canvas = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
      [canvas lockFocus];

      // transparent background
      [[NSColor clearColor] set];
      NSRectFill(NSMakeRect(0,0,size,size));

      if (docBase)
        {
          [docBase drawInRect:NSMakeRect(0,0,size,size) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        }
      else
        {
          NSRect r = NSMakeRect(size*0.06, size*0.06, size*0.88, size*0.88);
          [[NSColor colorWithCalibratedWhite:0.98 alpha:1.0] setFill];
          NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:size*0.02 yRadius:size*0.02];
          [path fill];
          NSPoint p1 = NSMakePoint(NSMaxX(r)-size*0.12, NSMaxY(r));
          NSPoint p2 = NSMakePoint(NSMaxX(r), NSMaxY(r)-size*0.12);
          NSBezierPath *fold = [NSBezierPath bezierPath];
          [fold moveToPoint:p1];
          [fold lineToPoint: NSMakePoint(NSMaxX(r), NSMaxY(r))];
          [fold lineToPoint:p2];
          [[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] setFill];
          [fold fill];
        }

      if (appIcon)
        {
          CGFloat overlaySize = size * 0.40;
          CGFloat inset = size * 0.08;
          NSRect overlayRect = NSMakeRect(size - inset - overlaySize, inset, overlaySize, overlaySize);
          NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(overlayRect, -4, -4) xRadius:6 yRadius:6];
          [[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] setFill];
          [bg fill];
          [appIcon drawInRect:overlayRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
          [appIcon release];
        }

      NSBitmapImageRep *tmpRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0,0,size,size)];
      [canvas unlockFocus];
      NSData *pngData = [tmpRep representationUsingType:NSPNGFileType properties:nil];
      [tmpRep release];
      [canvas release];

      if (!(pngData && [pngData writeToFile:docPath atomically:YES]))
        {
          NSLog(@"Failed to write document icon (fallback) to %@", docPath);
          return nil;
        }
    }

  // Basic validation: PNG signature (first 8 bytes) and that NSImage can load it
  NSError *readErr = nil;
  NSData *written = [NSData dataWithContentsOfFile:docPath options:0 error:&readErr];
  const unsigned char pngSig[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  BOOL valid = NO;

  if (!written || [written length] < 8)
    {
      NSLog(@"Written file is too small or couldn't be read: %@ (%@)", docPath, [readErr localizedDescription]);
    }
  else
    {
      if (memcmp([written bytes], pngSig, 8) == 0)
        {
          // Try loading via NSImage to ensure the PNG is readable by AppKit
          NSImage *verify = [[NSImage alloc] initWithContentsOfFile:docPath];
          if (verify && [verify size].width > 0)
            {
              valid = YES;
              NSLog(@"Document icon validated successfully: %@", docPath);
            }
          else
            {
              NSLog(@"NSImage failed to load generated PNG: %@", docPath);
            }
          [verify release];
        }
      else
        {
          NSLog(@"Generated file does not have PNG signature: %@", docPath);
        }
    }

  if (valid)
    return docFilename;

  // If validation failed, remove the invalid file and return nil
  NSLog(@"Removing invalid document icon: %@", docPath);
  [[NSFileManager defaultManager] removeItemAtPath:docPath error:NULL];
  return nil;
}

- (BOOL)createBundleFromDesktopFile:(NSString *)desktopPath
                           outputDir:(NSString *)outputDir
{
  // Parse the desktop file
  NSLog(@"Starting bundle creation from desktop file: %@", desktopPath);
  DesktopFileParser *parser = [[DesktopFileParser alloc] initWithFile:desktopPath];
  if (!parser)
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to parse desktop file: %@", desktopPath];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  // Get application metadata
  NSString *appName = [parser stringForKey:@"Name"];
  NSString *execCommand = [parser stringForKey:@"Exec"];
  NSString *iconName = [parser stringForKey:@"Icon"];

  NSLog(@"Parsed desktop file entries: Name=%@ Exec=%@ Icon=%@", appName, execCommand, iconName);

  if (!appName || !execCommand)
    {
      NSString *msg = @"Invalid desktop file: missing Name or Exec";
      ShowErrorAlert(@"Error", msg);
      [parser release];
      return NO;
    }

  // Use application name as bundle name, but sanitize it for filesystem safety
  NSString *bundleName = [self sanitizeFileName:appName];

  // Create the bundle path
  NSString *appPath = [NSString stringWithFormat:@"%@/%@.app", 
                       outputDir, bundleName];

  // Resolve icon path if provided
  NSString *resolvedIconPath = nil;
  if (iconName && [iconName length] > 0)
    {
      resolvedIconPath = [self resolveIconPath:iconName];
    }

  // If no icon was specified or resolution failed, try a set of generic fallback icons
  if (!resolvedIconPath)
    {
      NSArray *genericFallbacks = @[@"dialog-information", @"application", @"preferences-system", @"dialog-warning", @"dialog-error", @"notification", @"utilities-system-monitor"];
      NSLog(@"No specific icon resolved for %@; trying generic fallbacks: %@", appName, genericFallbacks);
      for (NSString *gname in genericFallbacks)
        {
          NSString *p = [self resolveIconPath:gname];
          if (p)
            {
              resolvedIconPath = p;
              NSLog(@"Using generic fallback icon '%@' -> %@", gname, p);
              break;
            }
        }
      if (!resolvedIconPath)
        {
          NSLog(@"No icon could be resolved for %@ (including generic fallbacks)", appName);
        }
    }

  // Create bundle structure
  NSLog(@"Creating bundle structure at %@", appPath);
  if (![self createBundleStructure:appPath withAppName:bundleName])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create bundle structure at %@", appPath];
      ShowErrorAlert(@"Error", msg);
      [parser release];
      return NO;
    }

  // Create the launcher script with the full Exec command; sanitize script name for safety
  NSLog(@"Creating launcher script (name: %@) with Exec: %@", bundleName, execCommand);
  if (![self createLauncherScript:appPath 
                      execCommand:execCommand
                        iconPath:resolvedIconPath
                        scriptName:bundleName])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create launcher script for %@", appName];
      ShowErrorAlert(@"Error", msg);
      [parser release];
      return NO;
    }

  // Copy icon if found and get the actual copied filename
  NSString *copiedIconFilename = nil;
  if (resolvedIconPath)
    {
      NSLog(@"Copying icon from %@ into bundle resources", resolvedIconPath);
      copiedIconFilename = [self copyIconToBundle:resolvedIconPath
                                  toBundleResources:[NSString stringWithFormat:@"%@/Resources", appPath]
                                           appName:bundleName];
      NSLog(@"Resulting icon filename in bundle: %@", copiedIconFilename);
    }
  else
    {
      NSLog(@"No icon resolved; skipping icon copy and Info.plist icon entry will be omitted");
    }

  // Create the Info.plist with the actual copied icon filename
  NSLog(@"Creating Info.plist (appName=%@, exec=%@, icon=%@)", appName, execCommand, copiedIconFilename);
  if (![self createInfoPlist:appPath 
                 desktopInfo:parser
                     appName:appName
                   execPath:execCommand
                   iconFilename:copiedIconFilename])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create Info.plist for %@", appName];
      ShowErrorAlert(@"Error", msg);
      [parser release];
      return NO;
    }

  NSLog(@"Successfully created application bundle: %@", appPath);
  [parser release];
  return YES;
}

- (BOOL)createBundleFromCommand:(NSString *)command
                        appName:(NSString *)appName
                        iconPath:(NSString *)iconPath
                        outputDir:(NSString *)outputDir
{
  if (!command || !appName || !outputDir) return NO;
  NSString *sanAppName = [self sanitizeFileName:appName];
  NSLog(@"Starting bundle creation from command: %@ (appName=%@)", command, sanAppName);

  NSString *appPath = [NSString stringWithFormat:@"%@/%@.app", outputDir, sanAppName];

  // Create bundle structure
  if (![self createBundleStructure:appPath withAppName:sanAppName])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create bundle structure at %@", appPath];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  // Create the launcher script with the provided command
  if (![self createLauncherScript:appPath execCommand:command iconPath:iconPath scriptName:sanAppName])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create launcher script for %@", appName];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  // Copy icon if provided and get the resulting filename
  NSString *copiedIconFilename = nil;
  if (iconPath && [iconPath length] > 0)
    {
      copiedIconFilename = [self copyIconToBundle:iconPath toBundleResources:[NSString stringWithFormat:@"%@/Resources", appPath] appName:sanAppName];
      NSLog(@"Resulting icon filename in bundle: %@", copiedIconFilename);
    }

  // Create Info.plist
  if (![self createInfoPlist:appPath desktopInfo:nil appName:appName execPath:command iconFilename:copiedIconFilename])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create Info.plist for %@", appName];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  NSLog(@"Successfully created application bundle: %@", appPath);
  return YES;
}

- (BOOL)createBundleStructure:(NSString *)appPath
                  withAppName:(NSString *)appName
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;

  // Create the .app directory
  if (![fm createDirectoryAtPath:appPath 
        withIntermediateDirectories:YES 
                         attributes:nil 
                              error:&error])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create app directory: %@", [error localizedDescription]];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  // Create Resources subdirectory
  NSString *resourcesPath = [NSString stringWithFormat:@"%@/Resources", appPath];
  if (![fm createDirectoryAtPath:resourcesPath 
        withIntermediateDirectories:YES 
                         attributes:nil 
                              error:&error])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to create Resources directory: %@", [error localizedDescription]];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  return YES;
}

- (BOOL)createInfoPlist:(NSString *)appPath
            desktopInfo:(DesktopFileParser *)parser
                appName:(NSString *)appName
              execPath:(NSString *)execPath
          iconFilename:(NSString *)iconFilename
{
  NSMutableDictionary *infoPlist = [NSMutableDictionary dictionary];

  [infoPlist setObject:@"8.0" forKey:@"NSAppVersion"];
  [infoPlist setObject:appName forKey:@"NSExecutable"];
  [infoPlist setObject:appName forKey:@"NSApplicationName"];
  [infoPlist setObject:@"1.0" forKey:@"NSApplicationVersion"];
  [infoPlist setObject:appName forKey:@"CFBundleName"];

  // Try to get version from desktop file
  NSString *version = [parser stringForKey:@"Version"];
  if (version)
    {
      [infoPlist setObject:version forKey:@"NSApplicationVersion"];
    }

  // Set icon name if an icon was successfully copied
  if (iconFilename && [iconFilename length] > 0)
    {
      // Use the full filename with extension
      NSString *iconNameWithExtension = [iconFilename lastPathComponent];
      [infoPlist setObject:iconNameWithExtension forKey:@"NSIcon"];
    }

  // Add document types from desktop MimeType key, if present
  NSArray *mimeTypes = [parser arrayForKey:@"MimeType"];
  if (mimeTypes && [mimeTypes count] > 0)
    {
      NSLog(@"Found MimeType entries in desktop file: %@", mimeTypes);
      NSMutableArray *docTypes = [NSMutableArray array];
      for (NSString *mt in mimeTypes)
        {
          if (![mt length]) continue;
          NSMutableDictionary *dt = [NSMutableDictionary dictionary];
          NSString *typeName = mt;
          [dt setObject:typeName forKey:@"CFBundleTypeName"];
          [dt setObject:@"Editor" forKey:@"CFBundleTypeRole"];

          NSArray *exts = [self extensionsForMIMEType:mt];
          if (exts && [exts count] > 0)
            {
              NSLog(@"Mapping MIME %@ -> extensions %@", mt, exts);
              [dt setObject:exts forKey:@"CFBundleTypeExtensions"];
            }
          else
            {
              NSLog(@"No extensions mapped for MIME %@; adding type without extensions", mt);
            }

          if (iconFilename && [iconFilename length] > 0)
            {
              // Create a document-specific icon by compositing the generic document image
              // with a small version of the app's icon so files of this type are visually
              // associated with the app. The icon will be written into the bundle Resources
              // and the resulting filename is stored in CFBundleTypeIconFile.
              NSString *resourcesPath = [NSString stringWithFormat:@"%@/Resources", appPath];
              NSString *createdDocIcon = [self createDocumentIconWithAppName:appName
                                                              resourcesPath:resourcesPath
                                                           appIconFilename:[iconFilename lastPathComponent]
                                                                    mimeType:mt
                                                                    typeName:typeName
                                                                        size:256];
              if (createdDocIcon)
                {
                  [dt setObject:createdDocIcon forKey:@"CFBundleTypeIconFile"];
                }
              else
                {
                  // Fallback to app icon if doc icon creation failed
                  [dt setObject:[iconFilename lastPathComponent] forKey:@"CFBundleTypeIconFile"];
                }
            }

          [docTypes addObject:dt];
        }

      if ([docTypes count] > 0)
        {
          [infoPlist setObject:docTypes forKey:@"CFBundleDocumentTypes"];
          NSLog(@"Added CFBundleDocumentTypes to Info.plist: %@", docTypes);
        }
    }

  // Create the plist file
  NSString *plistPath = [NSString stringWithFormat:@"%@/Resources/Info.plist", appPath];
  BOOL ok = [infoPlist writeToFile:plistPath atomically:YES];
  if (!ok)
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to write Info.plist to %@", plistPath];
      ShowErrorAlert(@"Error", msg);
    }
  else
    {
      NSLog(@"Wrote Info.plist to %@", plistPath);
    }
  return ok;
}

- (BOOL)createLauncherScript:(NSString *)appPath
                 execCommand:(NSString *)command
                 iconPath:(NSString *)iconPath
                 scriptName:(NSString *)scriptName
{
  NSFileManager *fm = [NSFileManager defaultManager];
  // Use the provided scriptName (full appName with spaces) for the executable file
  NSString *launcherPath = [NSString stringWithFormat:@"%@/%@", appPath, scriptName];

  // Sanitize Exec= field codes (%U, %u, %F, %f, %i, %c, %k) and %% → %
  NSLog(@"Sanitizing Exec command for launcher: %@", command);
  NSString *sanitized = [self sanitizeExecCommand:command];
  if (!sanitized || [sanitized length] == 0)
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to sanitize Exec command: %@", command];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  NSLog(@"Sanitized Exec command: %@", sanitized);

  // Create the launcher script using the sanitized command
  NSString *script = [NSString stringWithFormat:
    @"#!/bin/sh\n"
    @"# Auto-generated launcher script\n"
    @"exec %@ \"$@\"\n",
    sanitized];

  NSError *error = nil;
  if (![script writeToFile:launcherPath 
                 atomically:YES 
                   encoding:NSUTF8StringEncoding 
                      error:&error])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to write launcher script: %@", [error localizedDescription]];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  // Make the script executable
  if (![fm setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0755]
                                                     forKey:NSFilePosixPermissions]
            ofItemAtPath:launcherPath error:&error])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to set permissions on launcher script: %@", [error localizedDescription]];
      ShowErrorAlert(@"Error", msg);
      return NO;
    }

  NSLog(@"Created launcher script at %@", launcherPath);
  return YES;
}

- (NSString *)sanitizeExecCommand:(NSString *)command
{
  if (!command) { return nil; }

  NSLog(@"Sanitizing Exec field: %@", command);
  NSMutableString *mutable = [NSMutableString stringWithString:command];

  // Remove common freedesktop field codes
  NSArray *codes = @[@"%U", @"%u", @"%F", @"%f", @"%i", @"%c", @"%k"];
  for (NSString *code in codes)
    {
      [mutable replaceOccurrencesOfString:code
                               withString:@""
                                  options:0
                                    range:NSMakeRange(0, [mutable length])];
    }

  // %% represents a literal percent
  [mutable replaceOccurrencesOfString:@"%%"
                           withString:@"%"
                              options:0
                                range:NSMakeRange(0, [mutable length])];

  // Collapse whitespace that may result from removals
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSArray *parts = [mutable componentsSeparatedByCharactersInSet:ws];
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSString *p in parts)
    {
      if ([p length] > 0) { [filtered addObject:p]; }
    }
  NSString *collapsed = [filtered componentsJoinedByString:@" "];
  NSLog(@"Sanitized Exec field -> %@", collapsed);
  return collapsed;
}

- (NSArray *)extensionsForMIMEType:(NSString *)mimeType
{
  if (!mimeType) return nil;

  NSLog(@"Looking up extensions for MIME type: %@", mimeType);

  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableSet *exts = [NSMutableSet set];


  NSArray *pkgDirs = @[@"/usr/share/mime/packages",
                       @"/usr/local/share/mime/packages",
                       [NSString stringWithFormat:@"%@/.local/share/mime/packages", NSHomeDirectory()]];
  for (NSString *dir in pkgDirs)
    {
      if (![fm fileExistsAtPath:dir]) continue;
      NSLog(@"Scanning mime package dir: %@", dir);
      NSDirectoryEnumerator *e = [fm enumeratorAtPath:dir];
      NSString *file;
      while ((file = [e nextObject]))
        {
          NSString *path = [dir stringByAppendingPathComponent:file];
          NSError *readErr = nil;
          NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readErr];
          if (!content)
            {
              NSLog(@"Failed reading %@: %@", path, [readErr localizedDescription]);
              continue;
            }

          // Look for the specific mime-type tag
          NSString *searchTag1 = [NSString stringWithFormat:@"<mime-type type=\"%@\"", mimeType];
          NSString *searchTag2 = [NSString stringWithFormat:@"<mime-type type=\'%@\'", mimeType];

          NSRange foundRange = [content rangeOfString:searchTag1];
          if (foundRange.location == NSNotFound)
            foundRange = [content rangeOfString:searchTag2];

          if (foundRange.location != NSNotFound)
            {
              // Limit to the mime-type section (until </mime-type> or next <mime-type)
              NSRange tailRange = NSMakeRange(foundRange.location, [content length] - foundRange.location);
              NSRange endRange = [content rangeOfString:@"</mime-type>" options:0 range:tailRange];
              NSUInteger scanLength = (endRange.location != NSNotFound) ? (endRange.location - foundRange.location) : (tailRange.length);
              NSString *section = [content substringWithRange:NSMakeRange(foundRange.location, scanLength)];

              // Find pattern="*.ext" occurrences using regex
              NSError *reErr = nil;
              NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"pattern\\s*=\\s*['\"](\\*\\.[^'\"]+)['\"]" options:NSRegularExpressionCaseInsensitive error:&reErr];
              if (re && !reErr)
                {
                  NSArray *matches = [re matchesInString:section options:0 range:NSMakeRange(0, [section length])];
                  for (NSTextCheckingResult *m in matches)
                    {
                      NSRange r = [m rangeAtIndex:1];
                      NSString *pat = [section substringWithRange:r]; // like "*.txt" or "*.tar.gz"
                      if ([pat hasPrefix:@"*."] && [pat length] > 2)
                        {
                          NSString *ext = [pat substringFromIndex:2];
                          [exts addObject:ext];
                        }
                    }
                }
            }
        }

      if ([exts count] > 0)
        {
          NSLog(@"Found extensions via mime packages: %@", exts);
          return [[exts allObjects] sortedArrayUsingSelector:@selector(compare:)];
        }
    }

  // 2) Try globs2 / globs files as a fallback
  NSArray *globsFiles = @[@"/usr/share/mime/globs2",
                          @"/usr/local/share/mime/globs2",
                          [NSString stringWithFormat:@"%@/.local/share/mime/globs2", NSHomeDirectory()],
                          @"/usr/share/mime/globs",
                          @"/usr/local/share/mime/globs"];

  for (NSString *gf in globsFiles)
    {
      if (![fm fileExistsAtPath:gf]) continue;
      NSError *gErr = nil;
      NSString *content = [NSString stringWithContentsOfFile:gf encoding:NSUTF8StringEncoding error:&gErr];
      if (!content)
        {
          NSLog(@"Failed reading %@: %@", gf, [gErr localizedDescription]);
          continue;
        }

      NSLog(@"Scanning globs file: %@", gf);
      NSArray *lines = [content componentsSeparatedByString:@"\n"];
      for (NSString *line in lines)
        {
          if ([line rangeOfString:mimeType].location == NSNotFound) continue;

          // Find any token with *.
          NSScanner *sc = [NSScanner scannerWithString:line];
          while (![sc isAtEnd])
            {
              [sc scanUpToString:@"*." intoString:NULL];
              if ([sc scanString:@"*." intoString:NULL])
                {
                  // read until non-word or whitespace
                  NSMutableString *acc = [NSMutableString string];
                  unichar ch;
                  while (![sc isAtEnd])
                    {
                      ch = [line characterAtIndex:sc.scanLocation];
                      if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch] || ch == '.')
                        {
                          [acc appendFormat:@"%c", ch];
                          sc.scanLocation += 1;
                        }
                      else
                        break;
                    }
                  if ([acc length] > 0)
                    {
                      [exts addObject:acc];
                    }
                }
              else
                break;
            }
        }

      if ([exts count] > 0)
        {
          NSLog(@"Found extensions via globs file %@: %@", gf, exts);
          return [[exts allObjects] sortedArrayUsingSelector:@selector(compare:)];
        }
    }

  // 3) Fallback to small built-in mapping (only used if system DB not available)
  NSLog(@"No shared-mime-info entries found for %@; falling back to built-in mapping", mimeType);
  static NSDictionary *mimeMap = nil;
  if (!mimeMap)
    {
      mimeMap = [[NSDictionary alloc] initWithObjectsAndKeys:
                 @[@"txt"], @"text/plain",
                 @[@"html", @"htm"], @"text/html",
                 @[@"png"], @"image/png",
                 @[@"jpg", @"jpeg"], @"image/jpeg",
                 @[@"gif"], @"image/gif",
                 @[@"pdf"], @"application/pdf",
                 @[@"zip"], @"application/zip",
                 @[@"tar"], @"application/x-tar",
                 @[@"7z"], @"application/x-7z-compressed",
                 @[@"json"], @"application/json",
                 @[@"xml"], @"application/xml",
                 @[@"mp3"], @"audio/mpeg",
                 @[@"mp4"], @"video/mp4",
                 nil];
    }

  NSArray *fb = [mimeMap objectForKey:mimeType];
  if (fb && [fb count] > 0)
    return fb;

  // Final fallback: use subtype
  NSArray *parts = [mimeType componentsSeparatedByString:@"/"];
  if ([parts count] > 1)
    {
      NSString *subtype = [[parts lastObject] lowercaseString];
      NSRange plus = [subtype rangeOfString:@"+"];
      if (plus.location != NSNotFound)
        subtype = [subtype substringFromIndex:plus.location + 1];
      if ([subtype length] > 0) return [NSArray arrayWithObject:subtype];
    }

  return nil;
}

- (NSString *)findExecutableInPath:(NSString *)name
{
  if (!name || [name length] == 0) return nil;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *path = [env objectForKey:@"PATH"];
  if (!path) path = @"/usr/bin:/bin:/usr/local/bin";

  NSArray *components = [path componentsSeparatedByString:@":" ];
  for (NSString *dir in components)
    {
      NSString *candidate = [dir stringByAppendingPathComponent:name];
      if ([fm isExecutableFileAtPath:candidate])
        {
          NSLog(@"Found executable '%@' at %@", name, candidate);
          return candidate;
        }
    }
  NSLog(@"Executable '%@' not found in PATH", name);
  return nil;
}

- (BOOL)rasterizeSVG:(NSString *)svgPath toPNG:(NSString *)pngPath size:(int)size
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSLog(@"Attempting to rasterize SVG %@ -> %@ at %dx%d using GNUstep if available", svgPath, pngPath, size, size);

  // First try pure-GNUstep approach using NSImage drawing
  @try
    {
      NSImage *img = [[NSImage alloc] initWithContentsOfFile:svgPath];
      if (img && [img isKindOfClass:[NSImage class]])
        {
          NSLog(@"Loaded SVG into NSImage (size=%@). Rendering to %dx%d...", NSStringFromSize([img size]), size, size);

          // Create an alpha-enabled bitmap representation and draw into it using SourceOver
          NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                           pixelsWide:size
                                                                           pixelsHigh:size
                                                                        bitsPerSample:8
                                                                      samplesPerPixel:4
                                                                             hasAlpha:YES
                                                                             isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace
                                                                         bytesPerRow:0
                                                                          bitsPerPixel:0];

          NSLog(@"Created NSBitmapImageRep for rasterization (hasAlpha=%d)", [rep hasAlpha]);

          if (rep)
            {
              NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
              [NSGraphicsContext saveGraphicsState];
              [NSGraphicsContext setCurrentContext:ctx];

              // Clear to transparent first
              [[NSColor clearColor] set];
              NSRectFill(NSMakeRect(0, 0, size, size));

              // Draw image scaled to target using SourceOver so alpha is preserved
              [img drawInRect:NSMakeRect(0,0,size,size) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];

              [NSGraphicsContext restoreGraphicsState];

              NSData *pngData = [rep representationUsingType:NSPNGFileType properties:nil];
              if (pngData && [pngData writeToFile:pngPath atomically:YES])
                {
                  NSLog(@"GNUstep rasterization succeeded: %@", pngPath);
                  [rep release];
                  [img release];
                  return YES;
                }
              else
                {
                  NSLog(@"GNUstep rasterization produced no data or failed to write to %@", pngPath);
                }
              [rep release];
            }
          [img release];
        }
    }
  @catch (NSException *ex)
    {
      NSLog(@"GNUstep rasterization failed with exception: %@", ex);
    }

  // If we get here, fallback to command-line tools found on PATH
  NSArray *tools = @[@"rsvg-convert", @"convert", @"magick"]; // try rsvg-convert, then ImageMagick
  for (NSString *t in tools)
    {
      NSString *exe = [self findExecutableInPath:t];
      if (!exe) continue;

      NSLog(@"Using external tool '%@' at %@ to rasterize", t, exe);
      NSTask *task = [[NSTask alloc] init];

      if ([t isEqualToString:@"rsvg-convert"]) 
        {
          [task setLaunchPath:exe];
          // Request transparent background explicitly
          [task setArguments:@[@"-w", [NSString stringWithFormat:@"%d", size], @"-h", [NSString stringWithFormat:@"%d", size], @"-b", @"transparent", @"-o", pngPath, svgPath]];
        }
      else if ([t isEqualToString:@"magick"]) // 'magick' uses syntax: magick input.svg -background none -resize 256x256 output.png
        {
          [task setLaunchPath:exe];
          [task setArguments:@[svgPath, @"-background", @"none", @"-resize", [NSString stringWithFormat:@"%dx%d", size, size], pngPath]];
        }
      else // convert
        {
          [task setLaunchPath:exe];
          [task setArguments:@[svgPath, @"-background", @"none", @"-resize", [NSString stringWithFormat:@"%dx%d", size, size], pngPath]];
        }

      @try
        {
          [task launch];
          [task waitUntilExit];
          int status = [task terminationStatus];
          [task release];
          if (status == 0 && [fm fileExistsAtPath:pngPath])
            {
              NSLog(@"External tool '%@' rasterized SVG successfully to %@", t, pngPath);
              return YES;
            }
          else
            {
              NSLog(@"External tool '%@' failed (status %d)", t, status);
            }
        }
      @catch (NSException *e)
        {
          NSLog(@"Failed to run '%@' due to exception: %@", t, e);
        }
    }

  NSLog(@"All rasterization methods failed for %@", svgPath);
  return NO;
}

- (NSString *)resolveIconPath:(NSString *)iconName
{
  NSFileManager *fm = [NSFileManager defaultManager];
  if (!iconName || [iconName length] == 0)
    {
      NSLog(@"resolveIconPath: called with empty iconName");
      return nil;
    }

  NSLog(@"Resolving icon path for: '%@'", iconName);

  // If it's an absolute path and exists, use it directly
  if ([iconName hasPrefix:@"/"] && [fm fileExistsAtPath:iconName])
    {
      NSLog(@"Icon provided as absolute path and exists: %@", iconName);
      return iconName;
    }

  // Candidate structure: @{ @"path": path, @"ext": ext, @"score": @(score) }
  NSMutableArray *candidates = [NSMutableArray array];

  // Extensions to consider (ordered by preference)
  NSArray *extensions = @[@".png", @".svg", @".xpm", @".ico", @".gif", @".jpg", @".jpeg", @""];

  // Build a list of directories to search (themes + pixmaps + local)
  NSMutableArray *iconBaseDirs = [NSMutableArray arrayWithObjects:
                                  @"/usr/share/icons",
                                  @"/usr/local/share/icons",
                                  @"/usr/share/pixmaps",
                                  @"/usr/local/share/pixmaps",
                                  [NSString stringWithFormat:@"%@/.local/share/icons", NSHomeDirectory()],
                                  [NSString stringWithFormat:@"%@/.local/share/pixmaps", NSHomeDirectory()],
                                  nil];

  // Also add top-level hicolor locations for quick checks
  NSArray *quickPaths = @[
    @"/usr/share/icons/hicolor",
    @"/usr/local/share/icons/hicolor",
    [NSString stringWithFormat:@"%@/.local/share/icons/hicolor", NSHomeDirectory()]
  ];

  // 1) Quick exact checks (theme common sizes + pixmaps)
  NSArray *quickSizePaths = @[@"256x256/apps", @"128x128/apps", @"96x96/apps", @"64x64/apps", @"48x48/apps", @"32x32/apps", @"24x24/apps"];
  for (NSString *base in quickPaths)
    {
      for (NSString *sizeSub in quickSizePaths)
        {
          for (NSString *ext in extensions)
            {
              NSString *cand = [NSString stringWithFormat:@"%@/%@/%@%@", base, sizeSub, iconName, ext];
              if ([fm fileExistsAtPath:cand])
                {
                  NSLog(@"Quick-match found candidate: %@", cand);
                  [candidates addObject:@{@"path": cand, @"ext": ext}];
                }
            }
        }
    }

  // 2) Recursive search in iconBaseDirs for exact basename matches
  for (NSString *base in iconBaseDirs)
    {
      if (![fm fileExistsAtPath:base]) continue;
      NSLog(@"Searching base icon dir: %@", base);
      NSDirectoryEnumerator *e = [fm enumeratorAtPath:base];
      NSString *file;
      while ((file = [e nextObject]))
        {
          NSString *lowerFile = [file lowercaseString];
          NSString *lowerIcon = [iconName lowercaseString];

          // Check if file ends with iconName + ext or equals iconName
          for (NSString *ext in extensions)
            {
              NSString *target = nil;
              if ([ext length] > 0)
                target = [NSString stringWithFormat:@"%@%@", iconName, ext];
              else
                target = iconName;

              if ([[file lastPathComponent] isEqualToString:target] || [[file lastPathComponent] isEqualToString:[target lowercaseString]] || [[file lastPathComponent] isEqualToString:[target uppercaseString]])
                {
                  NSString *full = [base stringByAppendingPathComponent:file];
                  NSLog(@"Found candidate by basename match: %@", full);
                  [candidates addObject:@{@"path": full, @"ext": ext}];
                }
            }

          // quick substring fuzzy match (e.g., iconName-symbolic, iconName-16)
          if ([lowerFile rangeOfString:lowerIcon].location != NSNotFound)
            {
              NSString *full = [base stringByAppendingPathComponent:file];
              NSLog(@"Found fuzzy candidate (substring match): %@", full);
              [candidates addObject:@{@"path": full, @"ext": [[file pathExtension] length] ? [@"." stringByAppendingString:[file pathExtension]] : @""}];
            }
        }

      if ([candidates count] > 0)
        {
          NSLog(@"Stopping search at base %@ because candidates were found", base);
          break;
        }
    }

  // If no candidates yet, try more aggressive fuzzy search across installed themes
  if ([candidates count] == 0)
    {
      NSLog(@"No direct candidates found; performing aggressive fuzzy search (case-insensitive substring) across icon dirs");
      for (NSString *base in iconBaseDirs)
        {
          if (![fm fileExistsAtPath:base]) continue;
          NSDirectoryEnumerator *e = [fm enumeratorAtPath:base];
          NSString *file;
          while ((file = [e nextObject]))
            {
              NSString *lowerFile = [file lowercaseString];
              NSString *lowerIcon = [iconName lowercaseString];
              if ([lowerFile rangeOfString:lowerIcon].location != NSNotFound)
                {
                  NSString *full = [base stringByAppendingPathComponent:file];
                  NSLog(@"Aggressive fuzzy candidate: %@", full);
                  [candidates addObject:@{@"path": full, @"ext": [[file pathExtension] length] ? [@"." stringByAppendingString:[file pathExtension]] : @""}];
                }
            }
        }
    }

  // If still no candidates, try a short list of generic application icons as a last-resort fallback
  if ([candidates count] == 0)
    {
      NSArray *genericIcons = @[@"application-x-executable", @"application", @"dialog-information", @"preferences-system", @"system-run", @"utilities-terminal", @"help-about", @"preferences-desktop", @"applications-graphics"]; 
      NSLog(@"No candidates for '%@'; trying generic icon names: %@", iconName, genericIcons);
      for (NSString *g in genericIcons)
        {
          // Quick check in common quickPaths
          BOOL found = NO;
          for (NSString *base in quickPaths)
            {
              for (NSString *sizeSub in quickSizePaths)
                {
                  for (NSString *ext in extensions)
                    {
                      NSString *cand = [NSString stringWithFormat:@"%@/%@/%@%@", base, sizeSub, g, ext];
                      if ([fm fileExistsAtPath:cand])
                        {
                          NSLog(@"Generic fallback matched: %@", cand);
                          [candidates addObject:@{@"path": cand, @"ext": ext}];
                          found = YES; break;
                        }
                    }
                  if (found) break;
                }
              if (found) break;
            }

          if (found) break;

          // If not found in quick paths, do a shallow search in iconBaseDirs
          for (NSString *base in iconBaseDirs)
            {
              if (![fm fileExistsAtPath:base]) continue;
              NSDirectoryEnumerator *e = [fm enumeratorAtPath:base];
              NSString *file;
              while ((file = [e nextObject]))
                {
                  NSString *lowerFile = [file lowercaseString];
                  if ([lowerFile rangeOfString:g].location != NSNotFound)
                    {
                      NSString *full = [base stringByAppendingPathComponent:file];
                      NSLog(@"Generic fallback fuzzy candidate: %@", full);
                      [candidates addObject:@{@"path": full, @"ext": [[file pathExtension] length] ? [@"." stringByAppendingString:[file pathExtension]] : @""}];
                      found = YES; break;
                    }
                }
              if (found) break;
            }
          if (found) break;
        }
    }

  if ([candidates count] == 0)
    {
      NSLog(@"No icon candidates found for '%@' after extensive search and generic fallbacks", iconName);
      return nil;
    }

  // Score candidates and pick the best one
  NSMutableArray *scored = [NSMutableArray array];
  for (NSDictionary *c in candidates)
    {
      NSString *path = [c objectForKey:@"path"];
      NSString *ext = [[path pathExtension] lowercaseString];
      int score = 0;

      // Extension preference
      if ([ext isEqualToString:@"png"]) score += 100;
      else if ([ext isEqualToString:@"svg"]) score += 90;
      else if ([ext isEqualToString:@"xpm"]) score += 70;
      else if ([ext isEqualToString:@"ico"]) score += 60;
      else if ([ext isEqualToString:@"gif"]) score += 50;
      else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) score += 40;
      else if ([ext length] == 0) score += 10;

      // Theme boost for hicolor
      if ([path rangeOfString:@"hicolor" options:NSCaseInsensitiveSearch].location != NSNotFound) score += 50;

      // Pixmaps directory moderate boost
      if ([path rangeOfString:@"/pixmaps" options:NSCaseInsensitiveSearch].location != NSNotFound) score += 20;

      // Prefer non-symbolic icons a bit
      if ([[path lastPathComponent] rangeOfString:@"-symbolic" options:NSCaseInsensitiveSearch].location != NSNotFound)
        score -= 30;

      // Parse size in path like 256x256
      NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"([0-9]+)x([0-9]+)" options:0 error:NULL];
      NSTextCheckingResult *m = [re firstMatchInString:path options:0 range:NSMakeRange(0, [path length])];
      if (m && [m numberOfRanges] >= 3)
        {
          NSString *s1 = [path substringWithRange:[m rangeAtIndex:1]];
          int sizeVal = [s1 intValue];
          score += sizeVal; // larger size -> higher score
        }

      // Scalable icons should be treated as high quality
      if ([path rangeOfString:@"scalable" options:NSCaseInsensitiveSearch].location != NSNotFound)
        score += 200;

      [scored addObject:@{@"path": path, @"score": @(score)}];
    }

  // Log candidate scores
  NSLog(@"Icon candidates and scores for '%@':", iconName);
  for (NSDictionary *s in scored)
    {
      NSLog(@"  %@ -> %@", [s objectForKey:@"path"], [s objectForKey:@"score"]);
    }

  // Pick the candidate with the highest score
  NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"score" ascending:NO];
  NSArray *sorted = [scored sortedArrayUsingDescriptors:@[sd]];
  NSDictionary *best = [sorted objectAtIndex:0];
  NSString *bestPath = [best objectForKey:@"path"];

  NSLog(@"Selected icon for '%@': %@ (reason: highest score)", iconName, bestPath);
  return bestPath;
}

- (NSString *)copyIconToBundle:(NSString *)iconPath
                toBundleResources:(NSString *)resourcesPath
                       appName:(NSString *)appName
{
  if (!iconPath)
    return nil;

  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;

  // Check if the icon file exists and has non-zero size
  NSDictionary *fileAttrs = [fm attributesOfItemAtPath:iconPath error:&error];
  if (!fileAttrs)
    {
      NSString *msg = [NSString stringWithFormat:@"Could not read icon file attributes: %@", [error localizedDescription]];
      ShowErrorAlert(@"Icon error", msg);
      return nil;
    }

  unsigned long long fileSize = [fileAttrs fileSize];
  if (fileSize == 0)
    {
      NSString *msg = [NSString stringWithFormat:@"Icon file is empty (0 bytes): %@", iconPath];
      ShowErrorAlert(@"Icon error", msg);
      return nil;
    }

  // Get the icon file extension
  NSString *iconExt = [[iconPath pathExtension] lowercaseString];
  if ([iconExt length] == 0)
    {
      iconExt = @"png";
    }

  // If the icon is an SVG, try to rasterize to PNG (256x256)
  if ([iconExt isEqualToString:@"svg"])
    {
      NSString *bundleIconPath = [NSString stringWithFormat:@"%@/%@.%@",
                                 resourcesPath, appName, @"png"];

      // Attempt GNUstep rasterization or external tool fallback
      if ([self rasterizeSVG:iconPath toPNG:bundleIconPath size:256])
        {
          NSDictionary *copiedAttrs = [fm attributesOfItemAtPath:bundleIconPath error:&error];
          if (copiedAttrs && [copiedAttrs fileSize] > 0)
            {
              NSLog(@"Rasterized SVG and wrote PNG to bundle as %@", [bundleIconPath lastPathComponent]);
              return [bundleIconPath lastPathComponent];
            }
          else
            {
              NSLog(@"Rasterization produced empty file or failed to write: %@", bundleIconPath);
              // Fall through to copying original svg file if rasterization failed
            }
        }
      else
        {
          NSLog(@"Rasterization failed for %@; will try to copy original SVG into bundle as fallback", iconPath);
        }

      // As a fallback, copy the original SVG into the resources (so icon still exists)
      NSString *bundleSVGPath = [NSString stringWithFormat:@"%@/%@.%@", resourcesPath, appName, @"svg"];
      if ([fm copyItemAtPath:iconPath toPath:bundleSVGPath error:&error])
        {
          NSDictionary *copiedAttrs = [fm attributesOfItemAtPath:bundleSVGPath error:&error];
          if (copiedAttrs && [copiedAttrs fileSize] > 0)
            {
              NSLog(@"Copied SVG fallback into bundle as %@", [bundleSVGPath lastPathComponent]);
              return [bundleSVGPath lastPathComponent];
            }
          else
            {
              NSLog(@"Copied SVG fallback file is empty, removing: %@", bundleSVGPath);
              [fm removeItemAtPath:bundleSVGPath error:NULL];
              return nil;
            }
        }
      else
        {
          NSLog(@"Failed to copy SVG fallback into bundle: %@", [error localizedDescription]);
          return nil;
        }
    }

  // Non-SVG: Create the destination path with the extension
  NSString *bundleIconPath = [NSString stringWithFormat:@"%@/%@.%@",
                             resourcesPath, appName, iconExt];

  // Copy icon to bundle Resources
  if (![fm copyItemAtPath:iconPath toPath:bundleIconPath error:&error])
    {
      NSString *msg = [NSString stringWithFormat:@"Failed to copy icon: %@", [error localizedDescription]];
      ShowErrorAlert(@"Icon error", msg);
      return nil;
    }

  // Verify the copied file is not empty
  NSDictionary *copiedAttrs = [fm attributesOfItemAtPath:bundleIconPath error:&error];
  if (!copiedAttrs || [copiedAttrs fileSize] == 0)
    {
      NSString *msg = [NSString stringWithFormat:@"Copied icon file is empty, removing: %@", bundleIconPath];
      ShowErrorAlert(@"Icon error", msg);
      [fm removeItemAtPath:bundleIconPath error:NULL];
      return nil;
    }

  NSLog(@"Copied icon to bundle as %@", [bundleIconPath lastPathComponent]);
  // Return the filename with extension
  return [bundleIconPath lastPathComponent];
}

@end

// Main entry point
static void print_usage(const char *prog)
{
  fprintf(stderr, "Usage: %s [OPTIONS] /path/to/application.desktop [output_dir]\n", prog);
  fprintf(stderr, "       %s [OPTIONS] -c|--command \"command to run\" [-i|--icon /path/to/icon.png] [output_dir]\n", prog);
  fprintf(stderr, "\nIf output_dir is not specified:\n");
  fprintf(stderr, "  - ~/Applications is used for non-root users\n");
  fprintf(stderr, "  - /Local/Applications is used for root\n");
  fprintf(stderr, "\nOptions:\n");
  fprintf(stderr, "  -f, --force    Overwrite existing app bundle without asking\n");
  fprintf(stderr, "  -c, --command  Provide a command line to execute instead of a .desktop file (accepts args; use -- or quote your command)\n");
  fprintf(stderr, "  -i, --icon     Path to an icon file to use (overrides .desktop Icon resolution)\n");
  fprintf(stderr, "  -N, --name     Explicit application name to use for the bundle\n");
  fprintf(stderr, "  -a, --append-arg ARG   Append ARG to the command (may be used multiple times)\n");
  fprintf(stderr, "  -p, --prepend-arg ARG  Prepend ARG to the command (may be used multiple times)\n");
  fprintf(stderr, "  -h, --help     Show this help\n");
}

int main(int argc, char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  // Create a minimal NSApplication to allow AppKit operations (image loading, drawing)
  [[NSUserDefaults standardUserDefaults] setBool: YES forKey: @"NSApplicationSuppressPSN"];
  NSApplication *app __attribute__((unused)) = [NSApplication sharedApplication];

  BOOL forceOverwrite = NO;
  char *commandArg = NULL;
  char *iconArg = NULL;
  char *nameArg = NULL;

  // Support multiple prepend/append args
  NSMutableArray *prependArgs = [NSMutableArray array];
  NSMutableArray *appendArgs = [NSMutableArray array];

  static struct option long_options[] = {
    {"force", no_argument, 0, 'f'},
    {"command", required_argument, 0, 'c'},
    {"icon", required_argument, 0, 'i'},
    {"name", required_argument, 0, 'N'},
    {"append-arg", required_argument, 0, 'a'},
    {"prepend-arg", required_argument, 0, 'p'},
    {"help", no_argument, 0, 'h'},
    {0, 0, 0, 0}
  };

  int opt;
  int option_index = 0;
  while ((opt = getopt_long(argc, argv, "fc:i:hN:a:p:", long_options, &option_index)) != -1)
    {
      switch (opt)
        {
        case 'f':
          forceOverwrite = YES;
          break;
        case 'c':
          commandArg = optarg;
          break;
        case 'i':
          iconArg = optarg;
          break;
        case 'N':
          nameArg = optarg;
          break;
        case 'a':
          if (optarg) [appendArgs addObject:[NSString stringWithUTF8String:optarg]];
          break;
        case 'p':
          if (optarg) [prependArgs addObject:[NSString stringWithUTF8String:optarg]];
          break;
        case 'h':
          print_usage(argv[0]);
          [pool release];
          exit(EXIT_SUCCESS);
          break;
        default:
          print_usage(argv[0]);
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  BOOL commandMode = (commandArg != NULL);

  NSString *desktopFilePath = nil;
  NSString *outputDir = nil;
  NSString *iconPath = nil;
  NSString *commandStr = nil;

  // Positional arguments handling for desktop-mode or command-mode
  if (commandMode)
    {
      commandStr = [NSString stringWithUTF8String:commandArg];
      if (!commandStr || [commandStr length] == 0)
        {
          ShowErrorAlert(@"Error", @"Empty --command value");
          [pool release];
          exit(EXIT_FAILURE);
        }

      // Collect remaining positionals; these may be additional command args and/or an output_dir
      NSMutableArray *positionals = [NSMutableArray array];
      for (int i = optind; i < argc; i++)
        {
          [positionals addObject:[NSString stringWithUTF8String:argv[i]]];
        }

      // If the last positional appears path-like (contains '/','~', or starts with '/'), treat it as outputDir
      if ([positionals count] > 0)
        {
          NSString *last = [positionals lastObject];
          if ([last hasPrefix:@"/"] || [last hasPrefix:@"~"] || [last rangeOfString:@"/"].location != NSNotFound)
            {
              outputDir = last;
              [positionals removeLastObject];
            }
        }

      // Default output dir if none provided
      if (!outputDir)
        {
          if (geteuid() == 0)
            outputDir = @"/Local/Applications";
          else
            outputDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"];
        }

      // Append remaining positional tokens to the command (so --command can be used without quotes)
      for (NSString *p in positionals)
        {
          commandStr = [commandStr stringByAppendingFormat:@" %@", p];
        }

      // Prepend args, if any
      for (NSString *p in prependArgs)
        {
          commandStr = [NSString stringWithFormat:@"%@ %@", p, commandStr];
        }

      // Append args, if any
      for (NSString *p in appendArgs)
        {
          commandStr = [commandStr stringByAppendingFormat:@" %@", p];
        }

      if (iconArg)
        iconPath = [NSString stringWithUTF8String:iconArg];

      if (nameArg)
        {
          // Explicit name provided
          // nameStr will be used later when deriving bundle name
        }
    }
  else
    {
      if (optind >= argc)
        {
          fprintf(stderr, "Error: Desktop file path required\n");
          print_usage(argv[0]);
          [pool release];
          exit(EXIT_FAILURE);
        }

      desktopFilePath = [NSString stringWithUTF8String:argv[optind]];
      if (optind + 1 < argc)
        outputDir = [NSString stringWithUTF8String:argv[optind + 1]];
      else
        {
          if (geteuid() == 0)
            outputDir = @"/Local/Applications";
          else
            outputDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"];
        }
    }

  // Expand ~ in paths
  if (desktopFilePath) desktopFilePath = [desktopFilePath stringByExpandingTildeInPath];
  if (outputDir) outputDir = [outputDir stringByExpandingTildeInPath];
  if (iconPath) iconPath = [iconPath stringByExpandingTildeInPath];

  // Create output directory if it doesn't exist
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *dirError = nil;
  if (![fm fileExistsAtPath:outputDir])
    {
      if (![fm createDirectoryAtPath:outputDir
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&dirError])
        {
          NSString *msg = [NSString stringWithFormat:@"Failed to create output directory: %@", [dirError localizedDescription]];
          ShowErrorAlert(@"Error", msg);
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  // In desktop mode, validate the desktop file exists
  if (!commandMode)
    {
      if (![fm fileExistsAtPath:desktopFilePath])
        {
          NSString *msg = [NSString stringWithFormat:@"Desktop file not found: %@", desktopFilePath];
          ShowErrorAlert(@"Error", msg);
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  // Create the bundle
  AppBundleCreator *creator = [[AppBundleCreator alloc] init];
  BOOL success = NO;

  if (commandMode)
    {
      // Derive an app name from the first token of the command if necessary
      NSString *firstToken = nil;
      NSScanner *sc = [NSScanner scannerWithString:commandStr];
      [sc scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&firstToken];
      if (!firstToken || [firstToken length] == 0)
        firstToken = commandStr;

      NSString *candidate = [[firstToken lastPathComponent] stringByDeletingPathExtension];

      // If user provided an explicit name via --name/-N, use that; otherwise use the derived candidate
      NSString *appNameToUse = nil;
      if (nameArg && strlen(nameArg) > 0)
        {
          appNameToUse = [NSString stringWithUTF8String:nameArg];
        }
      else
        {
          appNameToUse = candidate;
        }

      NSString *bundleName = [creator sanitizeFileName:appNameToUse];

      // Check for existing bundle and ask/overwrite depending on force
      NSString *bundlePath = [NSString stringWithFormat:@"%@/%@.app", outputDir, bundleName];
      if ([fm fileExistsAtPath:bundlePath])
        {
          if (!forceOverwrite)
            {
              fprintf(stderr, "Warning: Application bundle already exists: %s\n", [bundlePath UTF8String]);
              fprintf(stderr, "Overwrite? (y/n) "); fflush(stderr);
              int response = getchar();
              if (response != 'y' && response != 'Y')
                {
                  fprintf(stderr, "Cancelled.\n");
                  [creator release];
                  [pool release];
                  exit(EXIT_FAILURE);
                }
            }

          NSError *remErr = nil;
          if (![fm removeItemAtPath:bundlePath error:&remErr])
            {
              NSString *msg = [NSString stringWithFormat:@"Failed to remove existing bundle: %@", [remErr localizedDescription]];
              ShowErrorAlert(@"Error", msg);
              [creator release];
              [pool release];
              exit(EXIT_FAILURE);
            }
        }

      success = [creator createBundleFromCommand:commandStr appName:appNameToUse iconPath:iconPath outputDir:outputDir];
    }
  else
    {
      // Desktop file mode - reuse existing flow
      DesktopFileParser *parser = [[DesktopFileParser alloc] initWithFile:desktopFilePath];
      if (!parser)
        {
          NSString *msg = [NSString stringWithFormat:@"Failed to parse desktop file: %@", desktopFilePath];
          ShowErrorAlert(@"Error", msg);
          [creator release];
          [pool release];
          exit(EXIT_FAILURE);
        }

      NSString *appName = [parser stringForKey:@"Name"];
      [parser release];

      if (!appName)
        {
          NSString *msg = @"Desktop file has no Name field";
          ShowErrorAlert(@"Error", msg);
          [creator release];
          [pool release];
          exit(EXIT_FAILURE);
        }

      NSString *bundleName = appName;
      NSString *bundlePath = [NSString stringWithFormat:@"%@/%@.app", outputDir, bundleName];

      if ([fm fileExistsAtPath:bundlePath])
        {
          if (!forceOverwrite)
            {
              fprintf(stderr, "Warning: Application bundle already exists: %s\n", [bundlePath UTF8String]);
              fprintf(stderr, "Overwrite? (y/n) "); fflush(stderr);
              int response = getchar();
              if (response != 'y' && response != 'Y')
                {
                  fprintf(stderr, "Cancelled.\n");
                  [creator release];
                  [pool release];
                  exit(EXIT_FAILURE);
                }
            }

          NSError *remErr = nil;
          if (![fm removeItemAtPath:bundlePath error:&remErr])
            {
              NSString *msg = [NSString stringWithFormat:@"Failed to remove existing bundle: %@", [remErr localizedDescription]];
              ShowErrorAlert(@"Error", msg);
              [creator release];
              [pool release];
              exit(EXIT_FAILURE);
            }
        }

      success = [creator createBundleFromDesktopFile:desktopFilePath outputDir:outputDir];
    }

  [creator release];

  [pool release];
  exit(success ? EXIT_SUCCESS : EXIT_FAILURE);
}
