/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PWPackageManager.h"
#import "GWUtils.h"
#include <stdlib.h>
#include <limits.h>

/* Helper: run a command and capture stdout as a string.
 * Reads pipe BEFORE waiting for exit to avoid deadlock when
 * the output exceeds the pipe buffer size (~64KB). */
static NSString *runCommand(NSString *launchPath, NSArray *arguments)
{
  NSTask *task = [[NSTask alloc] init];
  NSPipe *outPipe = [NSPipe pipe];
  [task setLaunchPath:launchPath];
  [task setArguments:arguments];
  [task setStandardOutput:outPipe];
  [task setStandardError:[NSPipe pipe]];
  [task launch];
  NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
  [task waitUntilExit];
  [task release];
  return [[[NSString alloc] initWithData:data
                                encoding:NSUTF8StringEncoding] autorelease];
}

/* Helper: run a command, return exit status.
 * When suppressing output, redirect to /dev/null instead of a pipe
 * to avoid deadlocks when the output exceeds the pipe buffer. */
static int runCommandStatus(NSString *launchPath, NSArray *arguments,
                            BOOL showOutput)
{
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:launchPath];
  [task setArguments:arguments];
  if (!showOutput)
    {
      NSFileHandle *devNull = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
      [task setStandardOutput:devNull];
      [task setStandardError:devNull];
    }
  [task launch];
  [task waitUntilExit];
  int status = [task terminationStatus];
  [task release];
  return status;
}

@implementation PWPackageManager
{
  NSMutableArray *_resolvedPackages;
  NSString *_debCachePath;
  NSString *_localDebPath;
  BOOL _localDirMode;
}

- (instancetype)initWithPackage:(NSString *)package verbose:(BOOL)verbose
{
  self = [super init];
  if (self)
    {
      _packageName = [package copy];
      _rootPath = nil;
      _debCachePath = nil;
      _skipPackages = [[NSMutableSet alloc] init];
      _resolvedPackages = [[NSMutableArray alloc] init];
      _verbose = verbose;

      /* Detect host architecture */
      NSString *arch = runCommand(@"/usr/bin/dpkg", @[@"--print-architecture"]);
      _arch = [[arch stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];
      if (!_arch || [_arch length] == 0)
        _arch = [@"amd64" retain];
    }
  return self;
}

- (BOOL)loadSkipList:(NSString *)path
{
  if (!path)
    return YES;

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path])
    {
      if (_verbose)
        fprintf(stderr, "Skip list not found: %s (proceeding without it)\n",
                [path UTF8String]);
      return YES;
    }

  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
  if (!content)
    {
      fprintf(stderr, "Error reading skip list: %s\n",
              [[error localizedDescription] UTF8String]);
      return NO;
    }

  NSArray *lines = [content componentsSeparatedByString:@"\n"];
  for (NSString *line in lines)
    {
      NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([trimmed length] == 0 || [trimmed hasPrefix:@"#"])
        continue;
      /* Lines can be "package\tversion\tarch" or just "package" */
      NSArray *parts = [trimmed componentsSeparatedByString:@"\t"];
      [_skipPackages addObject:[parts objectAtIndex:0]];
    }

  if (_verbose)
    fprintf(stderr, "Loaded %lu packages from skip list\n",
            (unsigned long)[_skipPackages count]);
  return YES;
}

- (BOOL)setupStagingRoot
{
  /* Create temporary directories for debs and extraction */
  char tmpl[PATH_MAX];
  snprintf(tmpl, sizeof(tmpl), "/tmp/pkgwrap-%s-XXXXXX",
           [_packageName UTF8String]);
  char *result = mkdtemp(tmpl);
  if (!result)
    {
      fprintf(stderr, "Failed to create temporary directory\n");
      return NO;
    }
  _rootPath = [[NSString stringWithUTF8String:result] retain];

  _debCachePath = [[_rootPath stringByAppendingPathComponent:@"debs"] retain];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;
  if (![fm createDirectoryAtPath:_debCachePath
         withIntermediateDirectories:YES
                          attributes:nil
                               error:&error])
    {
      fprintf(stderr, "Failed to create deb cache: %s\n",
              [[error localizedDescription] UTF8String]);
      return NO;
    }

  /* Create the extraction root */
  NSString *extractRoot = [_rootPath stringByAppendingPathComponent:@"root"];
  if (![fm createDirectoryAtPath:extractRoot
         withIntermediateDirectories:YES
                          attributes:nil
                               error:&error])
    {
      fprintf(stderr, "Failed to create extraction root: %s\n",
              [[error localizedDescription] UTF8String]);
      return NO;
    }

  if (_verbose)
    fprintf(stderr, "Staging directory: %s\n", [_rootPath UTF8String]);
  return YES;
}

