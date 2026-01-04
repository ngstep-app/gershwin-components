/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// Compile-time configuration for fallback menus
// Set to 1 to enable fallback File->Close menus when no DBus menu is available
// Set to 0 to disable fallback menus completely
#define ENABLE_FALLBACK_MENUS 0

#import "AppMenuWidget.h"
#import "MenuProtocolManager.h"
#import "MenuUtils.h"
#import "X11ShortcutManager.h"
#import "GTKActionHandler.h"
#import "DBusMenuActionHandler.h"
#import "MenuCacheManager.h"
#import <X11/Xlib.h>
#import <X11/Xutil.h>
#import <X11/Xatom.h>
#import <GNUstepGUI/GSTheme.h>

// Global X11 error handling for BadWindow and other errors
static BOOL x11_error_occurred = NO;
static int x11_error_code = 0;
static AppMenuWidget *currentWidget = nil;
static NSMutableSet *invalidWindows = nil;  // Track windows that have generated X11 errors

// X11 error handler to prevent crashes
static int handleX11Error(Display *display, XErrorEvent *event)
{
    (void)display;  // Suppress unused parameter warning
    
    // Initialize invalid windows set if needed
    if (!invalidWindows) {
        invalidWindows = [[NSMutableSet alloc] init];
    }
    
    x11_error_occurred = YES;
    x11_error_code = event->error_code;
    
    if (event->error_code == BadWindow) {
        NSLog(@"AppMenuWidget: X11 BadWindow error (window disappeared) - error_code=%d, request_code=%d", 
              event->error_code, event->request_code);
        
        // Track this window as invalid to prevent future access
        if (event->resourceid != 0) {
            NSNumber *windowKey = [NSNumber numberWithUnsignedLong:event->resourceid];
            [invalidWindows addObject:windowKey];
            NSLog(@"AppMenuWidget: Marked window %lu as invalid to prevent future access", event->resourceid);
        }
              
        // If we have a current widget and the error is for our tracked window, clean up immediately
        if (currentWidget && event->resourceid != 0) {
            [currentWidget handleWindowDisappeared:event->resourceid];
        }
    } else if (event->error_code == BadDrawable) {
        NSLog(@"AppMenuWidget: X11 BadDrawable error - error_code=%d, request_code=%d", 
              event->error_code, event->request_code);
        
        // Also track bad drawables as invalid
        if (event->resourceid != 0) {
            NSNumber *windowKey = [NSNumber numberWithUnsignedLong:event->resourceid];
            [invalidWindows addObject:windowKey];
        }
    } else {
        NSLog(@"AppMenuWidget: X11 error - error_code=%d, request_code=%d", 
              event->error_code, event->request_code);
    }
    
    // Don't call the default error handler which would terminate the program
    return 0;
}

// Macro to safely wrap X11 calls with error handling
#define SAFE_X11_CALL(display, call, cleanup_code) do { \
    x11_error_occurred = NO; \
    x11_error_code = 0; \
    int (*oldHandler)(Display *, XErrorEvent *) = XSetErrorHandler(handleX11Error); \
    XSync(display, False); \
    \
    call; \
    \
    XSync(display, False); \
    XSetErrorHandler(oldHandler); \
    \
    if (x11_error_occurred) { \
        NSLog(@"AppMenuWidget: X11 error occurred during call, executing cleanup"); \
        cleanup_code; \
    } \
} while(0)

@interface AppMenuView : NSMenuView
@end

@implementation AppMenuView

- (void)drawRect:(NSRect)dirtyRect
{
    [[[GSTheme theme] menuItemBackgroundColor] set];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

@end

@implementation AppMenuWidget

+ (void)setCurrentWidget:(AppMenuWidget *)widget
{
    currentWidget = widget;
}

// Utility function to check if a window is safe to access
+ (BOOL)isWindowSafeToAccess:(Window)windowId
{
    if (windowId == 0) return NO;
    
    if (!invalidWindows) {
        invalidWindows = [[NSMutableSet alloc] init];
        return YES;  // If no tracking yet, assume safe
    }
    
    NSNumber *windowKey = [NSNumber numberWithUnsignedLong:windowId];
    BOOL isInvalid = [invalidWindows containsObject:windowKey];
    
    if (isInvalid) {
        NSLog(@"AppMenuWidget: Skipping X11 operation on invalid window %lu", windowId);
    }
    
    return !isInvalid;
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.menuView = nil;
        self.currentApplicationName = nil;
        self.currentWindowId = 0;
        self.currentMenu = nil;
        self.fallbackTimers = [NSMutableDictionary dictionary];
        
        // Register this widget for X11 error handling
        [AppMenuWidget setCurrentWidget:self];
        
        NSLog(@"AppMenuWidget: Initialized with frame %.0f,%.0f %.0fx%.0f", 
              frameRect.origin.x, frameRect.origin.y, frameRect.size.width, frameRect.size.height);
        
        // Mark that we're waiting for real menu content - don't set up placeholder yet
        self.isWaitingForMenu = YES;
        
        // Defer placeholder menu setup until after initialization completes
        // This ensures the view is fully ready before we try to set up and draw the menu
        [self performSelector:@selector(setupPlaceholderMenu) withObject:nil afterDelay:0.0];
    }
    return self;
}

- (void)setupPlaceholderMenu
{
    // Only set up if we still don't have a menu view
    if (self.menuView) {
        return;
    }
    
    NSLog(@"AppMenuWidget: Setting up placeholder menu with initial item (deferred)");
    NSMenu *placeholderMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *helloItem = [[NSMenuItem alloc] initWithTitle:@" " action:nil keyEquivalent:@""];
    [helloItem setEnabled:NO];
    [placeholderMenu addItem:helloItem];
    
    @try {
        [self setupMenuViewWithMenu:placeholderMenu];
        NSLog(@"AppMenuWidget: Successfully set up initial menu view with placeholder");
    }
    @catch (NSException *exception) {
        NSLog(@"AppMenuWidget: Exception during placeholder menu setup: %@", exception);
        self.menuView = nil;
    }
}

- (void)dealloc
{
    // Unregister from X11 error handling if we're the current widget
    if (currentWidget == self) {
        currentWidget = nil;
    }
    
    // Cancel any fallback timers
    for (NSTimer *timer in [self.fallbackTimers allValues]) {
        [timer invalidate];
    }
    [self.fallbackTimers removeAllObjects];
}

