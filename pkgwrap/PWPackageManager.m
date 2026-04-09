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

  fprintf(stderr, "Downloading %lu packages...\n",
          (unsigned long)[_resolvedPackages count]);

  /* apt-get download puts .deb files in the current directory.
   * We cd to our deb cache and download in batches. */
  NSMutableArray *args = [NSMutableArray arrayWithObjects:
    @"download", nil];
  [args addObjectsFromArray:_resolvedPackages];

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
      /* Some packages may fail (virtual packages, etc.).
       * Try downloading one by one and skip failures. */
      fprintf(stderr, "Batch download had errors; retrying individually...\n");
      int downloaded = 0;
      int skipped = 0;
      for (NSString *pkg in _resolvedPackages)
        {
          NSTask *t = [[NSTask alloc] init];
          [t setLaunchPath:@"/usr/bin/apt-get"];
          [t setArguments:@[@"download", pkg]];
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
      if (downloaded == 0)
        return NO;
    }

  /* Count downloaded .deb files */
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *files = [fm contentsOfDirectoryAtPath:_debCachePath error:NULL];
  int debCount = 0;
  for (NSString *f in files)
    if ([f hasSuffix:@".deb"])
      debCount++;
  fprintf(stderr, "Downloaded %d .deb files\n", debCount);

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

  /* Search for any .desktop file containing the package name */
  NSArray *files = [fm contentsOfDirectoryAtPath:appsDir error:NULL];
  NSString *best = nil;
  for (NSString *file in files)
    {
      if (![file hasSuffix:@".desktop"])
        continue;

      if ([[file lowercaseString]
            rangeOfString:[_packageName lowercaseString]].location != NSNotFound)
        return [appsDir stringByAppendingPathComponent:file];

      if (!best)
        best = [appsDir stringByAppendingPathComponent:file];
    }

  return best;
}

- (NSString *)rootPath
{
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
  if (_rootPath) [_rootPath release];
  [super dealloc];
}

@end