- (BOOL)resolveDependencies
{
  fprintf(stderr, "Resolving dependencies for %s...\n", [_packageName UTF8String]);

  /* Use apt-cache depends --recurse to get the full dependency tree.
   * Lines without leading whitespace are package names. */
  NSString *output = runCommand(@"/usr/bin/apt-cache",
    @[@"depends", @"--recurse",
      @"--no-recommends", @"--no-suggests",
      @"--no-conflicts", @"--no-breaks",
      @"--no-replaces", @"--no-enhances",
      _packageName]);

  if (!output || [output length] == 0)
    {
      fprintf(stderr, "apt-cache depends failed for '%s'\n",
              [_packageName UTF8String]);
      return NO;
    }

  /* Parse output: collect unique package names (lines without leading space).
   * Skip virtual packages (enclosed in angle brackets <...>).
   * Strip :arch suffixes. */
  NSMutableSet *seen = [NSMutableSet set];
  NSArray *lines = [output componentsSeparatedByString:@"\n"];
  for (NSString *line in lines)
    {
      /* Package names start at column 0 (no leading whitespace) */
      if ([line length] == 0)
        continue;
      unichar first = [line characterAtIndex:0];
      if (first == ' ' || first == '\t' || first == '|')
        continue;

      NSString *pkg = [line stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];

      /* Skip virtual packages like <package-name> */
      if ([pkg hasPrefix:@"<"] && [pkg hasSuffix:@">"])
        continue;

      /* Strip architecture qualifier (e.g., libc6:amd64 -> libc6) */
      NSRange colonRange = [pkg rangeOfString:@":"];
      if (colonRange.location != NSNotFound)
        pkg = [pkg substringToIndex:colonRange.location];

      if ([pkg length] == 0)
        continue;

      /* Skip packages in the skip list */
      if ([_skipPackages containsObject:pkg])
        {
          if (_verbose)
            fprintf(stderr, "  Skipping (on host): %s\n", [pkg UTF8String]);
          continue;
        }

      if (![seen containsObject:pkg])
        {
          [seen addObject:pkg];
          [_resolvedPackages addObject:pkg];
        }
    }

  /* Include Debian Essential packages — these are assumed present on every
   * Debian system and no package declares dependencies on them, but our
   * staging root is empty so they must be explicitly added. */
  NSString *essentialOutput = runCommand(@"/usr/bin/dpkg-query",
    @[@"-W", @"-f", @"${Package} ${Essential}\n"]);
  if (essentialOutput)
    {
      NSArray *essLines = [essentialOutput componentsSeparatedByString:@"\n"];
      for (NSString *line in essLines)
        {
          if (![line hasSuffix:@" yes"])
            continue;
          NSString *pkg = [line substringToIndex:[line length] - 4];
          if ([pkg length] == 0)
            continue;
          if ([_skipPackages containsObject:pkg])
            continue;
          if (![seen containsObject:pkg])
            {
              [seen addObject:pkg];
              [_resolvedPackages addObject:pkg];
            }
        }
    }

  fprintf(stderr, "Resolved %lu packages to bundle\n",
          (unsigned long)[_resolvedPackages count]);

  if (_verbose)
    {
      for (NSString *pkg in _resolvedPackages)
        fprintf(stderr, "  %s\n", [pkg UTF8String]);
    }

  return [_resolvedPackages count] > 0;
}