- (void)updateForActiveWindow
{
    
    if (!self.protocolManager) {
        NSLog(@"AppMenuWidget: No protocol manager available");
        return;
    }
    
    // Get the active window using X11
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"AppMenuWidget: Cannot open X11 display");
        return;
    }
    
    Window root = DefaultRootWindow(display);
    Window activeWindow = 0;
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *prop = NULL;
    
    // Get _NET_ACTIVE_WINDOW property
    Atom activeWindowAtom = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
    SAFE_X11_CALL(display, {
        if (XGetWindowProperty(display, root, activeWindowAtom,
                              0, 1, False, AnyPropertyType,
                              &actualType, &actualFormat, &nitems, &bytesAfter,
                              &prop) == Success && prop) {
            activeWindow = *(Window*)prop;
            XFree(prop);
        }
    }, {
        // Cleanup on error
        if (prop) {
            XFree(prop);
            prop = NULL;
        }
        NSLog(@"AppMenuWidget: Failed to get active window due to X11 error");
    });
    
    XCloseDisplay(display);
    
    if (activeWindow != self.currentWindowId) {
        NSLog(@"AppMenuWidget: Active window changed from %lu to %lu", self.currentWindowId, activeWindow);
        
        // Notify cache manager about window changes
        MenuCacheManager *cacheManager = [MenuCacheManager sharedManager];
        if (self.currentWindowId != 0) {
            [cacheManager windowBecameInactive:self.currentWindowId];
        }
        if (activeWindow != 0) {
            [cacheManager windowBecameActive:activeWindow];
        }
        
        // Check if this is a different application by comparing application names
        // Use @try/@catch to prevent crashes when accessing window properties of invalid/transitioning windows
        NSString *newAppName = nil;
        if (activeWindow != 0) {
            @try {
                newAppName = [MenuUtils getApplicationNameForWindow:activeWindow];
            }
            @catch (NSException *exception) {
                NSLog(@"AppMenuWidget: Exception getting app name for window %lu: %@", activeWindow, exception);
                newAppName = nil;
            }
        } else {
            NSLog(@"AppMenuWidget: Active window is 0 (no window), skipping app name lookup");
            newAppName = nil;
        }

        BOOL isDifferentApp = !self.currentApplicationName ||
                             ![self.currentApplicationName isEqualToString:newAppName];
        
        // Notify cache manager about application switch
        if (isDifferentApp && newAppName && self.currentApplicationName) {
            [cacheManager applicationSwitched:self.currentApplicationName toApp:newAppName];
        }
        
        self.currentWindowId = activeWindow;

        // Use @try/@catch to prevent crashes during menu setup for invalid/transitioning windows
        @try {
            [self displayMenuForWindow:activeWindow isDifferentApp:isDifferentApp];
        }
        @catch (NSException *exception) {
            NSLog(@"AppMenuWidget: Exception displaying menu for window %lu: %@", activeWindow, exception);
            // Clear menu on exception to prevent further issues
            [self clearMenu];
        }
        
        // For complex applications, try to pre-warm cache for other windows of same app
        if (newAppName && [cacheManager isComplexApplication:newAppName]) {
            [self performSelector:@selector(preWarmCacheForApplication:) 
                       withObject:newAppName 
                       afterDelay:0.5]; // Delay to avoid blocking current menu load
        }
    }
}

- (void)clearMenu
{
    [self clearMenu:YES];  // Default to clearing shortcuts
}

- (void)clearMenu:(BOOL)shouldUnregisterShortcuts
{
    // Only unregister shortcuts when switching to a different application
    if (shouldUnregisterShortcuts) {
        NSLog(@"AppMenuWidget: Unregistering all shortcuts for application change");
        [[X11ShortcutManager sharedManager] unregisterAllShortcuts];
    } else {
        NSLog(@"AppMenuWidget: Keeping shortcuts registered (same application)");
    }
    
    // Mark that we're waiting for a new menu - don't clear visuals yet
    self.isWaitingForMenu = YES;
    NSLog(@"AppMenuWidget: Marked as waiting for menu");
    
    self.currentApplicationName = nil;
    
    // Trigger redraw to reflect the waiting state
    // Only do this if we're not in a half-finished state
    if (self.window) {
        [self setNeedsDisplay:YES];
    }
}

- (void)displayMenuForWindow:(unsigned long)windowId
{
    [self displayMenuForWindow:windowId isDifferentApp:YES];
}

