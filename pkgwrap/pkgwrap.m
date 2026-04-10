/*
 * Copyright (c) 2025-2026 Simon Peter
 * Modified by Joseph Maloney, 2026
 *
 * Based on appwrap by Simon Peter.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>

#import "PWPackageManager.h"
#import "PWBundleAssembler.h"
#import "PWLauncherGenerator.h"
#import "DesktopFileParser.h"
#import "GWBundleCreator.h"
#import "GWUtils.h"

/* Forward declaration */
static NSString *resolveElfBinaryWithDepth(NSString *execPath, NSString *rootPath,
                                           BOOL verbose, int depth);

/* Follow shell script wrapper chains to find the real ELF binary.
 * Recursively parses shell scripts, expanding simple variable assignments
 * and following exec statements until an ELF binary is found.
 * maxDepth prevents infinite loops. */
static NSString *resolveElfBinary(NSString *execPath, NSString *rootPath,
                                  BOOL verbose)
{
  return resolveElfBinaryWithDepth(execPath, rootPath, verbose, 0);
}

static NSString *resolveElfBinaryWithDepth(NSString *execPath, NSString *rootPath,
                                           BOOL verbose, int depth)
{
  if (depth > 5 || !execPath)
    return execPath;

  NSString *fullExec = [rootPath stringByAppendingPathComponent:execPath];
  NSFileManager *fm = [NSFileManager defaultManager];

  if (![fm fileExistsAtPath:fullExec])
    return execPath;

  /* Check if it's already an ELF binary */
  int fd = open([fullExec fileSystemRepresentation], O_RDONLY);
  if (fd < 0)
    return execPath;
  char hdr[4];
  ssize_t n = read(fd, hdr, 4);
  close(fd);

  if (n == 4 && hdr[0] == 0x7f && hdr[1] == 'E' &&
      hdr[2] == 'L' && hdr[3] == 'F')
    return execPath;  /* Already ELF */

  if (n < 2 || hdr[0] != '#' || hdr[1] != '!')
    return execPath;  /* Not a shell script either */

  /* Parse the shell script to find variable assignments and exec targets */
  NSString *script = [NSString stringWithContentsOfFile:fullExec
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
  if (!script)
    return execPath;

  /* Collect simple VAR=value assignments (no quotes, no spaces in value) */
  NSMutableDictionary *vars = [NSMutableDictionary dictionary];
  NSArray *lines = [script componentsSeparatedByString:@"\n"];

  for (NSString *line in lines)
    {
      NSString *t = [line stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];

      /* Skip comments and empty lines */
      if ([t length] == 0 || [t hasPrefix:@"#"])
        continue;

      /* Match VAR=value (simple assignments without export) */
      NSRange eq = [t rangeOfString:@"="];
      if (eq.location != NSNotFound && eq.location > 0)
        {
          NSString *before = [t substringToIndex:eq.location];
          /* Check it looks like a variable name (letters, digits, underscore) */
          NSCharacterSet *varChars = [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
          /* Also handle 'export VAR=value' */
          NSString *varName = before;
          if ([before hasPrefix:@"export "])
            varName = [before substringFromIndex:7];
          varName = [varName stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
          NSString *trimVar = [varName stringByTrimmingCharactersInSet:varChars];

          if ([trimVar length] == 0 && [varName length] > 0)
            {
              NSString *value = [t substringFromIndex:eq.location + 1];
              /* Strip surrounding quotes */
              if (([value hasPrefix:@"\""] && [value hasSuffix:@"\""]) ||
                  ([value hasPrefix:@"'"] && [value hasSuffix:@"'"]))
                value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];

              /* Expand known variables in the value */
              for (NSString *k in vars)
                {
                  value = [value stringByReplacingOccurrencesOfString:
                    [NSString stringWithFormat:@"$%@", k] withString:[vars objectForKey:k]];
                  value = [value stringByReplacingOccurrencesOfString:
                    [NSString stringWithFormat:@"${%@}", k] withString:[vars objectForKey:k]];
                }

              [vars setObject:value forKey:varName];
            }
        }
    }

  /* Now scan for exec statements to find the target binary */
  for (NSString *line in lines)
    {
      NSString *t = [line stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];

      if (![t hasPrefix:@"exec "])
        continue;

      /* Extract the command after exec */
      NSString *cmd = [t substringFromIndex:5];
      NSArray *tokens = [cmd componentsSeparatedByString:@" "];
      if ([tokens count] == 0)
        continue;

      NSString *target = [tokens objectAtIndex:0];

      /* Expand variables */
      for (NSString *k in vars)
        {
          target = [target stringByReplacingOccurrencesOfString:
            [NSString stringWithFormat:@"$%@", k] withString:[vars objectForKey:k]];
          target = [target stringByReplacingOccurrencesOfString:
            [NSString stringWithFormat:@"${%@}", k] withString:[vars objectForKey:k]];
        }

      /* Skip targets that still have unresolved variables */
      if ([target rangeOfString:@"$"].location != NSNotFound)
        continue;

      /* Check if this target exists in the staging root */
      NSString *fullTarget = [rootPath stringByAppendingPathComponent:target];
      if (![fm fileExistsAtPath:fullTarget])
        continue;

      if (verbose)
        fprintf(stderr, "  %s exec -> %s\n", [execPath UTF8String], [target UTF8String]);

      /* Recurse — target could be another shell script */
      return resolveElfBinaryWithDepth(target, rootPath, verbose, depth + 1);
    }

  /* No exec found — return original */
  return execPath;
}

static void print_usage(const char *prog)
{
  fprintf(stderr,
    "Usage: %s [OPTIONS] <package-name> [output-directory]\n"
    "       %s --localpkg FILE [OPTIONS] [output-directory]\n"
    "       %s --localdir DIR --name NAME --exec PATH --icon PATH [OPTIONS] [output-directory]\n"
    "\n"
    "Create a self-contained GNUstep .app bundle from a Debian/Devuan package,\n"
    "a local .deb file, or an existing directory tree.\n"
    "\n"
    "Source options (pick one):\n"
    "  <package-name>         Pull from apt repositories (default)\n"
    "      --localpkg FILE    Use a local .deb as the primary package;\n"
    "                         dependencies are resolved and downloaded from apt\n"
    "      --localdir DIR     Bundle an existing directory tree (no apt);\n"
    "                         requires --name, --exec, and --icon\n"
    "\n"
    "Options:\n"
    "  -s, --skip-list FILE   Path to package skip list (packages on the host)\n"
    "  -e, --exec PATH        Main executable path within package (e.g., /usr/bin/app)\n"
    "  -N, --name NAME        Override application name for the bundle\n"
    "  -i, --icon PATH        Override icon (path on host filesystem)\n"
    "  -L, --launch-args ARGS Extra arguments baked into the launcher exec line\n"
    "      --overlay DIR       Copy contents of DIR into bundle's Contents/\n"
    "                         (merged recursively, overwriting existing files)\n"
    "  -f, --force            Overwrite existing bundle without asking\n"
    "      --strip             Strip debug symbols from binaries\n"
    "      --keep-root         Don't delete the staging root after bundling\n"
    "      --enable-redirect   Force LD_PRELOAD path redirect in launcher\n"
    "      --no-redirect       Disable LD_PRELOAD path redirect in launcher\n"
    "  -v, --verbose          Show detailed progress\n"
    "  -h, --help             Show this help\n"
    "\n"
    "The skip list is a text file with one package name per line.\n"
    "Packages in this list are assumed to be on the host system and\n"
    "will not be installed into the staging root. Generate from a\n"
    "Gershwin live ISO with: dpkg-query -W -f '${Package}\\n'\n",
    prog, prog, prog);
}

int main(int argc, char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  /* Minimal NSApplication for AppKit image operations (icon rasterization).
   * Only initialize if a display is available; pkgwrap works without it. */
  if (getenv("DISPLAY"))
    {
      [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NSApplicationSuppressPSN"];
      (void)[NSApplication sharedApplication];
    }
  setenv("APPWRAP_NO_GUI", "1", 0);

  BOOL forceOverwrite = NO;
  BOOL verbose = NO;
  BOOL doStrip = NO;
  BOOL keepRoot = NO;
  int redirectOverride = 0;  /* 0=auto, 1=force-on, -1=force-off */
  char *skipListArg = NULL;
  char *execArg = NULL;
  char *nameArg = NULL;
  char *iconArg = NULL;
  char *launchArgsArg = NULL;
  char *localPkgArg = NULL;
  char *localDirArg = NULL;
  char *overlayArg = NULL;

  static struct option long_options[] = {
    {"skip-list",        required_argument, 0, 's'},
    {"exec",             required_argument, 0, 'e'},
    {"name",             required_argument, 0, 'N'},
    {"icon",             required_argument, 0, 'i'},
    {"launch-args",      required_argument, 0, 'L'},
    {"localpkg",         required_argument, 0, 'P'},
    {"localdir",         required_argument, 0, 'T'},
    {"overlay",          required_argument, 0, 'O'},
    {"force",            no_argument,       0, 'f'},
    {"strip",            no_argument,       0, 'S'},
    {"keep-root",        no_argument,       0, 'K'},
    {"enable-redirect",  no_argument,       0, 'R'},
    {"no-redirect",      no_argument,       0, 'D'},
    {"verbose",          no_argument,       0, 'v'},
    {"help",             no_argument,       0, 'h'},
    {0, 0, 0, 0}
  };

  int opt;
  int option_index = 0;
  while ((opt = getopt_long(argc, argv, "s:e:N:i:L:fvh", long_options, &option_index)) != -1)
    {
      switch (opt)
        {
        case 's': skipListArg = optarg; break;
        case 'e': execArg = optarg; break;
        case 'N': nameArg = optarg; break;
        case 'i': iconArg = optarg; break;
        case 'L': launchArgsArg = optarg; break;
        case 'P': localPkgArg = optarg; break;
        case 'T': localDirArg = optarg; break;
        case 'O': overlayArg = optarg; break;
        case 'f': forceOverwrite = YES; break;
        case 'S': doStrip = YES; break;
        case 'K': keepRoot = YES; break;
        case 'R': redirectOverride = 1; break;
        case 'D': redirectOverride = -1; break;
        case 'v': verbose = YES; break;
        case 'h':
          print_usage(argv[0]);
          [pool release];
          exit(EXIT_SUCCESS);
        default:
          print_usage(argv[0]);
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  /* ── Determine source mode ── */
  NSString *localPkgPath = localPkgArg
    ? [[NSString stringWithUTF8String:localPkgArg] stringByExpandingTildeInPath]
    : nil;
  NSString *localDirPath = localDirArg
    ? [[NSString stringWithUTF8String:localDirArg] stringByExpandingTildeInPath]
    : nil;

  NSString *packageName = nil;
  NSString *outputDir = nil;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;

  if (localDirPath)
    {
      /* --localdir mode: requires --name, --exec, --icon */
      if (!nameArg)
        {
          fprintf(stderr, "Error: --localdir requires --name\n");
          [pool release];
          exit(EXIT_FAILURE);
        }
      if (!execArg)
        {
          fprintf(stderr, "Error: --localdir requires --exec\n");
          [pool release];
          exit(EXIT_FAILURE);
        }
      if (!iconArg)
        {
          fprintf(stderr, "Error: --localdir requires --icon\n");
          [pool release];
          exit(EXIT_FAILURE);
        }
      if (![fm fileExistsAtPath:localDirPath])
        {
          fprintf(stderr, "Error: directory '%s' not found\n",
                  [localDirPath UTF8String]);
          [pool release];
          exit(EXIT_FAILURE);
        }
      packageName = [NSString stringWithUTF8String:nameArg];
    }
  else if (localPkgPath)
    {
      /* --localpkg mode: extract package name from the .deb */
      if (![fm fileExistsAtPath:localPkgPath])
        {
          fprintf(stderr, "Error: file '%s' not found\n",
                  [localPkgPath UTF8String]);
          [pool release];
          exit(EXIT_FAILURE);
        }
      /* Get the package name from the deb's control data */
      NSString *pkgField = nil;
      {
        NSTask *dpkgTask = [[NSTask alloc] init];
        NSPipe *dpkgPipe = [NSPipe pipe];
        [dpkgTask setLaunchPath:@"/usr/bin/dpkg-deb"];
        [dpkgTask setArguments:@[@"-f", localPkgPath, @"Package"]];
        [dpkgTask setStandardOutput:dpkgPipe];
        [dpkgTask setStandardError:[NSPipe pipe]];
        [dpkgTask launch];
        NSData *dpkgData = [[dpkgPipe fileHandleForReading] readDataToEndOfFile];
        [dpkgTask waitUntilExit];
        pkgField = [[[NSString alloc] initWithData:dpkgData
                      encoding:NSUTF8StringEncoding] autorelease];
        [dpkgTask release];
      }
      if (pkgField)
        pkgField = [pkgField stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (!pkgField || [pkgField length] == 0)
        {
          fprintf(stderr, "Error: could not read Package field from '%s'\n",
                  [localPkgPath UTF8String]);
          [pool release];
          exit(EXIT_FAILURE);
        }
      packageName = pkgField;
    }
  else
    {
      /* Default apt mode: package name is a positional argument */
      if (optind >= argc)
        {
          fprintf(stderr, "Error: package name required\n");
          print_usage(argv[0]);
          [pool release];
          exit(EXIT_FAILURE);
        }
      packageName = [NSString stringWithUTF8String:argv[optind]];
    }

  /* Output directory: next positional arg, or home directory */
  if (localDirPath || localPkgPath)
    {
      if (optind < argc)
        outputDir = [NSString stringWithUTF8String:argv[optind]];
      else
        outputDir = NSHomeDirectory();
    }
  else
    {
      if (optind + 1 < argc)
        outputDir = [NSString stringWithUTF8String:argv[optind + 1]];
      else
        outputDir = NSHomeDirectory();
    }

  outputDir = [outputDir stringByExpandingTildeInPath];

  /* Create output directory if needed */
  if (![fm fileExistsAtPath:outputDir])
    {
      if (![fm createDirectoryAtPath:outputDir
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:&error])
        {
          fprintf(stderr, "Failed to create output directory %s: %s\n",
                  [outputDir UTF8String], [[error localizedDescription] UTF8String]);
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  /* ── Phase 1: Resolve, download, and extract package ── */
  PWPackageManager *pm = nil;

  if (localDirPath)
    {
      /* --localdir: skip all package management, use directory as-is */
      fprintf(stderr, "pkgwrap: bundling directory '%s' as '%s'\n",
              [localDirPath UTF8String], [packageName UTF8String]);

      /* Create a minimal PWPackageManager just to hold the root path.
       * The root path IS the user-supplied directory. */
      pm = [[PWPackageManager alloc] initWithPackage:packageName
                                              verbose:verbose];
      [pm setLocalRootPath:localDirPath];
    }
  else
    {
      if (localPkgPath)
        fprintf(stderr, "pkgwrap: bundling local package '%s' (%s)\n",
                [packageName UTF8String], [localPkgPath UTF8String]);
      else
        fprintf(stderr, "pkgwrap: bundling '%s'\n", [packageName UTF8String]);

      pm = [[PWPackageManager alloc] initWithPackage:packageName
                                              verbose:verbose];

      /* Load skip list if provided */
      NSString *skipListPath = skipListArg
        ? [[NSString stringWithUTF8String:skipListArg] stringByExpandingTildeInPath]
        : nil;

      /* Also check for a default skip list in Resources/ */
      if (!skipListPath)
        {
          NSString *defaultSkipList = @"/System/Library/pkgwrap/gershwin-base-packages.txt";
          if ([fm fileExistsAtPath:defaultSkipList])
            skipListPath = defaultSkipList;
        }

      if (skipListPath)
        {
          if (![pm loadSkipList:skipListPath])
            {
              fprintf(stderr, "Warning: could not load skip list\n");
            }
        }

      if (![pm setupStagingRoot])
        {
          fprintf(stderr, "Failed to create staging directory\n");
          [pm release];
          [pool release];
          exit(EXIT_FAILURE);
        }

      if (localPkgPath)
        {
          /* --localpkg: resolve deps from the deb's Depends field, then
           * copy the local deb into the cache and download the rest. */
          if (![pm resolveDependenciesForLocalDeb:localPkgPath])
            {
              fprintf(stderr, "Failed to resolve dependencies for '%s'\n",
                      [localPkgPath UTF8String]);
              if (!keepRoot) [pm cleanup];
              [pm release];
              [pool release];
              exit(EXIT_FAILURE);
            }
        }
      else
        {
          if (![pm resolveDependencies])
            {
              fprintf(stderr, "Failed to resolve dependencies for '%s'\n",
                      [packageName UTF8String]);
              if (!keepRoot) [pm cleanup];
              [pm release];
              [pool release];
              exit(EXIT_FAILURE);
            }
        }

      if (![pm downloadPackages])
        {
          fprintf(stderr, "Failed to download packages\n");
          if (!keepRoot) [pm cleanup];
          [pm release];
          [pool release];
          exit(EXIT_FAILURE);
        }

      if (![pm extractPackages])
        {
          fprintf(stderr, "Failed to extract packages\n");
          if (!keepRoot) [pm cleanup];
          [pm release];
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  /* ── Phase 2: Discover application metadata ── */
  NSString *desktopPath = [pm findDesktopFile];
  NSString *appName = nil;
  NSString *iconName = nil;
  NSString *execCommand = nil;
  DesktopFileParser *parser = nil;

  if (desktopPath)
    {
      if (verbose)
        fprintf(stderr, "Found desktop file: %s\n", [desktopPath UTF8String]);

      parser = [[DesktopFileParser alloc] initWithFile:desktopPath];
      if (parser)
        {
          appName = [parser stringForKey:@"Name"];
          iconName = [parser stringForKey:@"Icon"];
          execCommand = [parser stringForKey:@"Exec"];
        }
    }

  /* Override name if provided */
  if (nameArg)
    appName = [NSString stringWithUTF8String:nameArg];

  /* Fallback app name to package name with capitalised first letter */
  if (!appName || [appName length] == 0)
    {
      appName = [[[packageName substringToIndex:1] uppercaseString]
                  stringByAppendingString:[packageName substringFromIndex:1]];
    }

  NSString *bundleName = [GWUtils sanitizeFileName:appName];

  /* Determine the main executable path (relative to root) */
  NSString *mainExec = nil;
  if (execArg)
    {
      mainExec = [NSString stringWithUTF8String:execArg];
    }
  else if (execCommand)
    {
      /* Extract the binary path from the Exec= field.
       * Strip field codes and take the first token. */
      NSString *sanitized = [GWUtils sanitizeExecCommand:execCommand];
      NSScanner *sc = [NSScanner scannerWithString:sanitized];
      NSString *firstToken = nil;
      [sc scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet]
                         intoString:&firstToken];
      if (firstToken)
        mainExec = firstToken;
    }

  /* If mainExec is a bare command (no path), resolve it within the staging root */
  if (mainExec && ![mainExec hasPrefix:@"/"])
    {
      NSArray *searchDirs = @[@"/usr/bin", @"/usr/sbin", @"/bin", @"/sbin",
                              @"/usr/games"];
      NSString *found = nil;
      for (NSString *dir in searchDirs)
        {
          NSString *candidate = [NSString stringWithFormat:@"%@/%@", dir, mainExec];
          NSString *fullCandidate = [[pm rootPath] stringByAppendingPathComponent:candidate];
          if ([fm fileExistsAtPath:fullCandidate])
            {
              found = candidate;
              break;
            }
        }
      if (found)
        mainExec = found;
      else
        mainExec = [NSString stringWithFormat:@"/usr/bin/%@", mainExec];
    }

  /* Fallback: look for executable matching package name */
  if (!mainExec)
    {
      NSString *candidate = [NSString stringWithFormat:@"/usr/bin/%@", packageName];
      NSString *fullCandidate = [[pm rootPath] stringByAppendingPathComponent:candidate];
      if ([fm fileExistsAtPath:fullCandidate])
        mainExec = candidate;
    }

  if (!mainExec)
    {
      fprintf(stderr, "Could not determine main executable.\n"
                      "Use --exec to specify it (e.g., --exec /usr/bin/chromium)\n");
      if (!keepRoot) [pm cleanup];
      [parser release];
      [pm release];
      [pool release];
      exit(EXIT_FAILURE);
    }

  /* If mainExec is a shell script wrapper, follow the chain of scripts
   * until we find the real ELF binary.  This avoids problems with
   * hardcoded paths in Debian wrapper scripts. */
  mainExec = resolveElfBinary(mainExec, [pm rootPath], verbose);

  /* Detect Chromium/Electron-based applications by scanning the staging
   * root for telltale files.  These apps need --no-sandbox on FreeBSD
   * because the linuxulator lacks clone3/user namespace support. */
  BOOL isChromiumBased = NO;
  {
    NSArray *chromiumSignatures = @[
      @"chrome-sandbox",
      @"chrome_crashpad_handler",
      @"chrome_100_percent.pak",
      @"libcef.so",
      @"resources/app.asar",
      @"snapshot_blob.bin"
    ];

    NSString *rootPath = [pm rootPath];
    NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:rootPath];
    NSString *relPath;
    while ((relPath = [dirEnum nextObject]))
      {
        NSString *lastComponent = [relPath lastPathComponent];
        for (NSString *sig in chromiumSignatures)
          {
            if ([lastComponent isEqualToString:sig] ||
                [relPath hasSuffix:sig])
              {
                isChromiumBased = YES;
                if (verbose)
                  fprintf(stderr, "Detected Chromium/Electron app (found %s)\n",
                          [sig UTF8String]);
                break;
              }
          }
        if (isChromiumBased)
          break;
      }
  }

  NSString *launchArgs = launchArgsArg
    ? [NSString stringWithUTF8String:launchArgsArg]
    : nil;

  /* Decide whether the LD_PRELOAD redirect library should be enabled.
   * Auto-detection: disable for Qt6 apps (Qt6 + Mesa/EGL crashes with
   * open() interception via LD_PRELOAD).  Enable for apps with hardcoded
   * absolute paths (like GIMP) that have no env var override.
   * Manual override via --enable-redirect / --no-redirect. */
  BOOL needsRedirect = NO;  /* default off — env vars cover most cases */
  if (redirectOverride == 1)
    {
      needsRedirect = YES;
    }
  else if (redirectOverride == -1)
    {
      needsRedirect = NO;
    }
  else
    {
      /* Auto-detect: check for Qt6 linkage which crashes with LD_PRELOAD */
      NSString *rootPath = [pm rootPath];
      NSString *fullExec = [rootPath stringByAppendingPathComponent:mainExec];
      BOOL hasQt6 = NO;

      NSTask *lddTask = [[NSTask alloc] init];
      NSPipe *lddPipe = [NSPipe pipe];
      [lddTask setLaunchPath:@"/usr/bin/ldd"];
      [lddTask setArguments:@[fullExec]];
      [lddTask setStandardOutput:lddPipe];
      [lddTask setStandardError:[NSPipe pipe]];
      [lddTask launch];
      [lddTask waitUntilExit];
      NSData *lddData = [[lddPipe fileHandleForReading] readDataToEndOfFile];
      NSString *lddOutput = [[[NSString alloc] initWithData:lddData
                               encoding:NSUTF8StringEncoding] autorelease];
      [lddTask release];

      if ([lddOutput rangeOfString:@"libQt6Core"].location != NSNotFound ||
          [lddOutput rangeOfString:@"libQt6Gui"].location != NSNotFound)
        hasQt6 = YES;

      if (hasQt6)
        {
          needsRedirect = NO;
          if (verbose)
            fprintf(stderr, "Qt6 app detected — disabling LD_PRELOAD redirect "
                            "(known crash with Qt6/Mesa open() interception)\n");
        }
    }

  if (verbose)
    {
      fprintf(stderr, "Application: %s\nExecutable: %s\n",
              [appName UTF8String], [mainExec UTF8String]);
      if (isChromiumBased)
        fprintf(stderr, "Chromium-based: yes (--no-sandbox on FreeBSD)\n");
      if (launchArgs)
        fprintf(stderr, "Extra launch args: %s\n", [launchArgs UTF8String]);
      fprintf(stderr, "LD_PRELOAD redirect: %s\n",
              needsRedirect ? "enabled" : "disabled");
    }

  /* ── Phase 3: Check for existing squashfs output ── */
  NSString *squashfsPath = [NSString stringWithFormat:@"%@/%@.squashfs",
                             outputDir, bundleName];

  if ([fm fileExistsAtPath:squashfsPath])
    {
      if (!forceOverwrite)
        {
          fprintf(stderr, "Output already exists: %s\nOverwrite? (y/n) ",
                  [squashfsPath UTF8String]);
          fflush(stderr);
          int response = getchar();
          if (response != 'y' && response != 'Y')
            {
              fprintf(stderr, "Cancelled.\n");
              if (!keepRoot) [pm cleanup];
              [parser release];
              [pm release];
              [pool release];
              exit(EXIT_FAILURE);
            }
        }

      if (![fm removeItemAtPath:squashfsPath error:&error])
        {
          fprintf(stderr, "Failed to remove existing file: %s\n",
                  [[error localizedDescription] UTF8String]);
          if (!keepRoot) [pm cleanup];
          [parser release];
          [pm release];
          [pool release];
          exit(EXIT_FAILURE);
        }
    }

  /* Create a temporary build directory in the user's home.
   * The .app bundle is built inside this dir, then the whole dir
   * is compressed into a squashfs so that when mounted the user
   * sees the .app bundle (not its raw contents). */
  char buildTmpl[PATH_MAX];
  snprintf(buildTmpl, sizeof(buildTmpl), "%s/pkgwrap-build-XXXXXX",
           [NSHomeDirectory() UTF8String]);
  char *buildResult = mkdtemp(buildTmpl);
  if (!buildResult)
    {
      fprintf(stderr, "Failed to create temporary build directory\n");
      if (!keepRoot) [pm cleanup];
      [parser release];
      [pm release];
      [pool release];
      exit(EXIT_FAILURE);
    }
  NSString *buildDir = [NSString stringWithUTF8String:buildResult];
  NSString *bundlePath = [NSString stringWithFormat:@"%@/%@.app", buildDir, bundleName];

  /* ── Phase 4: Assemble the bundle ── */
  fprintf(stderr, "Assembling bundle: %s\n", [bundlePath UTF8String]);

  PWBundleAssembler *assembler = [[PWBundleAssembler alloc]
    initWithAppName:bundleName
           rootPath:[pm rootPath]
         bundlePath:bundlePath
            verbose:verbose
              strip:doStrip];

  if (![assembler assembleBundle])
    {
      fprintf(stderr, "Failed to assemble bundle\n");
      if (!keepRoot) [pm cleanup];
      [assembler release];
      [parser release];
      [pm release];
      [pool release];
      exit(EXIT_FAILURE);
    }

  /* ── Phase 4b: Apply overlay directory ── */
  if (overlayArg)
    {
      NSString *overlayPath = [[NSString stringWithUTF8String:overlayArg]
                                stringByExpandingTildeInPath];
      NSString *contentsPath = [bundlePath stringByAppendingPathComponent:@"Contents"];

      if (![fm fileExistsAtPath:overlayPath])
        {
          fprintf(stderr, "Warning: overlay directory '%s' not found, skipping\n",
                  [overlayPath UTF8String]);
        }
      else
        {
          fprintf(stderr, "Applying overlay from %s...\n", [overlayPath UTF8String]);

          /* Use cp -a to recursively merge, overwriting existing files */
          NSTask *cpTask = [[NSTask alloc] init];
          [cpTask setLaunchPath:@"/bin/cp"];
          [cpTask setArguments:@[@"-a", @"-f",
            [overlayPath stringByAppendingString:@"/."],
            contentsPath]];
          [cpTask launch];
          [cpTask waitUntilExit];

          if ([cpTask terminationStatus] != 0)
            fprintf(stderr, "Warning: overlay copy had errors\n");
          else if (verbose)
            fprintf(stderr, "Overlay applied successfully\n");

          [cpTask release];
        }
    }

  /* ── Phase 5: Generate launcher script ── */
  NSString *launcherPath = [NSString stringWithFormat:@"%@/%@", bundlePath, bundleName];

  if (![PWLauncherGenerator generateLauncherAtPath:launcherPath
                                           appName:bundleName
                                          mainExec:mainExec
                                     chromiumBased:isChromiumBased
                                     needsRedirect:needsRedirect
                                        launchArgs:launchArgs])
    {
      fprintf(stderr, "Failed to generate launcher script\n");
      if (!keepRoot) [pm cleanup];
      [assembler release];
      [parser release];
      [pm release];
      [pool release];
      exit(EXIT_FAILURE);
    }

  /* ── Phase 6: Icon and metadata ── */
  NSString *resourcesPath = [bundlePath stringByAppendingPathComponent:@"Resources"];
  NSString *copiedIconFilename = nil;

  /* Find and copy icon */
  NSString *resolvedIcon = nil;
  if (iconArg)
    {
      resolvedIcon = [[NSString stringWithUTF8String:iconArg] stringByExpandingTildeInPath];
    }
  else if (iconName)
    {
      resolvedIcon = [assembler findIconInRoot:iconName];
    }

  if (resolvedIcon)
    {
      GWBundleCreator *creator = [[GWBundleCreator alloc] init];
      copiedIconFilename = [creator copyIconToBundle:resolvedIcon
                                    toBundleResources:resourcesPath
                                             appName:bundleName];
      [creator release];

      if (verbose && copiedIconFilename)
        fprintf(stderr, "Icon: %s\n", [copiedIconFilename UTF8String]);
    }

  /* Create Info.plist.
   * When no display is available, create it directly to avoid
   * AppKit calls in GWDocumentIcon that require a window server.
   * When a display IS available, use GWBundleCreator for full
   * document-type icon generation. */
  @try
    {
      if (getenv("DISPLAY"))
        {
          GWBundleCreator *plistCreator = [[GWBundleCreator alloc] init];
          if (![plistCreator createInfoPlist:bundlePath
                                 desktopInfo:parser
                                     appName:bundleName
                                   execPath:mainExec
                               iconFilename:copiedIconFilename])
            {
              fprintf(stderr, "Warning: failed to create Info.plist\n");
            }
          [plistCreator release];
        }
      else
        {
          /* Headless: write a basic Info.plist without document type icons */
          NSMutableDictionary *plist = [NSMutableDictionary dictionary];
          [plist setObject:@"8.0" forKey:@"NSAppVersion"];
          [plist setObject:bundleName forKey:@"NSExecutable"];
          [plist setObject:appName forKey:@"NSApplicationName"];
          [plist setObject:@"1.0" forKey:@"NSApplicationVersion"];
          [plist setObject:appName forKey:@"CFBundleName"];
          if (copiedIconFilename)
            [plist setObject:[copiedIconFilename lastPathComponent] forKey:@"NSIcon"];

          NSString *plistPath = [NSString stringWithFormat:@"%@/Resources/Info.plist",
                                  bundlePath];
          if (![plist writeToFile:plistPath atomically:YES])
            fprintf(stderr, "Warning: failed to write Info.plist\n");
        }
    }
  @catch (NSException *exception)
    {
      fprintf(stderr, "Warning: Info.plist creation failed: %s (%s)\n",
              [[exception reason] UTF8String], [[exception name] UTF8String]);
    }

  /* ── Phase 7: Create squashfs image ── */
  fprintf(stderr, "Creating squashfs image...\n");

  NSString *mksquashfs = @"/usr/bin/mksquashfs";
  if (![fm fileExistsAtPath:mksquashfs])
    {
      fprintf(stderr, "mksquashfs not found. Install squashfs-tools.\n");
      [fm removeItemAtPath:buildDir error:NULL];
      if (!keepRoot) [pm cleanup];
      [assembler release];
      [parser release];
      [pm release];
      [pool release];
      exit(EXIT_FAILURE);
    }

  NSTask *sqfs = [[NSTask alloc] init];
  [sqfs setLaunchPath:mksquashfs];
  [sqfs setArguments:@[buildDir, squashfsPath,
                       @"-comp", @"zstd",
                       @"-Xcompression-level", @"19",
                       @"-noappend"]];
  if (!verbose)
    {
      NSFileHandle *devNull = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
      [sqfs setStandardOutput:devNull];
    }
  [sqfs launch];
  [sqfs waitUntilExit];

  if ([sqfs terminationStatus] != 0)
    {
      fprintf(stderr, "mksquashfs failed (exit %d)\n", [sqfs terminationStatus]);
      [sqfs release];
      [fm removeItemAtPath:buildDir error:NULL];
      if (!keepRoot) [pm cleanup];
      [assembler release];
      [parser release];
      [pm release];
      [pool release];
      exit(EXIT_FAILURE);
    }
  [sqfs release];

  /* Remove the temporary build directory */
  [fm removeItemAtPath:buildDir error:NULL];

  /* ── Phase 8: Cleanup staging root ── */
  if (keepRoot)
    fprintf(stderr, "Staging root kept at: %s\n", [[pm rootPath] UTF8String]);
  else
    [pm cleanup];

  /* Report success */
  fprintf(stderr, "\nSuccessfully created: %s\n", [squashfsPath UTF8String]);

  /* Show squashfs size */
  NSDictionary *sqfsAttrs = [fm attributesOfItemAtPath:squashfsPath error:NULL];
  if (sqfsAttrs)
    {
      unsigned long long size = [sqfsAttrs fileSize];
      if (size > 1073741824)
        fprintf(stderr, "Image size: %.1f GB\n", size / 1073741824.0);
      else
        fprintf(stderr, "Image size: %.1f MB\n", size / 1048576.0);
    }

  [assembler release];
  [parser release];
  [pm release];
  [pool release];
  exit(EXIT_SUCCESS);
}
