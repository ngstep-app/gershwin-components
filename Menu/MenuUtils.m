/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MenuUtils.h"
#import <X11/Xlib.h>
#import <X11/Xutil.h>
#import <X11/Xatom.h>

static Display *g_display = NULL;
static NSLock *g_displayLock = nil;

static Display* getSharedDisplay(void) {
    if (g_displayLock == nil) {
        g_displayLock = [[NSLock alloc] init];
    }
    
    [g_displayLock lock];
    if (g_display == NULL) {
        g_display = XOpenDisplay(NULL);
    }
    [g_displayLock unlock];
    
    return g_display;
}

@implementation MenuUtils

+ (NSString *)getApplicationNameForWindow:(unsigned long)windowId
{
    // Validate window ID - 0 means no window
    if (windowId == 0) {
        NSLog(@"MenuUtils: Window ID is 0 (no active window), returning nil");
        return nil;
    }

    Display *display = getSharedDisplay();
    if (!display) {
        return nil;
    }

    // First validate that the window still exists before accessing properties
    XWindowAttributes attrs;
    if (XGetWindowAttributes(display, (Window)windowId, &attrs) != Success) {
        NSLog(@"MenuUtils: Window %lu no longer exists, skipping property access", windowId);
        return nil;
    }

    // Try to get the application name from WM_CLASS first
    XClassHint classHint = {NULL, NULL};
    NSString *className = nil;

    if (XGetClassHint(display, (Window)windowId, &classHint) == Success) {
        if (classHint.res_class != NULL) {
            className = [NSString stringWithUTF8String:classHint.res_class];
        }
        // XFreeStringList handles both res_class and res_name properly
        if (classHint.res_class != NULL || classHint.res_name != NULL) {
            char *strings[3] = {classHint.res_class, classHint.res_name, NULL};
            XFreeStringList(strings);
        }
    }

    if (className && [className length] > 0) {
        // Normalize application names for better cache consistency
        NSString *normalizedName = [className lowercaseString];
        if ([normalizedName isEqualToString:@"gimp"] ||
            [normalizedName hasPrefix:@"gimp-"]) {
            return @"GIMP";
        } else if ([normalizedName isEqualToString:@"inkscape"]) {
            return @"Inkscape";
        } else if ([normalizedName isEqualToString:@"libreoffice"]) {
            return @"LibreOffice";
        }
        return className;
    }

    // Fallback to window title, try to extract application name
    XTextProperty windowName;
    if (XGetWMName(display, (Window)windowId, &windowName) == Success) {
        NSString *title = nil;
        if (windowName.value) {
            title = [NSString stringWithUTF8String:(char *)windowName.value];
            XFree(windowName.value);
        }

        // Extract application name from window title
        if (title && [title length] > 0) {
            // Special handling for GIMP windows
            if ([title containsString:@"GIMP"] || [title containsString:@"GNU Image Manipulation Program"]) {
                return @"GIMP";
            }

            // Look for patterns like "Document - AppName" or "Title - AppName"
            NSRange dashRange = [title rangeOfString:@" - " options:NSBackwardsSearch];
            if (dashRange.location != NSNotFound) {
                NSString *appName = [title substringFromIndex:dashRange.location + 3];
                if ([appName length] > 0) {
                    return appName;
                }
            }
            // If no dash pattern, return the whole title as fallback
            return title;
        }
    }
    
    return nil;
}

+ (BOOL)isWindowValid:(unsigned long)windowId
{
    Display *display = getSharedDisplay();
    if (!display) {
        return NO;
    }
    
    XWindowAttributes attrs;
    BOOL valid = (XGetWindowAttributes(display, (Window)windowId, &attrs) == Success);
    
    return valid;
}

+ (BOOL)isDesktopWindow:(unsigned long)windowId
{
    if (windowId == 0) {
        return NO;
    }
    
    Display *display = getSharedDisplay();
    if (!display) {
        return NO;
    }
    
    // Check if window has _NET_WM_WINDOW_TYPE_DESKTOP
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *prop = NULL;
    BOOL isDesktop = NO;
    
    Atom windowTypeAtom = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
    Atom desktopTypeAtom = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
    
    if (XGetWindowProperty(display, (Window)windowId, windowTypeAtom,
                          0, (~0L), False, XA_ATOM,
                          &actualType, &actualFormat, &nitems, &bytesAfter,
                          &prop) == Success && prop) {
        Atom *types = (Atom *)prop;
        for (unsigned long i = 0; i < nitems; i++) {
            if (types[i] == desktopTypeAtom) {
                isDesktop = YES;
                break;
            }
        }
        XFree(prop);
    }
    
    return isDesktop;
}