- (BOOL)downloadPackages
{
  if ([_resolvedPackages count] == 0)
    {
      fprintf(stderr, "No packages to download\n");
      return NO;
    }

  NSFileManager *fm = [NSFileManager defaultManager];

  /* Use the system apt cache (/var/cache/apt/archives/) so pkgwrap
   * shares cached .debs with apt-get install, apt-get upgrade, etc.
   * Any package already installed or previously downloaded on the
   * host is reused without a network round-trip. */
  NSString *aptCache = @"/var/cache/apt/archives";

  /* Copy matching .debs from the apt cache into our working directory.
   * Try hard link first (instant, no disk space), fall back to copy. */
  NSArray *aptFiles = [fm contentsOfDirectoryAtPath:aptCache error:NULL];
  for (NSString *pkg in _resolvedPackages)
    {
      NSString *prefix = [pkg stringByAppendingString:@"_"];
      for (NSString *f in aptFiles)
        {
          if ([f hasPrefix:prefix] && [f hasSuffix:@".deb"])
            {
              NSString *dst = [_debCachePath stringByAppendingPathComponent:f];
              if (![fm fileExistsAtPath:dst])
                {
                  NSString *src = [aptCache stringByAppendingPathComponent:f];
                  if (link([src fileSystemRepresentation],
                           [dst fileSystemRepresentation]) != 0)
                    [fm copyItemAtPath:src toPath:dst error:NULL];
                }
              break;
            }
        }
    }

  /* Figure out which packages we still need to download */
  NSMutableArray *needed = [NSMutableArray array];
  NSArray *existing = [fm contentsOfDirectoryAtPath:_debCachePath error:NULL];
  for (NSString *pkg in _resolvedPackages)
    {
      BOOL found = NO;
      NSString *prefix = [pkg stringByAppendingString:@"_"];
      for (NSString *f in existing)
        {
          if ([f hasPrefix:prefix] && [f hasSuffix:@".deb"])
            {
              found = YES;
              break;
            }
        }
      if (!found)
        [needed addObject:pkg];
    }

  if ([needed count] < [_resolvedPackages count])
    fprintf(stderr, "%d packages from apt cache, %lu to download\n",
            (int)([_resolvedPackages count] - [needed count]),
            (unsigned long)[needed count]);
  else
    fprintf(stderr, "Downloading %lu packages...\n",
            (unsigned long)[_resolvedPackages count]);

  if ([needed count] > 0)
    {
      /* apt-get download puts .deb files in the current directory.
       * Append :arch to each package name to ensure only the native
       * architecture is downloaded (avoids pulling i386 libs on amd64). */
      NSMutableArray *args = [NSMutableArray arrayWithObjects:
        @"download", nil];
      for (NSString *pkg in needed)
        [args addObject:[NSString stringWithFormat:@"%@:%@", pkg, _arch]];

      NSFileHandle *devNull = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath:@"/usr/bin/apt-get"];
      [task setArguments:args];
      [task setCurrentDirectoryPath:_debCachePath];
      if (!_verbose)
        [task setStandardOutput:devNull];
      [task launch];
      [task waitUntilExit];
      int status = [task terminationStatus];
      [task release];

      if (status != 0)
        {
          fprintf(stderr, "Batch download had errors; retrying individually...\n");
          int downloaded = 0;
          int skipped = 0;
          for (NSString *pkg in needed)
            {
              NSTask *t = [[NSTask alloc] init];
              [t setLaunchPath:@"/usr/bin/apt-get"];
              [t setArguments:@[@"download",
                [NSString stringWithFormat:@"%@:%@", pkg, _arch]]];
              [t setCurrentDirectoryPath:_debCachePath];
              [t setStandardOutput:devNull];
              [t setStandardError:devNull];
              [t launch];
              [t waitUntilExit];
              int s = [t terminationStatus];
              [t release];

              if (s == 0)
                downloaded++;
              else
                {
                  skipped++;
                  if (_verbose)
                    fprintf(stderr, "  Skipped: %s (not downloadable)\n",
                            [pkg UTF8String]);
                }
            }
          fprintf(stderr, "Downloaded %d packages, skipped %d\n",
                  downloaded, skipped);
        }

      /* Copy newly downloaded .debs back into the apt cache so future
       * apt operations and pkgwrap runs can reuse them. */
      NSArray *nowFiles = [fm contentsOfDirectoryAtPath:_debCachePath error:NULL];
      for (NSString *f in nowFiles)
        {
          if (![f hasSuffix:@".deb"])
            continue;
          NSString *dst = [aptCache stringByAppendingPathComponent:f];
          if (![fm fileExistsAtPath:dst])
            {
              NSString *src = [_debCachePath stringByAppendingPathComponent:f];
              [fm copyItemAtPath:src toPath:dst error:NULL];
            }
        }
    }

  /* Count total .deb files available */
  NSArray *files = [fm contentsOfDirectoryAtPath:_debCachePath error:NULL];
  int debCount = 0;
  for (NSString *f in files)
    if ([f hasSuffix:@".deb"])
      debCount++;
  fprintf(stderr, "Total %d .deb files ready\n", debCount);

  return debCount > 0;
}

