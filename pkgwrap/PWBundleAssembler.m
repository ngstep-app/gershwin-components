/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PWBundleAssembler.h"
#import "GWUtils.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

@implementation PWBundleAssembler

- (instancetype)initWithAppName:(NSString *)appName
                       rootPath:(NSString *)rootPath
                     bundlePath:(NSString *)bundlePath
                        verbose:(BOOL)verbose
                          strip:(BOOL)strip
{
  self = [super init];
  if (self)
    {
      _appName = [appName copy];
      _rootPath = [rootPath copy];
      _bundlePath = [bundlePath copy];
      _verbose = verbose;
      _strip = strip;
    }
  return self;
}

- (BOOL)assembleBundle
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;

  /* Create the bundle directory structure */
  NSString *contentsPath = [_bundlePath stringByAppendingPathComponent:@"Contents"];
  NSString *resourcesPath = [_bundlePath stringByAppendingPathComponent:@"Resources"];

  for (NSString *dir in @[contentsPath, resourcesPath])
    {
      if (![fm createDirectoryAtPath:dir
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:&error])
        {
          fprintf(stderr, "Failed to create %s: %s\n",
                  [dir UTF8String], [[error localizedDescription] UTF8String]);
          return NO;
        }
    }

  /* Copy relevant directories from the staging root into Contents/
   * preserving the Debian filesystem layout. */
  NSArray *copyDirs = @[@"usr", @"etc", @"lib", @"opt"];
  /* Directories to skip entirely */
  NSSet *skipDirs = [NSSet setWithArray:@[
    @"usr/share/doc", @"usr/share/man", @"usr/share/info",
    @"usr/share/lintian", @"usr/share/bug", @"usr/share/menu",
    @"usr/share/locale"
  ]];

  for (NSString *dir in copyDirs)
    {
      NSString *srcDir = [_rootPath stringByAppendingPathComponent:dir];
      if (![fm fileExistsAtPath:srcDir])
        continue;

      NSString *dstDir = [contentsPath stringByAppendingPathComponent:dir];

      if (_verbose)
        fprintf(stderr, "Copying %s/ into bundle...\n", [dir UTF8String]);

      if (![self copyDirectory:srcDir
                   toDirectory:dstDir
                      skipDirs:skipDirs
                    relativeTo:_rootPath])
        {
          fprintf(stderr, "Warning: some files in %s/ could not be copied\n",
                  [dir UTF8String]);
        }
    }

  fprintf(stderr, "Copying complete, rewriting RPATH...\n");

  /* Run patchelf on all ELF binaries */
  @try
    {
      if (![self rewriteRPATH])
        {
          fprintf(stderr, "Warning: RPATH rewriting had errors (launcher LD_LIBRARY_PATH will compensate)\n");
        }
    }
  @catch (NSException *ex)
    {
      fprintf(stderr, "Warning: RPATH rewriting crashed: %s (%s)\n",
              [[ex reason] UTF8String], [[ex name] UTF8String]);
    }

  /* Optionally strip debug symbols */
  if (_strip)
    {
      [self stripBinaries];
    }

  fprintf(stderr, "Bundle assembly complete.\n");
  return YES;
}