+ (NSArray *)getAllWindows
{
    Display *display = getSharedDisplay();
    if (!display) {
        return [NSArray array];
    }
    
    Window root = DefaultRootWindow(display);
    Window parent, *children;
    unsigned int nchildren;
    
    NSMutableArray *windows = [NSMutableArray array];
    
    if (XQueryTree(display, root, &root, &parent, &children, &nchildren) == Success) {
        for (unsigned int i = 0; i < nchildren; i++) {
            XWindowAttributes attrs;
            if (XGetWindowAttributes(display, children[i], &attrs) == Success) {
                if (attrs.map_state == IsViewable && attrs.class == InputOutput) {
                    [windows addObject:[NSNumber numberWithUnsignedLong:children[i]]];
                }
            }
        }
        XFree(children);
    }
    
    return windows;
}

+ (unsigned long)getActiveWindow
{
    Display *display = getSharedDisplay();
    if (!display) {
        return 0;
    }
    
    Window root = DefaultRootWindow(display);
    Window activeWindow = 0;
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *prop = NULL;
    
    Atom activeWindowAtom = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
    if (XGetWindowProperty(display, root, activeWindowAtom,
                          0, 1, False, AnyPropertyType,
                          &actualType, &actualFormat, &nitems, &bytesAfter,
                          &prop) == Success && prop) {
        activeWindow = *(Window*)prop;
        XFree(prop);
    }
    
    return activeWindow;
}

+ (NSString *)getWindowProperty:(unsigned long)windowId atomName:(NSString *)atomName
{
    Display *display = getSharedDisplay();
    if (!display) {
        return nil;
    }
    
    Atom atom = XInternAtom(display, [atomName UTF8String], False);
    if (atom == None) {
        return nil;
    }
    
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *prop = NULL;
    
    if (XGetWindowProperty(display, (Window)windowId, atom,
                          0, 1024, False, AnyPropertyType,
                          &actualType, &actualFormat, &nitems, &bytesAfter,
                          &prop) == Success && prop) {
        
        NSString *result = nil;
        if (actualType == XA_STRING || actualFormat == 8) {
            result = [NSString stringWithUTF8String:(char *)prop];
        }
        
        XFree(prop);
        return result;
    }
    
    return nil;
}

+ (NSString*)getWindowMenuService:(unsigned long)windowId
{
    return [self getWindowProperty:windowId atomName:@"_KDE_NET_WM_APPMENU_SERVICE_NAME"];
}

+ (NSString*)getWindowMenuPath:(unsigned long)windowId
{
    return [self getWindowProperty:windowId atomName:@"_KDE_NET_WM_APPMENU_OBJECT_PATH"];
}

+ (BOOL)setWindowMenuService:(NSString*)service path:(NSString*)path forWindow:(unsigned long)windowId
{
    Display *display = getSharedDisplay();
    if (!display) {
        NSLog(@"MenuUtils: Failed to open X11 display");
        return NO;
    }
    
    BOOL success = YES;
    
    // Set the service name property
    if (service) {
        Atom serviceAtom = XInternAtom(display, "_KDE_NET_WM_APPMENU_SERVICE_NAME", False);
        const char *serviceStr = [service UTF8String];
        int result = XChangeProperty(display, (Window)windowId, serviceAtom, XA_STRING, 8,
                                   PropModeReplace, (unsigned char*)serviceStr, strlen(serviceStr));
        if (result != Success) {
            NSLog(@"MenuUtils: Failed to set service property for window %lu", windowId);
            success = NO;
        } else {
            NSLog(@"MenuUtils: Set _KDE_NET_WM_APPMENU_SERVICE_NAME=%@ for window %lu", service, windowId);
        }
    }
    
    // Set the object path property
    if (path) {
        Atom pathAtom = XInternAtom(display, "_KDE_NET_WM_APPMENU_OBJECT_PATH", False);
        const char *pathStr = [path UTF8String];
        int result = XChangeProperty(display, (Window)windowId, pathAtom, XA_STRING, 8,
                                   PropModeReplace, (unsigned char*)pathStr, strlen(pathStr));
        if (result != Success) {
            NSLog(@"MenuUtils: Failed to set path property for window %lu", windowId);
            success = NO;
        } else {
            NSLog(@"MenuUtils: Set _KDE_NET_WM_APPMENU_OBJECT_PATH=%@ for window %lu", path, windowId);
        }
    }
    
    XFlush(display);
    return success;
}

