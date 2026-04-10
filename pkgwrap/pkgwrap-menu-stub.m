/*
 * Copyright (c) 2026 Joseph Maloney
 *
 * pkgwrap-menu-stub — Registers a stub application menu with Gershwin
 * Menu.app for bundled Linux applications.  Provides the standard
 * app-name menu (Services, Hide, Quit) that appears to the left of
 * the application's own DBus menus.
 *
 * Usage: pkgwrap-menu-stub <app-name> <pid>
 *
 * The helper monitors X11 for a window owned by <pid>, registers the
 * stub menu via the GNUstep MenuServer DO protocol, handles Quit/Hide
 * callbacks, and exits when the monitored process terminates.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <signal.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

/* ── Menu server protocol (must match Menu.app's GNUStepMenuIPC.h) ── */

@protocol GSGNUstepMenuServer
- (oneway void)updateMenuForWindow:(NSNumber *)windowId
                          menuData:(NSDictionary *)menuData
                        clientName:(NSString *)clientName;
- (oneway void)unregisterWindow:(NSNumber *)windowId
                       clientName:(NSString *)clientName;
@end

@protocol GSGNUstepMenuClient
- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath
                            forWindow:(NSNumber *)windowId;
- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId;
@end

/* ── Helper implementation ──────────────────────────────────────── */

@interface PWMenuStub : NSObject <GSGNUstepMenuClient>
{
  NSString *_appName;
  pid_t     _targetPid;
  NSString *_clientName;
  NSNumber *_windowId;
  NSDistantObject<GSGNUstepMenuServer> *_serverProxy;
  NSConnection *_clientConnection;
  NSDictionary *_menuData;
  BOOL _registered;
}

- (instancetype)initWithAppName:(NSString *)name pid:(pid_t)pid;
- (void)run;
@end

@implementation PWMenuStub

- (instancetype)initWithAppName:(NSString *)name pid:(pid_t)pid
{
  self = [super init];
  if (self)
    {
      _appName = [name copy];
      _targetPid = pid;
      _clientName = [[NSString stringWithFormat:
        @"org.gnustep.Gershwin.MenuClient.pkgwrap.%d", getpid()] retain];
      _registered = NO;
    }
  return self;
}

/* Build the stub menu data in the format Menu.app expects. */
- (NSDictionary *)buildMenuData
{
  /* Separator item */
  NSDictionary *sep = @{@"isSeparator": @YES};

  /* Services submenu (empty — Menu.app populates it) */
  NSDictionary *servicesItem = @{
    @"title": @"Services",
    @"enabled": @YES,
    @"submenu": @{
      @"title": @"Services",
      @"items": @[]
    }
  };

  /* Hide <App> */
  NSDictionary *hideItem = @{
    @"title": [NSString stringWithFormat:@"Hide %@", _appName],
    @"enabled": @YES,
    @"keyEquivalent": @"h",
    @"keyEquivalentModifierMask":
      [NSNumber numberWithUnsignedInt:(1 << 17)]  /* NSCommandKeyMask */
  };

  /* Hide Others */
  NSDictionary *hideOthersItem = @{
    @"title": @"Hide Others",
    @"enabled": @YES,
    @"keyEquivalent": @"h",
    @"keyEquivalentModifierMask":
      [NSNumber numberWithUnsignedInt:((1 << 17) | (1 << 19))]  /* Cmd+Alt */
  };

  /* Show All */
  NSDictionary *showAllItem = @{
    @"title": @"Show All",
    @"enabled": @YES,
  };

  /* Quit <App> */
  NSDictionary *quitItem = @{
    @"title": [NSString stringWithFormat:@"Quit %@", _appName],
    @"enabled": @YES,
    @"keyEquivalent": @"q",
    @"keyEquivalentModifierMask":
      [NSNumber numberWithUnsignedInt:(1 << 17)]  /* NSCommandKeyMask */
  };

  /* The top-level menu's items become menu bar buttons.
   * Wrap everything in a single submenu named after the app
   * so it appears as one dropdown in the menu bar. */
  NSDictionary *appMenu = @{
    @"title": _appName,
    @"enabled": @YES,
    @"submenu": @{
      @"title": _appName,
      @"items": @[servicesItem, sep, hideItem, hideOthersItem, showAllItem, sep, quitItem]
    }
  };

  return @{
    @"title": _appName,
    @"items": @[appMenu]
  };
}

