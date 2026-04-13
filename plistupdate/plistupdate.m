/** plistupdate - Updates Info-gnustep.plist with build metadata
   Copyright (C) 2026 Free Software Foundation, Inc.

   Written by:  Gershwin Project Contributors
   Created: January 2026

   This file is part of the Gershwin Desktop Environment

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   You should have received a copy of the GNU General Public
   License along with this program; see the file COPYING.
   If not, write to the Free Software Foundation,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/

#import <Foundation/Foundation.h>

#define VERSION "1.0.0"

static void
print_usage(NSString *progName)
{
  fprintf(stderr, "Usage: %s [OPTIONS] PLIST_FILE\n\n", [progName UTF8String]);
  fprintf(stderr, "Updates Info-gnustep.plist files with build metadata.\n\n");
  fprintf(stderr, "Options:\n");
  fprintf(stderr, "  -h, --help           Show this help message\n");
  fprintf(stderr, "  -v, --version        Show version information\n");
  fprintf(stderr, "  -b, --build VERSION  Set NSBuildVersion manually (otherwise uses git)\n");
  fprintf(stderr, "  -d, --date DATE      Set ApplicationRelease manually (otherwise uses current date)\n");
  fprintf(stderr, "  -n, --no-git         Don't attempt to get version from git\n");
  fprintf(stderr, "  -q, --quiet          Suppress informational messages\n\n");
  fprintf(stderr, "If the plist file is in a git repository and -b is not specified,\n");
  fprintf(stderr, "NSBuildVersion will be set to the short git commit hash.\n");
  fprintf(stderr, "Otherwise, it will be set to \"dev\".\n\n");
  fprintf(stderr, "ApplicationRelease will be set to the current date in YYYYMMDD format,\n");
  fprintf(stderr, "unless -d is specified.\n\n");
  fprintf(stderr, "Examples:\n");
  fprintf(stderr, "  %s MyApp.app/Resources/Info-gnustep.plist\n", [progName UTF8String]);
  fprintf(stderr, "  %s -b 1.0 -d 20260107 Info-gnustep.plist\n", [progName UTF8String]);
}

static void
print_version(void)
{
  printf("plistupdate version %s\n", VERSION);
  printf("Copyright (C) 2026 Free Software Foundation, Inc.\n");
  printf("This is free software; see the source for copying conditions.\n");
}

static NSString*
get_git_revision(NSString *filePath, BOOL quiet)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  
  // Convert to absolute path first
  NSString *absolutePath = filePath;
  if (![filePath isAbsolutePath])
    {
      NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
      absolutePath = [cwd stringByAppendingPathComponent: filePath];
    }
  
  NSString *dirPath = [absolutePath stringByDeletingLastPathComponent];
  
  // Check if we're in a git repository by looking for .git directory
  NSString *checkPath = dirPath;
  BOOL foundGit = NO;
  
  while ([checkPath length] > 1)
    {
      NSString *gitPath = [checkPath stringByAppendingPathComponent: @".git"];
      if ([fm fileExistsAtPath: gitPath])
        {
          foundGit = YES;
          break;
        }
      checkPath = [checkPath stringByDeletingLastPathComponent];
    }
  
  if (!foundGit)
    {
      if (!quiet)
        fprintf(stderr, "plistupdate: Not in a git repository, using 'dev'\n");
      return @"dev";
    }
  
  // Run git rev-parse --short HEAD
  NSTask *task = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  
  [task setLaunchPath: @"/usr/bin/git"];
  [task setArguments: [NSArray arrayWithObjects: @"rev-parse", @"--short", @"HEAD", nil]];
  [task setCurrentDirectoryPath: dirPath];
  [task setStandardOutput: pipe];
  [task setStandardError: [NSFileHandle fileHandleWithNullDevice]];
  
  NS_DURING
    {
      [task launch];
      [task waitUntilExit];
    }
  NS_HANDLER
    {
      if (!quiet)
        fprintf(stderr, "plistupdate: Failed to execute git: %s\n",
          [[localException reason] UTF8String]);
      [task release];
      return @"dev";
    }
  NS_ENDHANDLER
  
  if ([task terminationStatus] != 0)
    {
      if (!quiet)
        fprintf(stderr, "plistupdate: git command failed, using 'dev'\n");
      [task release];
      return @"dev";
    }
  
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData: data 
                                            encoding: NSUTF8StringEncoding];
  NSString *revision = [[output stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
  
  [task release];
  [output release];
  
  if ([revision length] == 0)
    {
      if (!quiet)
        fprintf(stderr, "plistupdate: Empty git output, using 'dev'\n");
      return @"dev";
    }
  
  return [revision autorelease];
}

static NSString*
get_current_date(void)
{
  NSCalendarDate *date = [NSCalendarDate calendarDate];
  return [date descriptionWithCalendarFormat: @"%Y%m%d"];
}

int
main(int argc, char** argv, char **env)
{
  NSAutoreleasePool *pool;
  NSProcessInfo *procinfo;
  NSArray *args;
  NSString *plistPath = nil;
  NSString *buildVersion = nil;
  NSString *releaseDate = nil;
  BOOL noGit = NO;
  BOOL quiet = NO;
  unsigned i;

#ifdef GS_PASS_ARGUMENTS
  GSInitializeProcess(argc, argv, env);
#endif
  pool = [NSAutoreleasePool new];
  procinfo = [NSProcessInfo processInfo];
  
  if (procinfo == nil)
    {
      NSDebugLLog(@"gwcomp", @"plistupdate: unable to get process information!");
      [pool release];
      exit(EXIT_FAILURE);
    }

  args = [procinfo arguments];

  // Parse arguments
  for (i = 1; i < [args count]; i++)
    {
      NSString *arg = [args objectAtIndex: i];
      
      if ([arg isEqualToString: @"-h"] || [arg isEqualToString: @"--help"])
        {
          print_usage([procinfo processName]);
          [pool release];
          exit(EXIT_SUCCESS);
        }
      else if ([arg isEqualToString: @"-v"] || [arg isEqualToString: @"--version"])
        {
          print_version();
          [pool release];
          exit(EXIT_SUCCESS);
        }
      else if ([arg isEqualToString: @"-b"] || [arg isEqualToString: @"--build"])
        {
          if (i + 1 >= [args count])
            {
              fprintf(stderr, "Error: %s requires an argument\n", [arg UTF8String]);
              [pool release];
              exit(EXIT_FAILURE);
            }
          buildVersion = [args objectAtIndex: ++i];
        }
      else if ([arg isEqualToString: @"-d"] || [arg isEqualToString: @"--date"])
        {
          if (i + 1 >= [args count])
            {
              fprintf(stderr, "Error: %s requires an argument\n", [arg UTF8String]);
              [pool release];
              exit(EXIT_FAILURE);
            }
          releaseDate = [args objectAtIndex: ++i];
        }
      else if ([arg isEqualToString: @"-n"] || [arg isEqualToString: @"--no-git"])
        {
          noGit = YES;
        }
      else if ([arg isEqualToString: @"-q"] || [arg isEqualToString: @"--quiet"])
        {
          quiet = YES;
        }
      else if ([arg hasPrefix: @"-"])
        {
          fprintf(stderr, "Error: Unknown option: %s\n", [arg UTF8String]);
          print_usage([procinfo processName]);
          [pool release];
          exit(EXIT_FAILURE);
        }
      else
        {
          if (plistPath != nil)
            {
              fprintf(stderr, "Error: Multiple plist files specified\n");
              print_usage([procinfo processName]);
              [pool release];
              exit(EXIT_FAILURE);
            }
          plistPath = arg;
        }
    }

  if (plistPath == nil)
    {
      fprintf(stderr, "Error: No plist file specified\n");
      print_usage([procinfo processName]);
      [pool release];
      exit(EXIT_FAILURE);
    }

  // Check if file exists
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath: plistPath])
    {
      fprintf(stderr, "Error: File does not exist: %s\n", [plistPath UTF8String]);
      [pool release];
      exit(EXIT_FAILURE);
    }

  // Determine build version
  if (buildVersion == nil)
    {
      if (noGit)
        buildVersion = @"dev";
      else
        buildVersion = get_git_revision(plistPath, quiet);
    }

  // Determine release date
  if (releaseDate == nil)
    {
      releaseDate = get_current_date();
    }

  // Read the plist file
  NSString *fileContents = nil;
  NSMutableDictionary *plist = nil;
  
  NS_DURING
    {
      fileContents = [NSString stringWithContentsOfFile: plistPath];
      plist = [[fileContents propertyList] mutableCopy];
    }
  NS_HANDLER
    {
      fprintf(stderr, "Error parsing '%s': %s\n", [plistPath UTF8String],
        [[localException reason] UTF8String]);
      [pool release];
      exit(EXIT_FAILURE);
    }
  NS_ENDHANDLER

  if ((plist == nil) || ![plist isKindOfClass: [NSDictionary class]])
    {
      fprintf(stderr, "Error: The plist file must contain a dictionary.\n");
      [pool release];
      exit(EXIT_FAILURE);
    }

  // Update the plist
  [plist setObject: buildVersion forKey: @"NSBuildVersion"];
  [plist setObject: releaseDate forKey: @"ApplicationRelease"];

  if (!quiet)
    {
      printf("Updating %s:\n", [plistPath UTF8String]);
      printf("  NSBuildVersion = %s\n", [buildVersion UTF8String]);
      printf("  ApplicationRelease = %s\n", [releaseDate UTF8String]);
    }

  // Write the updated plist back
  NSString *plistString = [plist description];
  NSData *plistData = [plistString dataUsingEncoding: NSUTF8StringEncoding];
  
  if (![plistData writeToFile: plistPath atomically: YES])
    {
      fprintf(stderr, "Error: Failed to write to file: %s\n", [plistPath UTF8String]);
      [pool release];
      exit(EXIT_FAILURE);
    }

  [plist release];
  [pool release];
  return EXIT_SUCCESS;
}