- (BOOL)extractPackages
{
  NSString *extractRoot = [_rootPath stringByAppendingPathComponent:@"root"];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *files = [fm contentsOfDirectoryAtPath:_debCachePath error:NULL];

  int count = 0;
  int total = 0;
  for (NSString *f in files)
    if ([f hasSuffix:@".deb"])
      total++;

  fprintf(stderr, "Extracting %d packages...\n", total);

  for (NSString *file in files)
    {
      if (![file hasSuffix:@".deb"])
        continue;

      NSString *debPath = [_debCachePath stringByAppendingPathComponent:file];
      count++;

      if (_verbose)
        fprintf(stderr, "  [%d/%d] %s\n", count, total, [file UTF8String]);

      /* dpkg-deb -x extracts the data payload into a directory */
      int status = runCommandStatus(@"/usr/bin/dpkg-deb",
        (@[@"-x", debPath, extractRoot]), NO);

      if (status != 0)
        {
          fprintf(stderr, "  Warning: failed to extract %s\n",
                  [file UTF8String]);
        }
    }

  fprintf(stderr, "Extraction complete.\n");
  return YES;
}

- (NSString *)findDesktopFile
{
  NSString *extractRoot = [_rootPath stringByAppendingPathComponent:@"root"];
  NSString *appsDir = [extractRoot
    stringByAppendingPathComponent:@"usr/share/applications"];
  NSFileManager *fm = [NSFileManager defaultManager];

  if (![fm fileExistsAtPath:appsDir])
    return nil;

  /* Try exact match with package name */
  NSString *exact = [appsDir stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"%@.desktop", _packageName]];
  if ([fm fileExistsAtPath:exact])
    return exact;

  /* Strategy 1: Query the primary package's .deb to find which .desktop
   * files it actually ships.  This avoids picking up .desktop files from
   * dependency packages (e.g., python3.13.desktop when bundling obs-studio).
   * For --localpkg mode, the local deb path is used directly.
   * For apt mode, the .deb filename convention: <package>_<version>_<arch>.deb */
  if (_debCachePath || _localDebPath)
    {
      NSString *primaryDeb = _localDebPath;

      if (!primaryDeb)
        {
          NSArray *debs = [fm contentsOfDirectoryAtPath:_debCachePath error:NULL];
          NSString *prefix = [NSString stringWithFormat:@"%@_", _packageName];

          for (NSString *deb in debs)
            {
              if ([deb hasPrefix:prefix] && [deb hasSuffix:@".deb"])
                {
                  primaryDeb = [_debCachePath stringByAppendingPathComponent:deb];
                  break;
                }
            }
        }

      if (primaryDeb)
        {
          NSString *listing = runCommand(@"/usr/bin/dpkg-deb",
            @[@"-c", primaryDeb]);

          if (listing && [listing length] > 0)
            {
              NSArray *lines = [listing componentsSeparatedByString:@"\n"];
              NSMutableArray *desktopFiles = [NSMutableArray array];

              for (NSString *line in lines)
                {
                  /* dpkg-deb -c output has paths like:
                   * ./usr/share/applications/com.obsproject.Studio.desktop */
                  NSRange appsRange = [line rangeOfString:@"usr/share/applications/"];
                  if (appsRange.location == NSNotFound)
                    continue;

                  NSString *tail = [line substringFromIndex:
                    appsRange.location + [@ "usr/share/applications/" length]];
                  tail = [tail stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

                  if ([tail hasSuffix:@".desktop"] && [tail length] > 8)
                    [desktopFiles addObject:tail];
                }

              if ([desktopFiles count] == 1)
                {
                  NSString *found = [appsDir stringByAppendingPathComponent:
                    [desktopFiles objectAtIndex:0]];
                  if ([fm fileExistsAtPath:found])
                    return found;
                }
              else if ([desktopFiles count] > 1)
                {
                  /* Multiple .desktop files — prefer one matching package name */
                  for (NSString *df in desktopFiles)
                    {
                      if ([[df lowercaseString]
                            rangeOfString:[_packageName lowercaseString]].location
                              != NSNotFound)
                        {
                          NSString *found = [appsDir
                            stringByAppendingPathComponent:df];
                          if ([fm fileExistsAtPath:found])
                            return found;
                        }
                    }
                  /* Otherwise use the first from the primary package */
                  NSString *found = [appsDir stringByAppendingPathComponent:
                    [desktopFiles objectAtIndex:0]];
                  if ([fm fileExistsAtPath:found])
                    return found;
                }
            }
        }
    }

  /* Strategy 2: Fallback — search merged directory for substring match.
   * Do NOT fall back to an arbitrary .desktop file from a dependency. */
  NSArray *files = [fm contentsOfDirectoryAtPath:appsDir error:NULL];
  for (NSString *file in files)
    {
      if (![file hasSuffix:@".desktop"])
        continue;

      if ([[file lowercaseString]
            rangeOfString:[_packageName lowercaseString]].location != NSNotFound)
        return [appsDir stringByAppendingPathComponent:file];
    }

  return nil;
}