/* Recursively copy a directory tree, skipping paths in skipDirs */
- (BOOL)copyDirectory:(NSString *)src
          toDirectory:(NSString *)dst
             skipDirs:(NSSet *)skipDirs
           relativeTo:(NSString *)rootBase
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;

  /* Check if this path should be skipped */
  if (rootBase)
    {
      NSString *relPath = @"";
      if ([src length] > [rootBase length] + 1)
        relPath = [src substringFromIndex:[rootBase length] + 1];
      if ([skipDirs containsObject:relPath])
        {
          if (_verbose)
            fprintf(stderr, "  Skipping %s\n", [relPath UTF8String]);
          return YES;
        }
    }

  /* Check for symlinks first — attributesOfItemAtPath does not follow
   * symlinks, so it detects broken symlinks that fileExistsAtPath misses. */
  NSDictionary *attrs = [fm attributesOfItemAtPath:src error:NULL];
  if (!attrs)
    {
      fprintf(stderr, "  Cannot stat: %s\n", [src UTF8String]);
      return NO;
    }

  if ([[attrs fileType] isEqualToString:NSFileTypeSymbolicLink])
    {
      NSString *dstParent = [dst stringByDeletingLastPathComponent];
      [fm createDirectoryAtPath:dstParent
        withIntermediateDirectories:YES
                         attributes:nil
                              error:NULL];

      NSString *target = [fm pathContentOfSymbolicLinkAtPath:src];
      if (target)
        {
          [fm removeItemAtPath:dst error:NULL];
          if (![fm createSymbolicLinkAtPath:dst
                         withDestinationPath:target
                                       error:&error])
            {
              fprintf(stderr, "  Symlink failed: %s -> %s: %s\n",
                      [dst UTF8String], [target UTF8String],
                      [[error localizedDescription] UTF8String]);
              return NO;
            }
          return YES;
        }
      fprintf(stderr, "  Symlink unreadable: %s\n", [src UTF8String]);
      return NO;
    }

  BOOL isDir = NO;
  if (![fm fileExistsAtPath:src isDirectory:&isDir])
    return NO;

  if (!isDir)
    {
      /* Copy single file */
      NSString *dstParent = [dst stringByDeletingLastPathComponent];
      [fm createDirectoryAtPath:dstParent
        withIntermediateDirectories:YES
                         attributes:nil
                              error:NULL];

      if ([fm fileExistsAtPath:dst])
        [fm removeItemAtPath:dst error:NULL];

      if (![fm copyItemAtPath:src toPath:dst error:&error])
        {
          fprintf(stderr, "  Copy failed: %s -> %s: %s\n",
                  [src UTF8String], [dst UTF8String],
                  [[error localizedDescription] UTF8String]);
          return NO;
        }
      return YES;
    }

  /* Create destination directory */
  if (![fm createDirectoryAtPath:dst
         withIntermediateDirectories:YES
                          attributes:nil
                               error:&error])
    return NO;

  /* Enumerate contents */
  NSArray *contents = [fm contentsOfDirectoryAtPath:src error:&error];
  if (!contents)
    return NO;

  BOOL allOK = YES;
  for (NSString *item in contents)
    {
      NSString *srcItem = [src stringByAppendingPathComponent:item];
      NSString *dstItem = [dst stringByAppendingPathComponent:item];
      if (![self copyDirectory:srcItem
                   toDirectory:dstItem
                      skipDirs:skipDirs
                    relativeTo:rootBase])
        allOK = NO;
    }
  return allOK;
}

- (BOOL)rewriteRPATH
{
  /* Check if patchelf is available */
  NSString *patchelf = [GWUtils findExecutableInPath:@"patchelf"];
  if (!patchelf)
    {
      fprintf(stderr, "patchelf not found; skipping RPATH rewriting.\n"
                      "Install patchelf for more robust library resolution.\n");
      return YES;
    }

  if (_verbose)
    fprintf(stderr, "Rewriting RPATH with patchelf...\n");

  NSString *contentsPath = [_bundlePath stringByAppendingPathComponent:@"Contents"];
  NSArray *elfFiles = [self findElfFilesIn:contentsPath];

  /* Open /dev/null once and detect multiarch once, outside the loop */
  int devNullFd = open("/dev/null", O_WRONLY);
  if (devNullFd < 0)
    {
      fprintf(stderr, "Warning: cannot open /dev/null\n");
      return NO;
    }
  NSFileHandle *devNull = [[NSFileHandle alloc] initWithFileDescriptor:devNullFd
                                                        closeOnDealloc:YES];
  NSString *multiarch = [self detectMultiarchTriple];

  for (NSString *elfPath in elfFiles)
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];

      /* Compute relative path from the ELF file to Contents/usr/lib
       * and Contents/lib directories */
      NSString *elfDir = [elfPath stringByDeletingLastPathComponent];
      NSString *relToContents = [self relativePath:contentsPath fromPath:elfDir];

      /* Build rpath entries for all possible lib locations */
      NSMutableArray *rpaths = [NSMutableArray array];
      [rpaths addObject:[NSString stringWithFormat:@"$ORIGIN/%@/usr/lib", relToContents]];

      if (multiarch)
        [rpaths addObject:[NSString stringWithFormat:@"$ORIGIN/%@/usr/lib/%@",
                           relToContents, multiarch]];

      [rpaths addObject:[NSString stringWithFormat:@"$ORIGIN/%@/lib", relToContents]];
      if (multiarch)
        [rpaths addObject:[NSString stringWithFormat:@"$ORIGIN/%@/lib/%@",
                           relToContents, multiarch]];

      NSString *rpath = [rpaths componentsJoinedByString:@":"];

      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath:patchelf];
      [task setArguments:@[@"--set-rpath", rpath, elfPath]];
      [task setStandardOutput:devNull];
      if (_verbose)
        {
          NSPipe *errPipe = [NSPipe pipe];
          [task setStandardError:errPipe];
          [task launch];
          NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
          [task waitUntilExit];
          if ([task terminationStatus] != 0)
            {
              NSString *errStr = [[NSString alloc] initWithData:errData
                                                       encoding:NSUTF8StringEncoding];
              fprintf(stderr, "  patchelf warning for %s: %s\n",
                      [[elfPath lastPathComponent] UTF8String], [errStr UTF8String]);
              [errStr release];
            }
        }
      else
        {
          [task setStandardError:devNull];
          [task launch];
          [task waitUntilExit];
        }
      [task release];
      [inner release];
    }

  [devNull release];
  return YES;
}