/* X11 error handler — suppress BadWindow errors from windows that
 * disappear between listing and querying. */
/* Suppress all X11 errors — we're just probing windows, and any
 * error (BadWindow, BadMatch, etc.) is harmless for our use case. */
static int x11ErrorHandler(Display *dpy, XErrorEvent *ev)
{
  (void)dpy;
  (void)ev;
  return 0;
}

/* Scan X11 for a window owned by _targetPid. */
- (unsigned long)findWindowForPid
{
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy)
    return 0;

  XSetErrorHandler(x11ErrorHandler);

  Atom pidAtom = XInternAtom(dpy, "_NET_WM_PID", True);
  if (pidAtom == None)
    {
      XCloseDisplay(dpy);
      return 0;
    }

  Atom clientList = XInternAtom(dpy, "_NET_CLIENT_LIST", True);
  if (clientList == None)
    {
      XCloseDisplay(dpy);
      return 0;
    }

  Atom actualType;
  int actualFormat;
  unsigned long nItems, bytesAfter;
  unsigned char *data = NULL;

  Window root = DefaultRootWindow(dpy);
  int status = XGetWindowProperty(dpy, root, clientList,
                                  0, 4096, False, XA_WINDOW,
                                  &actualType, &actualFormat,
                                  &nItems, &bytesAfter, &data);

  unsigned long found = 0;
  if (status == Success && data)
    {
      Window *windows = (Window *)data;

      /* First pass: match by _NET_WM_PID (reliable when set) */
      if (pidAtom != None)
        {
          for (unsigned long i = 0; i < nItems; i++)
            {
              unsigned char *pidData = NULL;
              Atom pidType;
              int pidFormat;
              unsigned long pidItems, pidBytes;

              int ps = XGetWindowProperty(dpy, windows[i], pidAtom,
                                          0, 1, False, XA_CARDINAL,
                                          &pidType, &pidFormat,
                                          &pidItems, &pidBytes, &pidData);
              if (ps == Success && pidData && pidItems > 0)
                {
                  uint32_t winPid = *(uint32_t *)pidData;
                  if ((pid_t)winPid == _targetPid)
                    {
                      found = windows[i];
                      XFree(pidData);
                      break;
                    }
                  XFree(pidData);
                }
            }
        }

      /* Second pass: if no PID match, try WM_CLASS (older apps like
       * xpdf don't set _NET_WM_PID).  Match the class name against
       * our app name case-insensitively. */
      if (found == 0)
        {
          NSString *lowerApp = [_appName lowercaseString];
          for (unsigned long i = 0; i < nItems; i++)
            {
              XClassHint classHint;
              if (XGetClassHint(dpy, windows[i], &classHint))
                {
                  BOOL match = NO;
                  if (classHint.res_class)
                    {
                      NSString *cls = [NSString
                        stringWithUTF8String:classHint.res_class];
                      if ([[cls lowercaseString] isEqualToString:lowerApp])
                        match = YES;
                    }
                  if (!match && classHint.res_name)
                    {
                      NSString *rn = [NSString
                        stringWithUTF8String:classHint.res_name];
                      if ([[rn lowercaseString] isEqualToString:lowerApp])
                        match = YES;
                    }
                  if (classHint.res_class) XFree(classHint.res_class);
                  if (classHint.res_name) XFree(classHint.res_name);

                  if (match)
                    {
                      found = windows[i];
                      break;
                    }
                }
            }
        }

      XFree(data);
    }

  XCloseDisplay(dpy);
  return found;
}

/* Register our menu with Menu.app for the given window. */
- (BOOL)registerMenuForWindow:(unsigned long)windowId
{
  @try
    {
      NSConnection *serverConn =
        [NSConnection connectionWithRegisteredName:
          @"org.gnustep.Gershwin.MenuServer" host:nil];
      if (!serverConn)
        return NO;

      _serverProxy = (NSDistantObject<GSGNUstepMenuServer> *)
        [[serverConn rootProxy] retain];
      [(NSDistantObject *)_serverProxy
        setProtocolForProxy:@protocol(GSGNUstepMenuServer)];

      _windowId = [[NSNumber numberWithUnsignedLong:windowId] retain];
      _menuData = [[self buildMenuData] retain];

      [_serverProxy updateMenuForWindow:_windowId
                               menuData:_menuData
                             clientName:_clientName];
      _registered = YES;
      return YES;
    }
  @catch (NSException *e)
    {
      fprintf(stderr, "pkgwrap-menu-stub: failed to register menu: %s\n",
              [[e reason] UTF8String]);
      return NO;
    }
}