- (void)displayMenuForWindow:(unsigned long)windowId isDifferentApp:(BOOL)isDifferentApp
{
    // Defensive check: ensure we're initialized
    if (!self.protocolManager) {
        NSLog(@"AppMenuWidget: Protocol manager not initialized, cannot display menu for window %lu", windowId);
        return;
    }
    
    [self clearMenu:isDifferentApp];
    
    if (windowId == 0) {
        return;
    }
    
    // Get application name for this window
    NSString *appName = nil;
    @try {
        appName = [MenuUtils getApplicationNameForWindow:windowId];
    }
    @catch (NSException *exception) {
        NSLog(@"AppMenuWidget: Exception getting app name for window %lu in displayMenuForWindow: %@", windowId, exception);
        appName = nil;
    }

    if (appName && [appName length] > 0) {
        self.currentApplicationName = appName;
        NSLog(@"AppMenuWidget: Window %lu belongs to application: %@", windowId, appName);
    }
    
    NSLog(@"AppMenuWidget: Displaying menu for window %lu", windowId);
    
    // Check if this window has a DBus menu registered
    @try {
        if (![self.protocolManager hasMenuForWindow:windowId]) {
            NSLog(@"AppMenuWidget: No registered menu for window %lu yet", windowId);

            // DON'T trigger immediate scan here - it can interfere with app startup
            // The periodic scanning will pick it up safely
            // [self.protocolManager scanForExistingMenuServices];

            // Check if we should wait a moment for menu to appear
            if (![self.protocolManager hasMenuForWindow:windowId]) {
                // Prevent fallback menu for desktop windows
                if ([MenuUtils isDesktopWindow:windowId]) {
                    NSLog(@"AppMenuWidget: Suppressing fallback menu for desktop window %lu", windowId);
                    return;
                }

#if ENABLE_FALLBACK_MENUS
                // Schedule a delayed fallback (200ms) to avoid showing fallback immediately
                [self scheduleFallbackMenuForWindow:windowId delay:0.2];
#else
                NSLog(@"AppMenuWidget: Fallback menus disabled at compile time");
#endif
                return;
            }
        } else {
            // If we already have a menu, cancel any scheduled fallback
            [self cancelScheduledFallbackForWindow:windowId];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"AppMenuWidget: Exception during menu protocol check for window %lu: %@", windowId, exception);
        // Prevent fallback menu for desktop windows
        if ([MenuUtils isDesktopWindow:windowId]) {
            NSLog(@"AppMenuWidget: Suppressing fallback menu for desktop window %lu on exception", windowId);
            return;
        }
#if ENABLE_FALLBACK_MENUS
        // Create fallback File->Close menu on exception
        NSMenu *fallbackMenu = [self createFileMenuWithClose:windowId];
        [self loadMenu:fallbackMenu forWindow:windowId];
#else
        NSLog(@"AppMenuWidget: Exception occurred but fallback menus disabled at compile time");
#endif
        return;
    }
    
    NSLog(@"AppMenuWidget: ===== LOADING MENU FROM PROTOCOL MANAGER =====");
    NSLog(@"AppMenuWidget: This is where AboutToShow events should be triggered for submenus");

    // Get the menu from protocol manager for registered windows
    NSMenu *menu = nil;
    @try {
        menu = [self.protocolManager getMenuForWindow:windowId];
    }
    @catch (NSException *exception) {
        NSLog(@"AppMenuWidget: Exception getting menu from protocol manager for window %lu: %@", windowId, exception);
        menu = nil;
    }

    if (!menu) {
        NSLog(@"AppMenuWidget: Failed to get menu for window %lu (protocol manager), will provide fallback after short delay", windowId);
        // Prevent fallback menu for desktop windows
        if ([MenuUtils isDesktopWindow:windowId]) {
            NSLog(@"AppMenuWidget: Suppressing fallback menu for desktop window %lu", windowId);
            return;
        }
#if ENABLE_FALLBACK_MENUS
        // Schedule delayed fallback to allow menu to arrive (200ms)
        [self scheduleFallbackMenuForWindow:windowId delay:0.2];
#else
        NSLog(@"AppMenuWidget: Fallback menus disabled at compile time, no menu available for window %lu", windowId);
#endif
        return;
    }
    
    // Debug: Log menu details for placeholder detection
    NSLog(@"AppMenuWidget: Menu has %lu items", (unsigned long)[[menu itemArray] count]);
    if ([[menu itemArray] count] > 0) {
        NSMenuItem *firstItem = [[menu itemArray] objectAtIndex:0];
        NSLog(@"AppMenuWidget: First menu item: '%@' (enabled: %@)", [firstItem title], [firstItem isEnabled] ? @"YES" : @"NO");
    }
    
    BOOL isPlaceholder = [self isPlaceholderMenu:menu];
    NSLog(@"AppMenuWidget: isPlaceholderMenu: %@", isPlaceholder ? @"YES" : @"NO");
    
    // If this is a placeholder menu, replace it with a functional File menu
    if (isPlaceholder) {
        // Prevent fallback menu for desktop windows
        if ([MenuUtils isDesktopWindow:windowId]) {
            NSLog(@"AppMenuWidget: Suppressing fallback menu for desktop window %lu (placeholder menu)", windowId);
            return;
        }
#if ENABLE_FALLBACK_MENUS
        NSLog(@"AppMenuWidget: Replacing placeholder menu with File menu containing Close for window %lu", windowId);
        menu = [self createFileMenuWithClose:windowId];
#else
        NSLog(@"AppMenuWidget: Placeholder menu detected but fallback menus disabled at compile time");
        return;
#endif
    }
    
    [self loadMenu:menu forWindow:windowId];
}