/* Find all ELF binaries in a directory tree */
- (NSArray *)findElfFilesIn:(NSString *)directory
{
  NSMutableArray *result = [NSMutableArray array];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:directory];
  NSString *file;

  while ((file = [enumerator nextObject]))
    {
      NSString *fullPath = [directory stringByAppendingPathComponent:file];

      /* Skip symlinks */
      NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:NULL];
      if ([[attrs fileType] isEqualToString:NSFileTypeSymbolicLink])
        continue;

      /* Check if regular file */
      if (![[attrs fileType] isEqualToString:NSFileTypeRegular])
        continue;

      /* Check ELF magic bytes using raw fd to avoid leaking file handles */
      int fd = open([fullPath fileSystemRepresentation], O_RDONLY);
      if (fd < 0)
        continue;
      unsigned char magic[4];
      ssize_t n = read(fd, magic, 4);
      close(fd);

      if (n == 4 && magic[0] == 0x7f && magic[1] == 'E' &&
          magic[2] == 'L' && magic[3] == 'F')
        {
          [result addObject:fullPath];
        }
    }

  if (_verbose)
    fprintf(stderr, "Found %lu ELF files in bundle\n", (unsigned long)[result count]);
  return result;
}

/* Compute relative path from fromPath to toPath */
- (NSString *)relativePath:(NSString *)toPath fromPath:(NSString *)fromPath
{
  NSArray *toComponents = [toPath pathComponents];
  NSArray *fromComponents = [fromPath pathComponents];

  /* Find common prefix length */
  NSUInteger commonLen = 0;
  NSUInteger minLen = MIN([toComponents count], [fromComponents count]);
  for (NSUInteger i = 0; i < minLen; i++)
    {
      if ([[toComponents objectAtIndex:i] isEqualToString:[fromComponents objectAtIndex:i]])
        commonLen = i + 1;
      else
        break;
    }

  /* Build relative path: go up from fromPath, then down to toPath */
  NSMutableString *rel = [NSMutableString string];
  for (NSUInteger i = commonLen; i < [fromComponents count]; i++)
    {
      if ([rel length] > 0)
        [rel appendString:@"/"];
      [rel appendString:@".."];
    }
  for (NSUInteger i = commonLen; i < [toComponents count]; i++)
    {
      if ([rel length] > 0)
        [rel appendString:@"/"];
      [rel appendString:[toComponents objectAtIndex:i]];
    }

  return [rel length] > 0 ? rel : @".";
}