/* ── GSGNUstepMenuClient protocol ── */

- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath
                            forWindow:(NSNumber *)windowId
{
  if ([indexPath count] < 1)
    return;

  int itemIndex = [[indexPath lastObject] intValue];

  /* Map item indices to actions.
   * Menu structure: Services(0), sep(1), Hide(2), HideOthers(3),
   *                 ShowAll(4), sep(5), Quit(6) */
  switch (itemIndex)
    {
    case 2:  /* Hide */
      {
        /* Minimize the window via X11 */
        Display *dpy = XOpenDisplay(NULL);
        if (dpy)
          {
            XSetErrorHandler(x11ErrorHandler);
            XIconifyWindow(dpy, [windowId unsignedLongValue],
                           DefaultScreen(dpy));
            XSync(dpy, False);
            XCloseDisplay(dpy);
          }
        break;
      }
    case 6:  /* Quit */
      {
        /* Send SIGTERM to the application */
        kill(_targetPid, SIGTERM);
        break;
      }
    default:
      break;
    }
}

- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId
{
  if (_serverProxy && _menuData && _clientName)
    {
      @try
        {
          [_serverProxy updateMenuForWindow:windowId
                                   menuData:_menuData
                                 clientName:_clientName];
        }
      @catch (NSException *e)
        {
          /* Server may have restarted; silently ignore */
        }
    }
}

/* Check if the target process is still alive. */
- (BOOL)processAlive
{
  return (kill(_targetPid, 0) == 0);
}

/* Main run loop. */
- (void)run
{
  /* Register ourselves as a menu client */
  _clientConnection = [[NSConnection alloc] init];
  [_clientConnection setRootObject:self];
  if (![_clientConnection registerName:_clientName])
    {
      fprintf(stderr, "pkgwrap-menu-stub: failed to register client %s\n",
              [_clientName UTF8String]);
      return;
    }

  NSPort *port = [_clientConnection receivePort];
  [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];

  /* Poll for the target window to appear, then register.
   * Also monitor process liveness. */
  NSTimer *timer = [NSTimer
    scheduledTimerWithTimeInterval:0.5
                           target:self
                         selector:@selector(pollTick:)
                         userInfo:nil
                          repeats:YES];
  (void)timer;

  [[NSRunLoop currentRunLoop] run];
}

- (void)pollTick:(NSTimer *)timer
{
  /* Exit if the target process has died */
  if (![self processAlive])
    {
      if (_registered && _serverProxy && _windowId)
        {
          @try
            {
              [_serverProxy unregisterWindow:_windowId
                                  clientName:_clientName];
            }
          @catch (NSException *e) { /* ignore */ }
        }
      [timer invalidate];
      exit(0);
    }

  /* Try to find and register the window if not yet done */
  if (!_registered)
    {
      unsigned long wid = [self findWindowForPid];
      if (wid != 0)
        {
          if ([self registerMenuForWindow:wid])
            {
              /* Once registered, slow down polling (just checking liveness) */
              [timer invalidate];
              [NSTimer scheduledTimerWithTimeInterval:2.0
                                              target:self
                                            selector:@selector(pollTick:)
                                            userInfo:nil
                                             repeats:YES];
            }
        }
    }
}

- (void)dealloc
{
  [_appName release];
  [_clientName release];
  [_windowId release];
  [_serverProxy release];
  [_clientConnection release];
  [_menuData release];
  [super dealloc];
}

@end

/* ── Main ───────────────────────────────────────────────────────── */

int main(int argc, char *argv[])
{
  if (argc < 3)
    {
      fprintf(stderr, "Usage: pkgwrap-menu-stub <app-name> <pid>\n");
      return 1;
    }

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSString *appName = [NSString stringWithUTF8String:argv[1]];
  pid_t pid = (pid_t)atoi(argv[2]);

  if (pid <= 0)
    {
      fprintf(stderr, "pkgwrap-menu-stub: invalid pid\n");
      [pool release];
      return 1;
    }

  PWMenuStub *stub = [[PWMenuStub alloc] initWithAppName:appName pid:pid];
  [stub run];

  [stub release];
  [pool release];
  return 0;
}