- (void)setupMenuViewWithMenu:(NSMenu *)menu
{
    if (!menu) {
        NSLog(@"AppMenuWidget: Cannot setup menu view with nil menu");
        return;
    }

    NSLog(@"AppMenuWidget: Setting up menu view with menu: %@", [menu title]);
    
    // Set the current menu so drawRect knows we have menu content
    self.currentMenu = menu;
    
    // Lock the window to prevent flashing during menu updates
    NSWindow *window = [self window];
    if (window) {
        [window disableFlushWindow];
    }
    
    @try {
        // Remove any existing menu view to prevent crashes when adding new one
        if (self.menuView) {
            [self.menuView removeFromSuperview];
            self.menuView = nil;
            NSLog(@"AppMenuWidget: Removed existing menu view before creating new one");
        }

        // Calculate text width for positioning
        CGFloat textWidth = 0;
        if (self.currentApplicationName && [self.currentApplicationName length] > 0) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
                                       [NSColor colorWithCalibratedWhite:0.3 alpha:1.0], NSForegroundColorAttributeName,
                                       nil];
            
            NSSize textSize = [self.currentApplicationName sizeWithAttributes:attributes];
            textWidth = textSize.width + 0; // Add minimal padding
        }

        // Create a new horizontal menu view that fits within our widget frame, starting after the text
        NSRect menuViewFrame = NSMakeRect(textWidth, 0, [self bounds].size.width - textWidth, [self bounds].size.height);
        self.menuView = [[AppMenuView alloc] initWithFrame:menuViewFrame];

        if (!self.menuView) {
            NSLog(@"AppMenuWidget: Failed to create menu view - aborting setup");
            return;
        }

        // Configure the menu view for horizontal display (like a menu bar)
        [self.menuView setHorizontal:YES];
        [self.menuView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        // Set the menu for the menu view
        [self.menuView setMenu:menu];
        
        // Set ourselves as the delegate of the main menu to catch AboutToShow events
        [menu setDelegate:self];
        NSLog(@"AppMenuWidget: Set AppMenuWidget as delegate for main menu: %@", [menu title]);
        
        // Add comprehensive logging to each menu item
        NSArray *items = [menu itemArray];
        for (NSUInteger i = 0; i < [items count]; i++) {
            NSMenuItem *item = [items objectAtIndex:i];
            NSLog(@"AppMenuWidget: Setting up item %lu: '%@' (submenu: %@)", 
                  i, [item title], [item hasSubmenu] ? @"YES" : @"NO");
            
            // Set target and action for logging purposes
            if (![item hasSubmenu]) {
                [item setTarget:self];
                [item setAction:@selector(menuItemClicked:)];
                NSLog(@"AppMenuWidget: Set click action for non-submenu item: '%@'", [item title]);
            }
        }
        
        // Add the menu view to our widget (this makes it visible)
        [self addSubview:self.menuView];
        
        [self setNeedsDisplay:YES];
        
        NSLog(@"AppMenuWidget: Menu view setup complete with %lu menu items", 
              (unsigned long)[[menu itemArray] count]);
    }
    @finally {
        // Re-enable window drawing and flush all pending updates
        if (window) {
            [window enableFlushWindow];
            [window flushWindow];
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Only draw if we have menu items to display
    BOOL hasMenu = (self.currentMenu && [[self.currentMenu itemArray] count] > 0);
    BOOL isLoading = self.isWaitingForMenu;
    
    NSLog(@"AppMenuWidget: drawRect called - hasMenu=%@, isLoading=%@, currentMenu=%@", 
          hasMenu ? @"YES" : @"NO", isLoading ? @"YES" : @"NO", self.currentMenu);
    
    // If we're waiting for a menu but don't have one yet, keep the old menu visible
    if (!hasMenu && !isLoading) {
        // No menu to display and not waiting - clear the background completely
        NSLog(@"AppMenuWidget: No menus - clearing background");
        [[NSColor clearColor] set];
        NSRectFill([self bounds]);
        NSLog(@"AppMenuWidget: Background cleared");
        
        // Hide the menu view when there's no menu
        if (self.menuView) {
            [self.menuView setHidden:YES];
        }
        return;
    }
    
    // If waiting for menu, show placeholder or old menu
    if (isLoading && !hasMenu) {
        NSLog(@"AppMenuWidget: Waiting for real menu content, showing placeholder");
        
        // Show the placeholder menu if it exists
        if (self.menuView) {
            [self.menuView setHidden:NO];
        }
        return;
    }
    
    // Show new menu
    NSLog(@"AppMenuWidget: Drawing background and content");
    
    // Show the menu view when there's a menu
    if (self.menuView) {
        [self.menuView setHidden:NO];
    }
    // Don't fill background - let the MenuBarView background show through
    // The menu items themselves will be drawn by the menuView
    
    // Draw application name if we have one
    if (self.currentApplicationName && [self.currentApplicationName length] > 0) {
        NSLog(@"AppMenuWidget: Drawing app name: %@", self.currentApplicationName);
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
                                   [NSColor colorWithCalibratedWhite:0.3 alpha:1.0], NSForegroundColorAttributeName,
                                   nil];
        
        NSSize textSize = [self.currentApplicationName sizeWithAttributes:attributes];
        NSPoint textPoint = NSMakePoint(0, ([self bounds].size.height - textSize.height) / 2);
        
        [self.currentApplicationName drawAtPoint:textPoint withAttributes:attributes];
    }
    
    // Draw drop shadow below the menu bar (GNUstep compatible)
    NSLog(@"AppMenuWidget: Drawing shadow");
    NSRect shadowRect = NSMakeRect(0, [self bounds].size.height - 2, [self bounds].size.width, 6);
    NSColor *shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.18];
    [shadowColor set];
    NSRectFillUsingOperation(shadowRect, NSCompositeSourceOver);
    
    NSLog(@"AppMenuWidget: drawRect completed");

}

- (void)checkAndDisplayMenuForNewlyRegisteredWindow:(unsigned long)windowId
{
    // If we had a scheduled fallback for this window, cancel it — a real menu is now available
    [self cancelScheduledFallbackForWindow:windowId];

    // Get the currently active window using X11
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"AppMenuWidget: Cannot open X11 display for checking active window");
        return;
    }
    
    Window root = DefaultRootWindow(display);
    Window activeWindow = 0;
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *prop = NULL;
    
    // Get _NET_ACTIVE_WINDOW property
    Atom activeWindowAtom = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
    SAFE_X11_CALL(display, {
        if (XGetWindowProperty(display, root, activeWindowAtom,
                              0, 1, False, AnyPropertyType,
                              &actualType, &actualFormat, &nitems, &bytesAfter,
                              &prop) == Success && prop) {
            activeWindow = *(Window*)prop;
            XFree(prop);
        }
    }, {
        // Cleanup on error
        if (prop) {
            XFree(prop);
            prop = NULL;
        }
        NSLog(@"AppMenuWidget: Failed to get active window for newly registered window check due to X11 error");
    });
    
    XCloseDisplay(display);
    
    // If the newly registered window is the currently active window, display its menu immediately
    if (activeWindow == windowId) {
        NSLog(@"AppMenuWidget: Newly registered window %lu is currently active, displaying menu immediately", windowId);
        self.currentWindowId = activeWindow;
        @try {
            [self displayMenuForWindow:activeWindow isDifferentApp:YES];
        }
        @catch (NSException *exception) {
            NSLog(@"AppMenuWidget: Exception displaying menu for newly registered window %lu: %@", windowId, exception);
        }
    } else {
        NSLog(@"AppMenuWidget: Newly registered window %lu is not currently active (active: %lu)", windowId, activeWindow);
    }
}

// Debug method implementation

// MARK: - NSMenuDelegate Methods for Main Menu

- (void)menuWillOpen:(NSMenu *)menu
{
    NSLog(@"AppMenuWidget: ===== MAIN MENU WILL OPEN =====");
    NSLog(@"AppMenuWidget: menuWillOpen called for main menu: '%@'", [menu title] ?: @"(no title)");
    NSLog(@"AppMenuWidget: Main menu object: %@", menu);
    NSLog(@"AppMenuWidget: Main menu has %lu items", (unsigned long)[[menu itemArray] count]);
    NSLog(@"AppMenuWidget: Current window ID: %lu", self.currentWindowId);
    NSLog(@"AppMenuWidget: Current application: %@", self.currentApplicationName ?: @"(none)");
    // Log coordinates of the submenu itself
    if (self.menuView) {
        NSRect menuViewFrame = [self.menuView frame];
        NSRect menuViewFrameInWindow = [self.menuView convertRect:menuViewFrame toView:nil];
        NSPoint menuViewOriginScreen = [self.window convertBaseToScreen:menuViewFrameInWindow.origin];
        NSLog(@"AppMenuWidget: Submenu view frame: %@, screen origin: %@", NSStringFromRect(menuViewFrame), NSStringFromPoint(menuViewOriginScreen));
    }
    NSLog(@"AppMenuWidget: ===== MAIN MENU WILL OPEN COMPLETE =====");
}

