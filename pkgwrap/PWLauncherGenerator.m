/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PWLauncherGenerator.h"

@implementation PWLauncherGenerator

+ (BOOL)generateLauncherAtPath:(NSString *)launcherPath
                       appName:(NSString *)appName
                      mainExec:(NSString *)mainExec
{
  /* Determine multi-arch triplet from the host */
  NSString *multiarch = nil;
  NSTask *task = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  [task setLaunchPath:@"/usr/bin/dpkg"];
  [task setArguments:@[@"--print-architecture"]];
  [task setStandardOutput:pipe];
  [task setStandardError:[NSPipe pipe]];
  [task launch];
  [task waitUntilExit];
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *arch = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  [task release];

  if ([arch isEqualToString:@"amd64"])
    multiarch = @"x86_64-linux-gnu";
  else if ([arch isEqualToString:@"arm64"])
    multiarch = @"aarch64-linux-gnu";
  else if ([arch isEqualToString:@"i386"])
    multiarch = @"i386-linux-gnu";
  else if ([arch isEqualToString:@"armhf"])
    multiarch = @"arm-linux-gnueabihf";
  else
    multiarch = @"x86_64-linux-gnu";

  /* Build the launcher script.
   * The script sets up environment variables so that libraries and data
   * files within the bundle are found before (or instead of) the system ones.
   * It preserves the Debian filesystem layout under Contents/, so
   * LD_LIBRARY_PATH covers the standard library directories. */
  NSMutableString *script = [NSMutableString string];

  [script appendString:@"#!/bin/sh\n"];
  [script appendFormat:@"# Auto-generated launcher for %@\n", appName];
  [script appendString:@"# Created by pkgwrap\n\n"];

  /* Resolve bundle directory */
  [script appendString:@"BUNDLE=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\n"];
  [script appendString:@"C=\"${BUNDLE}/Contents\"\n\n"];

  /* Library paths - cover all Debian library locations */
  [script appendString:@"# Library search paths\n"];
  [script appendFormat:
    @"export LD_LIBRARY_PATH="
    @"\"${C}/usr/lib/%@"
    @":${C}/usr/lib"
    @":${C}/lib/%@"
    @":${C}/lib"
    @"${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\"\n\n",
    multiarch, multiarch];

  /* PATH for helper binaries */
  [script appendString:@"# Executable search path\n"];
  [script appendString:@"export PATH=\"${C}/usr/bin:${C}/usr/sbin:${PATH}\"\n\n"];

  /* XDG data dirs for app resources, icons, mime types */
  [script appendString:@"# Application data\n"];
  [script appendString:@"export XDG_DATA_DIRS=\"${C}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\"\n\n"];

  /* Toolkit-specific environment variables (set only if dirs exist) */
  [script appendString:@"# Fontconfig\n"];
  [script appendString:@"[ -d \"${C}/etc/fonts\" ] && export FONTCONFIG_PATH=\"${C}/etc/fonts\"\n\n"];

  [script appendString:@"# GIO modules\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/gio/modules\" ] && \\\n", multiarch];
  [script appendFormat:@"    export GIO_MODULE_DIR=\"${C}/usr/lib/%@/gio/modules\"\n\n", multiarch];

  [script appendString:@"# GTK modules\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/gtk-3.0\" ] && \\\n", multiarch];
  [script appendFormat:@"    export GTK_PATH=\"${C}/usr/lib/%@/gtk-3.0\"\n\n", multiarch];

  [script appendString:@"# GDK pixbuf loaders\n"];
  [script appendFormat:
    @"PIXBUF_CACHE=\"${C}/usr/lib/%@/gdk-pixbuf-2.0/2.10.0/loaders.cache\"\n"
    @"[ -f \"${PIXBUF_CACHE}\" ] && export GDK_PIXBUF_MODULE_FILE=\"${PIXBUF_CACHE}\"\n\n",
    multiarch];

  [script appendString:@"# Qt plugins\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/qt5/plugins\" ] && \\\n", multiarch];
  [script appendFormat:@"    export QT_PLUGIN_PATH=\"${C}/usr/lib/%@/qt5/plugins\"\n\n", multiarch];

  /* Filter GNUstep-specific arguments (same as appwrap) */
  [script appendString:@"# Filter GNUstep arguments\n"];
  [script appendString:@"for arg do\n"];
  [script appendString:@"    shift\n"];
  [script appendString:@"    [ \"$arg\" = \"-GSFilePath\" ] && continue\n"];
  [script appendString:@"    set -- \"$@\" \"$arg\"\n"];
  [script appendString:@"done\n\n"];

  /* Execute the main binary */
  [script appendFormat:@"exec \"${C}%@\" \"$@\"\n", mainExec];

  /* Write the script */
  NSError *error = nil;
  if (![script writeToFile:launcherPath
                atomically:YES
                  encoding:NSUTF8StringEncoding
                     error:&error])
    {
      fprintf(stderr, "Failed to write launcher: %s\n",
              [[error localizedDescription] UTF8String]);
      return NO;
    }

  /* Make executable */
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm setAttributes:@{NSFilePosixPermissions: @(0755)}
            ofItemAtPath:launcherPath
                   error:&error])
    {
      fprintf(stderr, "Failed to set launcher permissions: %s\n",
              [[error localizedDescription] UTF8String]);
      return NO;
    }

  return YES;
}

@end
