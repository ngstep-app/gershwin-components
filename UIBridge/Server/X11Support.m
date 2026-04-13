/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "X11Support.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/keysym.h>

@implementation X11Support

static Display *display = NULL;

+ (Display *)display {
    if (!display) {
        display = XOpenDisplay(NULL);
        if (!display) {
            NSDebugLLog(@"gwcomp", @"[X11Support] Failed to open X display");
        }
    }
    return display;
}

+ (void)cleanup {
    if (display) {
        XCloseDisplay(display);
        display = NULL;
    }
}

+ (NSArray *)windowList {
    Display *d = [self display];
    if (!d) return @[];
    
    Window root = DefaultRootWindow(d);
    Window parent;
    Window *children = NULL;
    unsigned int nchildren = 0;
    
    NSMutableArray *result = [NSMutableArray array];
    
    if (XQueryTree(d, root, &root, &parent, &children, &nchildren)) {
        for (unsigned int i = 0; i < nchildren; i++) {
            [result addObject:@(children[i])];
        }
        if (children) XFree(children);
    }
    
    return result;
}

+ (NSDictionary *)windowInfo:(unsigned long)xid {
    Display *d = [self display];
    if (!d) return nil;
    
    Window w = (Window)xid;
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(d, w, &attrs)) {
        return nil;
    }
    
    // Get Property: _NET_WM_NAME or WM_NAME
    NSString *title = @"";
    char *name = NULL;
    if (XFetchName(d, w, &name) && name) {
        title = [NSString stringWithUTF8String:name];
        XFree(name);
    }
    
    // Get PID: _NET_WM_PID
    unsigned long pid = 0;
    Atom atomPID = XInternAtom(d, "_NET_WM_PID", True);
    if (atomPID != None) {
        Atom actualType;
        int actualFormat;
        unsigned long nItems;
        unsigned long bytesAfter;
        unsigned char *propPID = NULL;
        if (XGetWindowProperty(d, w, atomPID, 0, 1, False, XA_CARDINAL,
                               &actualType, &actualFormat, &nItems, &bytesAfter, &propPID) == Success) {
            if (propPID) {
                pid = *((unsigned long *)propPID);
                XFree(propPID);
            }
        }
    }
    
    return @{
        @"id": @(w),
        @"x": @(attrs.x),
        @"y": @(attrs.y),
        @"width": @(attrs.width),
        @"height": @(attrs.height),
        @"map_state": @(attrs.map_state), // IsViewable=2
        @"title": title,
        @"pid": @(pid)
    };
}

+ (void)simulateMouseMoveTo:(NSPoint)point {
    Display *d = [self display];
    if (!d) return;
    
    Window root = DefaultRootWindow(d);
    XWarpPointer(d, None, root, 0, 0, 0, 0, (int)point.x, (int)point.y);
    XFlush(d);
}

static void SendButtonEvent(Display *d, int button, Bool press) {
    Window root = DefaultRootWindow(d);
    Window child = None;
    int root_x, root_y, win_x, win_y;
    unsigned int mask;
    
    // Get current pointer position
    XQueryPointer(d, root, &root, &child, &root_x, &root_y, &win_x, &win_y, &mask);
    
    // Target window is child if exists, else root
    Window target = (child != None) ? child : root;
    
    XEvent event;
    memset(&event, 0, sizeof(event));
    
    event.type = press ? ButtonPress : ButtonRelease;
    event.xbutton.button = button;
    event.xbutton.same_screen = True;
    event.xbutton.subwindow = None; // Should probably be child if we targeted root?
    event.xbutton.window = target;
    event.xbutton.root = root;
    event.xbutton.x_root = root_x;
    event.xbutton.y_root = root_y;
    event.xbutton.x = (child != None) ? win_x : root_x;
    event.xbutton.y = (child != None) ? win_y : root_y;
    event.xbutton.time = CurrentTime;
    
    XSendEvent(d, target, True, ButtonPressMask | ButtonReleaseMask, &event);
    XFlush(d);
}

+ (void)simulateClick:(int)button {
    Display *d = [self display];
    if (!d) return;
    
    SendButtonEvent(d, button, True); // Press
    SendButtonEvent(d, button, False); // Release
}

static void SendKeyEvent(Display *d, KeyCode keycode, Bool press) {
    Window root = DefaultRootWindow(d);
    Window focus;
    int revert;
    XGetInputFocus(d, &focus, &revert);
    
    if (focus == None) focus = root;
    
    XEvent event;
    memset(&event, 0, sizeof(event));
    
    event.type = press ? KeyPress : KeyRelease;
    event.xkey.keycode = keycode;
    event.xkey.window = focus;
    event.xkey.root = root;
    event.xkey.same_screen = True;
    event.xkey.time = CurrentTime;
    
    XSendEvent(d, focus, True, KeyPressMask | KeyReleaseMask, &event);
    XFlush(d);
}

+ (void)simulateKeyStroke:(NSString *)keyString {
    Display *d = [self display];
    if (!d) return;
    
    for (NSUInteger i = 0; i < [keyString length]; i++) {
        unichar c = [keyString characterAtIndex:i];
        KeySym sym = NoSymbol;
        
        if (c >= 'a' && c <= 'z') sym = XK_a + (c - 'a');
        else if (c >= 'A' && c <= 'Z') sym = XK_A + (c - 'A');
        else if (c >= '0' && c <= '9') sym = XK_0 + (c - '0');
        else if (c == ' ') sym = XK_space;
        else if (c == '\n') sym = XK_Return;
        else if (c == '\t') sym = XK_Tab;
        
        if (sym != NoSymbol) {
             KeyCode code = XKeysymToKeycode(d, sym);
             if (code != 0) {
                 SendKeyEvent(d, code, True);
                 SendKeyEvent(d, code, False);
             }
        }
    }
}

@end