- (void)menuDidClose:(NSMenu *)menu
{
    NSLog(@"AppMenuWidget: Main menu did close: '%@'", [menu title] ?: @"(no title)");
}

- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item
{
    if (item) {
        NSLog(@"AppMenuWidget: ===== MAIN MENU ITEM HIGHLIGHT =====");
        NSLog(@"AppMenuWidget: Main menu will highlight item: '%@' (has submenu: %@)", 
              [item title], [item hasSubmenu] ? @"YES" : @"NO");
        
        if ([item hasSubmenu]) {
            NSMenu *submenu = [item submenu];
            id<NSMenuDelegate> submenuDelegate = [submenu delegate];
            NSLog(@"AppMenuWidget: Item has submenu with %lu items", 
                  (unsigned long)[[submenu itemArray] count]);
            NSLog(@"AppMenuWidget: Submenu delegate: %@ (%@)", 
                  submenuDelegate, submenuDelegate ? NSStringFromClass([submenuDelegate class]) : @"nil");
            NSLog(@"AppMenuWidget: THIS IS WHERE ABOUTTOSHOW SHOULD BE TRIGGERED!");
            NSLog(@"AppMenuWidget: If you don't see AboutToShow logging after this, the delegate isn't working");
        }
        NSLog(@"AppMenuWidget: ===== END MAIN MENU ITEM HIGHLIGHT =====");
    } else {
        NSLog(@"AppMenuWidget: Main menu will unhighlight current item");
    }
}

- (BOOL)menu:(NSMenu *)menu updateItem:(NSMenuItem *)item atIndex:(NSInteger)index shouldCancel:(BOOL)shouldCancel
{
    NSLog(@"AppMenuWidget: Main menu update item at index %ld: '%@' (shouldCancel: %@)", 
          (long)index, [item title], shouldCancel ? @"YES" : @"NO");
    return YES; // Allow the update
}

- (NSInteger)numberOfItemsInMenu:(NSMenu *)menu
{
    NSInteger count = [[menu itemArray] count];
    NSLog(@"AppMenuWidget: Main menu numberOfItemsInMenu called, returning: %ld", (long)count);
    return count;
}

- (NSRect)confinementRectForMenu:(NSMenu *)menu onScreen:(NSScreen *)screen
{
    // Return the full screen bounds - no confinement
    NSRect screenFrame = [screen frame];
    NSLog(@"AppMenuWidget: confinementRectForMenu called, returning full screen bounds");
    return screenFrame;
}

// MARK: - Mouse Event Tracking