/* Set the root path directly for --localdir mode (no extraction needed). */
- (void)setLocalRootPath:(NSString *)path
{
  [_rootPath release];
  _rootPath = [path copy];
  _localDirMode = YES;
}

/* Resolve dependencies from a local .deb file's Depends field.
 * The local deb is copied into the working cache and its dependencies
 * are resolved from apt, just like the normal apt mode. */
- (BOOL)resolveDependenciesForLocalDeb:(NSString *)debPath
{
  NSFileManager *fm = [NSFileManager defaultManager];

  /* Remember the local deb path for findDesktopFile */
  _localDebPath = [debPath copy];

  /* Copy the local deb into our working cache */
  NSString *debName = [debPath lastPathComponent];
  NSString *dst = [_debCachePath stringByAppendingPathComponent:debName];
  [fm removeItemAtPath:dst error:NULL];
  if (![fm copyItemAtPath:debPath toPath:dst error:NULL])
    {
      fprintf(stderr, "Failed to copy local deb to staging area\n");
      return NO;
    }

  /* Read the Depends field from the deb */
  NSString *depends = runCommand(@"/usr/bin/dpkg-deb",
    @[@"-f", debPath, @"Depends"]);
  if (!depends)
    depends = @"";
  depends = [depends stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

  /* Also read Pre-Depends */
  NSString *preDepends = runCommand(@"/usr/bin/dpkg-deb",
    @[@"-f", debPath, @"Pre-Depends"]);
  if (preDepends)
    {
      preDepends = [preDepends stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([preDepends length] > 0)
        {
          if ([depends length] > 0)
            depends = [depends stringByAppendingFormat:@", %@", preDepends];
          else
            depends = preDepends;
        }
    }

  fprintf(stderr, "Local package dependencies: %s\n", [depends UTF8String]);

  /* Parse the comma-separated dependency list.
   * Each entry is like: "libfoo (>= 1.0)" or "libfoo | libbar".
   * We take the first alternative and strip version constraints. */
  NSMutableSet *depNames = [NSMutableSet set];
  NSArray *entries = [depends componentsSeparatedByString:@","];
  for (NSString *entry in entries)
    {
      NSString *trimmed = [entry stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([trimmed length] == 0)
        continue;

      /* Take first alternative if "a | b" */
      NSRange pipeRange = [trimmed rangeOfString:@"|"];
      if (pipeRange.location != NSNotFound)
        trimmed = [[trimmed substringToIndex:pipeRange.location]
          stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

      /* Strip version constraint "(>= 1.0)" */
      NSRange parenRange = [trimmed rangeOfString:@"("];
      if (parenRange.location != NSNotFound)
        trimmed = [[trimmed substringToIndex:parenRange.location]
          stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

      /* Strip :arch qualifier */
      NSRange colonRange = [trimmed rangeOfString:@":"];
      if (colonRange.location != NSNotFound)
        trimmed = [trimmed substringToIndex:colonRange.location];

      if ([trimmed length] > 0)
        [depNames addObject:trimmed];
    }

  /* Now resolve the full dependency tree for each direct dependency
   * using apt-cache depends --recurse */
  NSMutableSet *allPackages = [NSMutableSet set];
  for (NSString *dep in depNames)
    {
      if ([_skipPackages containsObject:dep])
        continue;

      NSString *output = runCommand(@"/usr/bin/apt-cache",
        @[@"depends", @"--recurse",
          @"--no-recommends", @"--no-suggests",
          @"--no-conflicts", @"--no-breaks",
          @"--no-replaces", @"--no-enhances",
          dep]);

      if (!output)
        continue;

      NSArray *lines = [output componentsSeparatedByString:@"\n"];
      for (NSString *line in lines)
        {
          if ([line length] == 0)
            continue;
          unichar first = [line characterAtIndex:0];
          if (first == ' ' || first == '\t' || first == '|')
            continue;

          NSString *pkg = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

          if ([pkg hasPrefix:@"<"] && [pkg hasSuffix:@">"])
            continue;

          NSRange cr = [pkg rangeOfString:@":"];
          if (cr.location != NSNotFound)
            pkg = [pkg substringToIndex:cr.location];

          if ([pkg length] > 0 && ![_skipPackages containsObject:pkg])
            [allPackages addObject:pkg];
        }
    }

  /* Add essential packages */
  NSString *essentialOutput = runCommand(@"/usr/bin/dpkg-query",
    @[@"-W", @"-f", @"${Package} ${Essential}\n"]);
  if (essentialOutput)
    {
      NSArray *essLines = [essentialOutput componentsSeparatedByString:@"\n"];
      for (NSString *line in essLines)
        {
          if (![line hasSuffix:@" yes"])
            continue;
          NSString *pkg = [line substringToIndex:[line length] - 4];
          if ([pkg length] > 0 && ![_skipPackages containsObject:pkg])
            [allPackages addObject:pkg];
        }
    }

  /* Build the resolved list (exclude the local package itself) */
  for (NSString *pkg in allPackages)
    {
      if (![pkg isEqualToString:_packageName])
        [_resolvedPackages addObject:pkg];
    }

  fprintf(stderr, "Resolved %lu dependency packages (plus local deb)\n",
          (unsigned long)[_resolvedPackages count]);

  if (_verbose)
    {
      for (NSString *pkg in _resolvedPackages)
        fprintf(stderr, "  %s\n", [pkg UTF8String]);
    }

  return YES;
}

- (NSString *)rootPath
{
  if (_localDirMode)
    return _rootPath;
  /* Return the extraction root, not the temp dir */
  return [_rootPath stringByAppendingPathComponent:@"root"];
}

- (NSArray *)resolvedPackageNames
{
  return [[_resolvedPackages copy] autorelease];
}

- (void)cleanup
{
  if (!_rootPath)
    return;

  if (_verbose)
    fprintf(stderr, "Cleaning up: %s\n", [_rootPath UTF8String]);

  [[NSFileManager defaultManager] removeItemAtPath:_rootPath error:NULL];
  [_rootPath release];
  _rootPath = nil;
}

- (void)dealloc
{
  [_packageName release];
  [_skipPackages release];
  [_resolvedPackages release];
  [_arch release];
  if (_debCachePath) [_debCachePath release];
  if (_localDebPath) [_localDebPath release];
  if (_rootPath) [_rootPath release];
  [super dealloc];
}

@end
