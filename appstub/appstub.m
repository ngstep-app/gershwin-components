/*
 * appstub - Execute a wrapped executable from Info.plist
 * 
 * This tool reads the GSWrappedExecutable key from its Info.plist
 * and execs the command from PATH, passing through all arguments.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void showError(NSString *message)
{
  NSAutoreleasePool *errorPool = [[NSAutoreleasePool alloc] init];
  
  // Always log to stderr
  fprintf(stderr, "Application Stub Error: %s\n", [message UTF8String]);
  
  // Try to show GUI alert if display is available
  @try
    {
      // Initialize application and backend
      NSApplication *app = [NSApplication sharedApplication];
      [app finishLaunching];
      
      NSAlert *alert = [[NSAlert alloc] init];
      [alert setMessageText:@"Application Stub Error"];
      [alert setInformativeText:message];
      [alert setAlertStyle:NSCriticalAlertStyle];
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
      [alert release];
    }
  @catch (NSException *exception)
    {
      // GUI not available, stderr output is sufficient
      // Silently continue since we already logged to stderr
    }
  
  [errorPool release];
  exit(1);
}

int main(int argc, char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = 1;

  @try
    {
      // Get the path to the executable
      NSString *execPath = [NSString stringWithUTF8String:argv[0]];
      NSString *resourcesPath = nil;

      // Check if we're running from within an app bundle
      if ([execPath containsString:@".app/"])
        {
          // Extract the bundle path
          NSRange appRange = [execPath rangeOfString:@".app/" options:NSBackwardsSearch];
          if (appRange.location != NSNotFound)
            {
              NSString *bundlePath = [execPath substringToIndex:appRange.location + 4];
              resourcesPath = [bundlePath stringByAppendingPathComponent:@"Resources"];
            }
        }
      else
        {
          // Running directly - look for Info.plist in same directory
          resourcesPath = [execPath stringByDeletingLastPathComponent];
        }

      if (!resourcesPath)
        {
          showError(@"Could not determine Resources path. The application bundle structure may be invalid.");
          ret = 1;
          goto cleanup;
        }

      NSString *plistPath = [resourcesPath stringByAppendingPathComponent:@"Info.plist"];
      
      // Check if Info.plist exists
      NSFileManager *fm = [NSFileManager defaultManager];
      if (![fm fileExistsAtPath:plistPath])
        {
          showError([NSString stringWithFormat:@"Info.plist not found at path:\n%@", plistPath]);
          ret = 1;
          goto cleanup;
        }

      // Read the Info.plist
      NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
      if (!plist)
        {
          showError([NSString stringWithFormat:@"Failed to read Info.plist at path:\n%@\n\nThe file may be corrupted or have invalid syntax.", plistPath]);
          ret = 1;
          goto cleanup;
        }

      // Get the GSWrappedExecutable value
      NSString *wrappedExec = [plist objectForKey:@"GSWrappedExecutable"];
      if (!wrappedExec || [wrappedExec length] == 0)
        {
          showError(@"GSWrappedExecutable key not found or empty in Info.plist.\n\nThis key is required to specify which executable to launch.");
          ret = 1;
          goto cleanup;
        }

      // Convert to C string
      const char *command = [wrappedExec UTF8String];
      
      NSLog(@"Executing: %s", command);

      // Build argv array for exec
      char **newArgv = (char **)malloc((argc + 1) * sizeof(char *));
      if (!newArgv)
        {
          showError(@"Memory allocation failed. The system may be out of memory.");
          ret = 1;
          goto cleanup;
        }

      newArgv[0] = (char *)command;
      for (int i = 1; i < argc; i++)
        {
          newArgv[i] = argv[i];
        }
      newArgv[argc] = NULL;

      // exec the command - this replaces the current process
      // If exec succeeds, we never return from here
      execvp(command, newArgv);

      // If we get here, exec failed
      NSString *errorMsg = [NSString stringWithFormat:@"Failed to execute command: %s\n\nError: %s\n\nMake sure the executable is installed and available in your PATH.",
                            command, strerror(errno)];
      showError(errorMsg);
      free(newArgv);
      ret = 1;
    }
  @catch (NSException *exception)
    {
      NSString *errorMsg = [NSString stringWithFormat:@"An unexpected error occurred:\n\n%@\n\nReason: %@",
                            [exception name], [exception reason]];
      showError(errorMsg);
      ret = 1;
    }

cleanup:
  [pool release];
  return ret;
}