- (void)mouseEntered:(NSEvent *)theEvent
{
    NSLog(@"AppMenuWidget: ===== MOUSE ENTERED MENU AREA =====");
    NSLog(@"AppMenuWidget: Mouse entered at location: %@", NSStringFromPoint([theEvent locationInWindow]));
    [super mouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent
{
    NSLog(@"AppMenuWidget: ===== MOUSE EXITED MENU AREA =====");
    NSLog(@"AppMenuWidget: Mouse exited at location: %@", NSStringFromPoint([theEvent locationInWindow]));
    [super mouseExited:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
    NSPoint location = [theEvent locationInWindow];
    NSPoint localPoint = [self convertPoint:location fromView:nil];
    NSLog(@"AppMenuWidget: Mouse moved to: %@ (local: %@)", NSStringFromPoint(location), NSStringFromPoint(localPoint));
    
    // Check if we're over a specific menu item
    if (self.menuView) {
        NSPoint menuViewPoint = [self.menuView convertPoint:location fromView:nil];
        NSLog(@"AppMenuWidget: Menu view point: %@", NSStringFromPoint(menuViewPoint));
        
        // Try to determine which menu item we're over
        if ([self.menuView respondsToSelector:@selector(itemAtPoint:)]) {
            NSMenuItem *item = [(id)self.menuView performSelector:@selector(itemAtPoint:) withObject:[NSValue valueWithPoint:menuViewPoint]];
            if (item) {
                NSLog(@"AppMenuWidget: Mouse over menu item: '%@'", [item title]);
            }
        }
    }
    
    [super mouseMoved:theEvent];
}

- (void)mouseDown:(NSEvent *)theEvent
{
    NSLog(@"AppMenuWidget: ===== MOUSE DOWN IN MENU =====");
    NSPoint location = [theEvent locationInWindow];
    NSPoint localPoint = [self convertPoint:location fromView:nil];
    NSLog(@"AppMenuWidget: Mouse down at: %@ (local: %@)", NSStringFromPoint(location), NSStringFromPoint(localPoint));
    
    if (self.menuView && self.currentMenu) {
        NSPoint menuViewPoint = [self.menuView convertPoint:location fromView:nil];
        NSLog(@"AppMenuWidget: Menu view click point: %@", NSStringFromPoint(menuViewPoint));
        
        // Check if we clicked on a menu item
        NSArray *items = [self.currentMenu itemArray];
        for (NSUInteger i = 0; i < [items count]; i++) {
            NSMenuItem *item = [items objectAtIndex:i];
            // Try to get the menu item's frame (this is a bit of a hack)
            NSRect itemFrame = NSMakeRect(i * 80, 0, 80, [self bounds].size.height); // Approximate
            if (NSPointInRect(localPoint, itemFrame)) {
                NSLog(@"AppMenuWidget: Clicked on menu item %lu: '%@'", i, [item title]);
                
                if ([item hasSubmenu]) {
                    NSLog(@"AppMenuWidget: Item has submenu - this should trigger AboutToShow!");
                    NSMenu *submenu = [item submenu];
                    id<NSMenuDelegate> delegate = [submenu delegate];
                    NSLog(@"AppMenuWidget: Submenu delegate: %@", delegate);
                    // Log coordinates of the menu item that opens the submenu
                    NSRect itemFrameInView = [self convertRect:itemFrame toView:nil];
                    NSPoint itemOriginScreen = [self.window convertBaseToScreen:itemFrameInView.origin];
                    NSLog(@"AppMenuWidget: Menu item frame: %@, screen origin: %@", NSStringFromRect(itemFrame), NSStringFromPoint(itemOriginScreen));
                    // Manually trigger menuWillOpen to test AboutToShow
                    if (delegate && [delegate respondsToSelector:@selector(menuWillOpen:)]) {
                        NSLog(@"AppMenuWidget: MANUALLY TRIGGERING menuWillOpen for testing...");
                        [delegate menuWillOpen:submenu];
                    }
                }
                break;
            }
        }
        
        // Let the menu view handle the click
        [self.menuView mouseDown:theEvent];
        NSLog(@"AppMenuWidget: Forwarded mouse down to menu view");
    }
    
    [super mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    NSLog(@"AppMenuWidget: ===== MOUSE UP IN MENU =====");
    NSLog(@"AppMenuWidget: Mouse up at: %@", NSStringFromPoint([theEvent locationInWindow]));
    
    if (self.menuView) {
        [self.menuView mouseUp:theEvent];
        NSLog(@"AppMenuWidget: Forwarded mouse up to menu view");
    }
    
}

// MARK: - Debug Methods

- (void)menuItemClicked:(NSMenuItem *)sender
{
    NSLog(@"AppMenuWidget: ===== MENU ITEM CLICKED =====");
    NSLog(@"AppMenuWidget: Clicked menu item: '%@'", [sender title]);
    NSLog(@"AppMenuWidget: Item tag: %ld", (long)[sender tag]);
    NSLog(@"AppMenuWidget: Item has submenu: %@", [sender hasSubmenu] ? @"YES" : @"NO");
    NSLog(@"AppMenuWidget: ===== END MENU ITEM CLICKED =====");
    
    // Forward to the original action if it exists
    if ([sender respondsToSelector:@selector(representedObject)] && [sender representedObject]) {
        id originalTarget = [sender representedObject];
        if ([originalTarget respondsToSelector:@selector(performSelector:withObject:)]) {
            NSLog(@"AppMenuWidget: Forwarding to original target: %@", originalTarget);
        }
    }
}

- (void)debugLogCurrentMenuState
{
    NSLog(@"AppMenuWidget: ===== DEBUG MENU STATE =====");
    NSLog(@"AppMenuWidget: Current window ID: %lu", self.currentWindowId);
    NSLog(@"AppMenuWidget: Current application: %@", self.currentApplicationName ?: @"(none)");
    NSLog(@"AppMenuWidget: Current menu: %@", self.currentMenu ? [self.currentMenu title] : @"(none)");
    
    if (self.currentMenu) {
        NSLog(@"AppMenuWidget: Current menu has %lu items", (unsigned long)[[self.currentMenu itemArray] count]);
        NSArray *items = [self.currentMenu itemArray];
        for (NSUInteger i = 0; i < [items count]; i++) {
            NSMenuItem *item = [items objectAtIndex:i];
            NSLog(@"AppMenuWidget: Item %lu: '%@' (submenu: %@)", 
                  i, [item title], [item hasSubmenu] ? @"YES" : @"NO");
        }
    }
    
    NSLog(@"AppMenuWidget: Menu view: %@", self.menuView);
    NSLog(@"AppMenuWidget: Protocol manager: %@", self.protocolManager);
    NSLog(@"AppMenuWidget: ===== END DEBUG MENU STATE =====");
}

- (BOOL)isPlaceholderMenu:(NSMenu *)menu
{
    if (!menu || [[menu itemArray] count] == 0) {
        return YES;
    }
    
    // Check if this is the "GTK Application" placeholder menu
    NSArray *items = [menu itemArray];
    if ([items count] == 1) {
        NSMenuItem *firstItem = [items objectAtIndex:0];
        if ([[firstItem title] isEqualToString:@"GTK Application"]) {
            return YES;
        }
    }
    
    return NO;
}

- (NSMenu *)createFileMenuWithClose:(unsigned long)windowId
{
#if ENABLE_FALLBACK_MENUS
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    
    // Create Close menu item with Cmd+W
    NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close" action:@selector(closeWindow:) keyEquivalent:@"w"];
    [closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
    [closeItem setTarget:self];
    [closeItem setRepresentedObject:[NSNumber numberWithUnsignedLong:windowId]];
    [fileMenu addItem:closeItem];
    
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [fileMenuItem setSubmenu:fileMenu];
    [mainMenu addItem:fileMenuItem];
    
    return mainMenu;
#else
    (void)windowId;  // Suppress unused parameter warning
    return nil;
#endif
}

// Schedule a delayed fallback menu to avoid showing fallback immediately when an app is starting up
- (void)scheduleFallbackMenuForWindow:(unsigned long)windowId delay:(NSTimeInterval)delay
{
#if ENABLE_FALLBACK_MENUS
    NSNumber *key = [NSNumber numberWithUnsignedLong:windowId];
    if ([self.fallbackTimers objectForKey:key]) {
        // Already scheduled
        return;
    }

    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(fallbackTimerFired:) userInfo:key repeats:NO];
    [self.fallbackTimers setObject:timer forKey:key];
#else
    (void)windowId;  // Suppress unused parameter warning
    (void)delay;     // Suppress unused parameter warning
#endif
}

- (void)cancelScheduledFallbackForWindow:(unsigned long)windowId
{
#if ENABLE_FALLBACK_MENUS
    NSNumber *key = [NSNumber numberWithUnsignedLong:windowId];
    NSTimer *timer = [self.fallbackTimers objectForKey:key];
    if (timer) {
        [timer invalidate];
        [self.fallbackTimers removeObjectForKey:key];
    }
#else
    (void)windowId;  // Suppress unused parameter warning
#endif
}

- (void)fallbackTimerFired:(NSTimer *)timer
{
#if ENABLE_FALLBACK_MENUS
    NSNumber *windowNum = (NSNumber *)[timer userInfo];
    [self.fallbackTimers removeObjectForKey:windowNum];

    unsigned long windowId = [windowNum unsignedLongValue];

    // If the user switched away, do nothing
    if (self.currentWindowId != windowId) {
        return;
    }

    // If a real menu appeared in the meantime, cancel fallback
    if ([self.protocolManager hasMenuForWindow:windowId]) {
        return;
    }

    // Prevent fallback for desktop windows
    if ([MenuUtils isDesktopWindow:windowId]) {
        NSLog(@"AppMenuWidget: Suppressing fallback menu for desktop window %lu (delayed)", windowId);
        return;
    }

    NSLog(@"AppMenuWidget: No menu received for window %lu after delay, providing fallback menu", windowId);
    NSMenu *fallbackMenu = [self createFileMenuWithClose:windowId];
    [self loadMenu:fallbackMenu forWindow:windowId];
#else
    (void)timer;  // Suppress unused parameter warning
#endif
}

- (void)closeWindow:(NSMenuItem *)sender
{
#if ENABLE_FALLBACK_MENUS
    NSNumber *windowIdNumber = [sender representedObject];
    if (!windowIdNumber) {
        NSLog(@"AppMenuWidget: closeWindow called but no window ID in representedObject");
        return;
    }
    
    unsigned long windowId = [windowIdNumber unsignedLongValue];
    NSLog(@"AppMenuWidget: Closing window %lu", windowId);
    
    // Send Alt+F4 to close the window
    [self sendAltF4ToWindow:windowId];
#else
    (void)sender;  // Suppress unused parameter warning
#endif
}

- (void)sendAltF4ToWindow:(unsigned long)windowId
{
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"AppMenuWidget: Failed to open X11 display for window close");
        return;
    }
    
    Window window = (Window)windowId;
    Window root = DefaultRootWindow(display);
    
    // Send Alt+F4 key event to the window
    // We use the root window to ensure the window manager can intercept it
    XEvent keyEvent;
    memset(&keyEvent, 0, sizeof(keyEvent));
    
    // Make sure the target window has focus first
    XSetInputFocus(display, window, RevertToParent, CurrentTime);
    XFlush(display);
    
    // Press Alt+F4
    keyEvent.xkey.type = KeyPress;
    keyEvent.xkey.display = display;
    keyEvent.xkey.window = window;
    keyEvent.xkey.root = root;
    keyEvent.xkey.subwindow = None;
    keyEvent.xkey.time = CurrentTime;
    keyEvent.xkey.x = 1;
    keyEvent.xkey.y = 1;
    keyEvent.xkey.x_root = 1;
    keyEvent.xkey.y_root = 1;
    keyEvent.xkey.state = Mod1Mask; // Alt modifier
    keyEvent.xkey.keycode = XKeysymToKeycode(display, XK_F4);
    keyEvent.xkey.same_screen = True;
    
    // Send to both the window and root (for window manager)
    XSendEvent(display, window, True, KeyPressMask, &keyEvent);
    XSendEvent(display, root, False, KeyPressMask, &keyEvent);
    
    // Release Alt+F4
    keyEvent.xkey.type = KeyRelease;
    XSendEvent(display, window, True, KeyReleaseMask, &keyEvent);
    XSendEvent(display, root, False, KeyReleaseMask, &keyEvent);
    
    NSLog(@"AppMenuWidget: Sent Alt+F4 key event to window %lu", windowId);
    
    XFlush(display);
    XCloseDisplay(display);
}

- (void)preWarmCacheForApplication:(NSString *)applicationName
{
    NSLog(@"AppMenuWidget: Pre-warming cache for complex application: %@", applicationName);
    
    // Find all windows belonging to this application that aren't cached yet
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"AppMenuWidget: Cannot open X11 display for cache pre-warming");
        return;
    }
    
    Window root = DefaultRootWindow(display);
    Atom clientListAtom = XInternAtom(display, "_NET_CLIENT_LIST", False);
    
    Atom actualType;
    int actualFormat;
    unsigned long numWindows, bytesAfter;
    Window *windows = NULL;
    
    SAFE_X11_CALL(display, {
        if (XGetWindowProperty(display, root, clientListAtom, 0, 1024, False, XA_WINDOW,
                              &actualType, &actualFormat, &numWindows, &bytesAfter,
                              (unsigned char**)&windows) == Success && windows) {
            
            NSUInteger warmedCount = 0;
            MenuCacheManager *cacheManager = [MenuCacheManager sharedManager];
            
            for (unsigned long i = 0; i < numWindows && warmedCount < 3; i++) {
            Window window = windows[i];
            
            // Skip current window (already loaded)
            if (window == self.currentWindowId) {
                continue;
            }
            
            // Check if this window belongs to the same application
            NSString *windowAppName = [MenuUtils getApplicationNameForWindow:(unsigned long)window];
            if (!windowAppName || ![windowAppName isEqualToString:applicationName]) {
                continue;
            }
            
            // Check if we already have this window cached
            if ([cacheManager getCachedMenuForWindow:(unsigned long)window]) {
                continue;
            }
            
            // Check if protocol manager has a menu for this window
            if ([self.protocolManager hasMenuForWindow:(unsigned long)window]) {
                NSLog(@"AppMenuWidget: Pre-warming cache for window %lu (%@)", 
                      (unsigned long)window, applicationName);
                
                // Load menu in background (this will cache it)
                NSMenu *menu = [self.protocolManager getMenuForWindow:(unsigned long)window];
                if (menu) {
                    warmedCount++;
                    NSLog(@"AppMenuWidget: Successfully pre-warmed cache for window %lu", 
                          (unsigned long)window);
                } else {
                    NSLog(@"AppMenuWidget: Failed to pre-warm cache for window %lu", 
                          (unsigned long)window);
                }
            }
        }
        
        XFree(windows);
        NSLog(@"AppMenuWidget: Pre-warmed cache for %lu windows of application %@", 
              (unsigned long)warmedCount, applicationName);
        }
    }, {
        // Cleanup on error
        if (windows) {
            XFree(windows);
            windows = NULL;
        }
        NSLog(@"AppMenuWidget: Failed to get client list for cache pre-warming due to X11 error");
    });
    
    XCloseDisplay(display);
}

