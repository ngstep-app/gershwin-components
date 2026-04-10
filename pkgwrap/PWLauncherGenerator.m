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

  /* Library paths - cover all Debian library locations including
   * subdirectories (e.g., pulseaudio/, pipewire/, private/) */
  [script appendString:@"# Library search paths\n"];
  [script appendFormat:
    @"_LP=\"${C}/usr/lib/%@:${C}/usr/lib:${C}/lib/%@:${C}/lib\"\n"
    @"for _d in \"${C}/usr/lib/%@\"/*/  \"${C}/usr/lib\"/*/; do\n"
    @"    [ -d \"$_d\" ] && _LP=\"${_LP}:${_d%%/}\"\n"
    @"done\n"
    @"export LD_LIBRARY_PATH=\"${_LP}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\"\n\n",
    multiarch, multiarch, multiarch];

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

  [script appendString:@"# babl extensions (GIMP)\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/babl-0.1\" ] && \\\n", multiarch];
  [script appendFormat:@"    export BABL_PATH=\"${C}/usr/lib/%@/babl-0.1\"\n\n", multiarch];

  [script appendString:@"# GEGL operations (GIMP)\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/gegl-0.4\" ] && \\\n", multiarch];
  [script appendFormat:@"    export GEGL_PATH=\"${C}/usr/lib/%@/gegl-0.4\"\n\n", multiarch];

  [script appendString:@"# GStreamer plugins\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/gstreamer-1.0\" ] && \\\n", multiarch];
  [script appendFormat:@"    export GST_PLUGIN_PATH=\"${C}/usr/lib/%@/gstreamer-1.0\"\n\n", multiarch];

  [script appendString:@"# Mesa/DRI drivers\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/dri\" ] && \\\n", multiarch];
  [script appendFormat:@"    export LIBGL_DRIVERS_PATH=\"${C}/usr/lib/%@/dri\"\n\n", multiarch];

  [script appendString:@"# Pango modules\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/pango\" ] && \\\n", multiarch];
  [script appendFormat:@"    export PANGO_LIBDIR=\"${C}/usr/lib/%@\"\n\n", multiarch];

  [script appendString:@"# GObject introspection typelibs\n"];
  [script appendFormat:@"[ -d \"${C}/usr/lib/%@/girepository-1.0\" ] && \\\n", multiarch];
  [script appendFormat:@"    export GI_TYPELIB_PATH=\"${C}/usr/lib/%@/girepository-1.0\"\n\n", multiarch];

  /* Filter GNUstep-specific arguments (same as appwrap) */
  [script appendString:@"# Filter GNUstep arguments\n"];
  [script appendString:@"for arg do\n"];
  [script appendString:@"    shift\n"];
  [script appendString:@"    [ \"$arg\" = \"-GSFilePath\" ] && continue\n"];
  [script appendString:@"    set -- \"$@\" \"$arg\"\n"];
  [script appendString:@"done\n\n"];

  /* Locate the bundled ld-linux dynamic linker.  Use it to invoke binaries
   * so the bundle is fully self-contained — works on any Linux distro
   * (even musl-based or older glibc) and on FreeBSD via linuxulator. */
  [script appendString:@"# Locate bundled dynamic linker\n"];
  [script appendFormat:
    @"LD_LINUX=\"\"\n"
    @"for f in \"${C}/lib/%@/ld-linux\"*.so.* \"${C}/lib64/ld-linux\"*.so.* \"${C}/lib/ld-linux\"*.so.*; do\n"
    @"    [ -f \"$f\" ] && LD_LINUX=\"$f\" && break\n"
    @"done\n\n",
    multiarch];

  [script appendString:@"# Execute the main binary\n"];
  [script appendFormat:
    @"MAIN=\"${C}%@\"\n"
    @"if [ -n \"$LD_LINUX\" ]; then\n"
    @"    if head -c4 \"$MAIN\" 2>/dev/null | grep -q ELF; then\n"
    @"        exec \"$LD_LINUX\" \"$MAIN\" \"$@\"\n"
    @"    else\n"
    @"        exec \"$LD_LINUX\" \"${C}/usr/bin/bash\" \"$MAIN\" \"$@\"\n"
    @"    fi\n"
    @"fi\n"
    @"exec \"$MAIN\" \"$@\"\n",
    mainExec];

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