+ (BOOL)advertiseGlobalMenuSupport
{
    Display *display = getSharedDisplay();
    if (!display) {
        NSLog(@"MenuUtils: Failed to open X11 display for advertising global menu support");
        return NO;
    }
    
    Window root = DefaultRootWindow(display);
    BOOL success = YES;
    
    // Set _NET_SUPPORTING_WM_CHECK to advertise window manager support
    Atom supportingWmAtom = XInternAtom(display, "_NET_SUPPORTING_WM_CHECK", False);
    if (supportingWmAtom != None) {
        // Create a dummy window for WM identification
        Window dummyWindow = XCreateSimpleWindow(display, root, -100, -100, 1, 1, 0, 0, 0);
        XChangeProperty(display, root, supportingWmAtom, XA_WINDOW, 32,
                       PropModeReplace, (unsigned char*)&dummyWindow, 1);
        XChangeProperty(display, dummyWindow, supportingWmAtom, XA_WINDOW, 32,
                       PropModeReplace, (unsigned char*)&dummyWindow, 1);
        
        // Set WM name
        Atom wmNameAtom = XInternAtom(display, "_NET_WM_NAME", False);
        const char *wmName = "Menu.app Global Menu";
        XChangeProperty(display, dummyWindow, wmNameAtom, XInternAtom(display, "UTF8_STRING", False), 8,
                       PropModeReplace, (unsigned char*)wmName, strlen(wmName));
        
        NSLog(@"MenuUtils: Set _NET_SUPPORTING_WM_CHECK for global menu support");
    }
    
    // Set _NET_SUPPORTED to advertise supported features
    Atom supportedAtom = XInternAtom(display, "_NET_SUPPORTED", False);
    if (supportedAtom != None) {
        Atom supportedFeatures[] = {
            XInternAtom(display, "_NET_WM_NAME", False),
            XInternAtom(display, "_NET_ACTIVE_WINDOW", False),
            XInternAtom(display, "_KDE_NET_WM_APPMENU_SERVICE_NAME", False),
            XInternAtom(display, "_KDE_NET_WM_APPMENU_OBJECT_PATH", False)
        };
        
        XChangeProperty(display, root, supportedAtom, XA_ATOM, 32,
                       PropModeReplace, (unsigned char*)supportedFeatures, 
                       sizeof(supportedFeatures) / sizeof(Atom));
        
        NSLog(@"MenuUtils: Set _NET_SUPPORTED with global menu atoms");
    }
    
    // Set KDE-specific property to indicate global menu support
    Atom kdeMenuAtom = XInternAtom(display, "_KDE_GLOBAL_MENU_AVAILABLE", False);
    if (kdeMenuAtom != None) {
        unsigned long value = 1;
        XChangeProperty(display, root, kdeMenuAtom, XA_CARDINAL, 32,
                       PropModeReplace, (unsigned char*)&value, 1);
        
        NSLog(@"MenuUtils: Set _KDE_GLOBAL_MENU_AVAILABLE=1 on root window");
    }
    
    // Set Unity-specific property for Ubuntu compatibility
    Atom unityMenuAtom = XInternAtom(display, "_UNITY_GLOBAL_MENU", False);
    if (unityMenuAtom != None) {
        unsigned long value = 1;
        XChangeProperty(display, root, unityMenuAtom, XA_CARDINAL, 32,
                       PropModeReplace, (unsigned char*)&value, 1);
        
        NSLog(@"MenuUtils: Set _UNITY_GLOBAL_MENU=1 on root window");
    }
    
    XFlush(display);
    XSync(display, False);
    
    NSLog(@"MenuUtils: Successfully advertised global menu support on root window");
    return success;
}

+ (void)removeGlobalMenuSupport
{
    Display *display = getSharedDisplay();
    if (!display) {
        return;
    }
    
    // Remove the global menu properties
    Window root = DefaultRootWindow(display);
    
    Atom kdeMenuAtom = XInternAtom(display, "_KDE_GLOBAL_MENU_AVAILABLE", False);
    if (kdeMenuAtom != None) {
        XDeleteProperty(display, root, kdeMenuAtom);
    }
    
    Atom unityMenuAtom = XInternAtom(display, "_UNITY_GLOBAL_MENU", False);
    if (unityMenuAtom != None) {
        XDeleteProperty(display, root, unityMenuAtom);
    }
    
    XFlush(display);
    
    NSLog(@"MenuUtils: Removed global menu support properties from root window");
}

@end