/* Detect the Debian multi-arch triplet (e.g., x86_64-linux-gnu) */
- (NSString *)detectMultiarchTriple
{
  NSString *libDir = [_rootPath stringByAppendingPathComponent:@"usr/lib"];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *contents = [fm contentsOfDirectoryAtPath:libDir error:NULL];
  for (NSString *item in contents)
    {
      /* Multi-arch triplets contain hyphens and typically end with -linux-gnu */
      if ([item rangeOfString:@"-linux-gnu"].location != NSNotFound)
        return item;
      if ([item rangeOfString:@"-linux-musl"].location != NSNotFound)
        return item;
    }
  return nil;
}

- (void)stripBinaries
{
  NSString *strip = [GWUtils findExecutableInPath:@"strip"];
  if (!strip)
    {
      fprintf(stderr, "strip not found; skipping debug symbol removal\n");
      return;
    }

  if (_verbose)
    fprintf(stderr, "Stripping debug symbols...\n");

  NSString *contentsPath = [_bundlePath stringByAppendingPathComponent:@"Contents"];
  NSArray *elfFiles = [self findElfFilesIn:contentsPath];

  for (NSString *elfPath in elfFiles)
    {
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath:strip];
      [task setArguments:@[@"--strip-unneeded", elfPath]];
      NSFileHandle *dn = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
      [task setStandardOutput:dn];
      [task setStandardError:dn];
      [task launch];
      [task waitUntilExit];
      [task release];
    }
}

- (NSString *)findIconInRoot:(NSString *)iconName
{
  if (!iconName || [iconName length] == 0)
    return nil;

  NSFileManager *fm = [NSFileManager defaultManager];

  /* If it's an absolute path within the root, check there */
  if ([iconName hasPrefix:@"/"])
    {
      NSString *inRoot = [_rootPath stringByAppendingPathComponent:iconName];
      if ([fm fileExistsAtPath:inRoot])
        return inRoot;
    }

  /* Search hicolor theme in the staging root, prefer larger sizes */
  NSArray *sizes = @[@"256x256", @"128x128", @"96x96", @"64x64",
                     @"48x48", @"scalable"];
  NSArray *extensions = @[@".png", @".svg", @".xpm", @""];

  for (NSString *size in sizes)
    {
      for (NSString *ext in extensions)
        {
          NSString *path = [NSString stringWithFormat:
            @"%@/usr/share/icons/hicolor/%@/apps/%@%@",
            _rootPath, size, iconName, ext];
          if ([fm fileExistsAtPath:path])
            return path;
        }
    }

  /* Check pixmaps */
  for (NSString *ext in extensions)
    {
      NSString *path = [NSString stringWithFormat:
        @"%@/usr/share/pixmaps/%@%@", _rootPath, iconName, ext];
      if ([fm fileExistsAtPath:path])
        return path;
    }

  /* Broad search through icons directory */
  NSString *iconsDir = [_rootPath stringByAppendingPathComponent:@"usr/share/icons"];
  if ([fm fileExistsAtPath:iconsDir])
    {
      NSDirectoryEnumerator *e = [fm enumeratorAtPath:iconsDir];
      NSString *file;
      NSString *best = nil;
      int bestScore = -1;

      while ((file = [e nextObject]))
        {
          NSString *basename = [[file lastPathComponent] stringByDeletingPathExtension];
          if (![[basename lowercaseString] isEqualToString:[iconName lowercaseString]])
            continue;

          NSString *full = [iconsDir stringByAppendingPathComponent:file];
          int score = 0;

          NSString *ext = [[file pathExtension] lowercaseString];
          if ([ext isEqualToString:@"png"]) score += 100;
          else if ([ext isEqualToString:@"svg"]) score += 200;

          if ([file rangeOfString:@"256x256"].location != NSNotFound) score += 256;
          else if ([file rangeOfString:@"128x128"].location != NSNotFound) score += 128;
          else if ([file rangeOfString:@"scalable"].location != NSNotFound) score += 300;

          if (score > bestScore)
            {
              bestScore = score;
              best = full;
            }
        }

      if (best)
        return best;
    }

  return nil;
}

- (void)dealloc
{
  [_appName release];
  [_rootPath release];
  [_bundlePath release];
  [super dealloc];
}

@end