- (void)loadMenu:(NSMenu *)menu forWindow:(unsigned long)windowId
{
    if (!menu) {
        NSLog(@"AppMenuWidget: Cannot load nil menu for window %lu", windowId);
        return;
    }
    
    // Cancel any scheduled fallback for this window since we're loading a real menu
    [self cancelScheduledFallbackForWindow:windowId];

    NSLog(@"AppMenuWidget: Loading menu for window %lu", windowId);
    
    // Clear the waiting flag - we have a new menu
    self.isWaitingForMenu = NO;
    self.currentMenu = menu;
    
    NSLog(@"AppMenuWidget: ===== MENU LOADED, SETTING UP VIEW =====");
    NSLog(@"AppMenuWidget: Menu has %lu top-level items", (unsigned long)[[menu itemArray] count]);
    
    // Log each top-level menu item and whether it has submenus
    NSArray *items = [menu itemArray];
    for (NSUInteger i = 0; i < [items count]; i++) {
        NSMenuItem *item = [items objectAtIndex:i];
        NSLog(@"AppMenuWidget: Top-level item %lu: '%@' (has submenu: %@, submenu items: %lu)", 
              i, [item title], [item hasSubmenu] ? @"YES" : @"NO",
              [item hasSubmenu] ? (unsigned long)[[[item submenu] itemArray] count] : 0);
    }
    
    @try {
        [self setupMenuViewWithMenu:menu];
        NSLog(@"AppMenuWidget: setupMenuViewWithMenu completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"AppMenuWidget: EXCEPTION in setupMenuViewWithMenu: %@", exception);
        NSLog(@"AppMenuWidget: Exception details - name: %@, reason: %@", [exception name], [exception reason]);
    }
    
    // Re-register shortcuts for this menu since we cleared them in clearMenu
    [self reregisterShortcutsForMenu:menu];
    
    NSLog(@"AppMenuWidget: Successfully loaded fallback menu with %lu items", (unsigned long)[[menu itemArray] count]);
    
    // For fallback menus, also register Alt+W shortcut through X11ShortcutManager
    [self registerAltWShortcutForWindow:windowId];
}

- (void)registerAltWShortcutForWindow:(unsigned long)windowId
{
    // Create a temporary menu item for Alt+W registration
    NSMenuItem *altWMenuItem = [[NSMenuItem alloc] initWithTitle:@"Close" action:@selector(closeActiveWindow:) keyEquivalent:@"w"];
    [altWMenuItem setKeyEquivalentModifierMask:NSAlternateKeyMask];
    [altWMenuItem setTarget:self];
    // Don't set representedObject - we'll determine the active window dynamically
    
    // Register this shortcut with the X11ShortcutManager
    [[X11ShortcutManager sharedManager] registerDirectShortcutForMenuItem:altWMenuItem
                                                                    target:self
                                                                    action:@selector(closeActiveWindow:)];
    
}

- (void)closeActiveWindow:(NSMenuItem *)sender
{
    // Get the currently active window using X11
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"AppMenuWidget: Cannot open X11 display for active window detection");
        return;
    }
    
    Window root = DefaultRootWindow(display);
    Window activeWindow = 0;
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *prop = NULL;
    
    // Get _NET_ACTIVE_WINDOW property
    Atom activeWindowAtom = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
    SAFE_X11_CALL(display, {
        if (XGetWindowProperty(display, root, activeWindowAtom,
                              0, 1, False, AnyPropertyType,
                              &actualType, &actualFormat, &nitems, &bytesAfter,
                              &prop) == Success && prop) {
            activeWindow = *(Window*)prop;
            XFree(prop);
        }
    }, {
        // Cleanup on error
        if (prop) {
            XFree(prop);
            prop = NULL;
        }
        NSLog(@"AppMenuWidget: Failed to get active window for close operation due to X11 error");
    });
    
    XCloseDisplay(display);
    
    if (activeWindow == 0) {
        NSLog(@"AppMenuWidget: Could not determine active window for Alt+W close");
        return;
    }
    
    NSLog(@"AppMenuWidget: Alt+W triggered - closing currently active window %lu", activeWindow);
    
    // Send Alt+F4 to close the currently active window
    [self sendAltF4ToWindow:activeWindow];
}

- (void)reregisterShortcutsForMenu:(NSMenu *)menu
{
    // This method is now handled by the protocol managers when they return cached menus
    // GTKMenuImporter and DBusMenuImporter will re-register shortcuts automatically
    NSLog(@"AppMenuWidget: Shortcut re-registration handled by protocol managers");
}

- (void)reregisterGTKShortcut:(NSMenuItem *)item
{
    // For GTK shortcuts, we need to get the stored action data and re-register
    // We would need access to GTKActionHandler's static data, but for now
    // let's register it as a basic shortcut that will trigger the existing action
    NSLog(@"AppMenuWidget: Re-registering GTK shortcut for item: %@", [item title]);
    
    [[X11ShortcutManager sharedManager] registerShortcutForMenuItem:item
                                                        serviceName:nil
                                                         objectPath:nil 
                                                     dbusConnection:nil];
}

- (void)reregisterDBusShortcut:(NSMenuItem *)item
{
    // For DBus shortcuts, similar approach
    NSLog(@"AppMenuWidget: Re-registering DBus shortcut for item: %@", [item title]);
    
    [[X11ShortcutManager sharedManager] registerShortcutForMenuItem:item
                                                        serviceName:nil
                                                         objectPath:nil
                                                     dbusConnection:nil];
}

#pragma mark - Window Validity Checks

+ (BOOL)isWindowStillValid:(Window)windowId
{
    if (windowId == 0) {
        return NO;
    }
    
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"AppMenuWidget: Cannot open X11 display for window validation");
        return NO;
    }
    
    BOOL isValid = NO;
    
    // Try to get window attributes to check if window still exists
    SAFE_X11_CALL(display, {
        XWindowAttributes attrs;
        if (XGetWindowAttributes(display, windowId, &attrs) != BadWindow) {
            isValid = YES;
        }
    }, {
        // Error occurred - window is invalid
        isValid = NO;
    });
    
    XCloseDisplay(display);
    return isValid;
}

+ (BOOL)safelyCheckWindow:(Window)windowId withDisplay:(Display *)display
{
    if (windowId == 0 || !display) {
        return NO;
    }
    
    BOOL isValid = NO;
    
    SAFE_X11_CALL(display, {
        XWindowAttributes attrs;
        if (XGetWindowAttributes(display, windowId, &attrs) != BadWindow) {
            isValid = YES;
        }
    }, {
        // Error occurred - window is invalid
        isValid = NO;
    });
    
    return isValid;
}

- (void)handleWindowDisappeared:(Window)windowId
{
    NSLog(@"AppMenuWidget: Window %lu disappeared, performing emergency cleanup", windowId);
    
    // If this is our current window, clear everything immediately
    if (self.currentWindowId == windowId) {
        NSLog(@"AppMenuWidget: Current window disappeared, clearing all state");
        
        // Clear all state immediately
        self.currentWindowId = 0;
        self.currentApplicationName = nil;
        self.currentMenu = nil;
        
        // Force cleanup of menu views with exception handling
        @try {
            if (self.menuView) {
                if ([self.menuView respondsToSelector:@selector(setMenu:)]) {
                    [self.menuView setMenu:nil];
                }
                self.menuView = nil;
            }
            
            [self setNeedsDisplay:YES];
        }
        @catch (NSException *exception) {
            NSLog(@"AppMenuWidget: Exception during emergency cleanup: %@", exception);
            // Force clear all references
            self.menuView = nil;
        }
    }
}

@end
