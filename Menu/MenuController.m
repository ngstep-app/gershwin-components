/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MenuController.h"
#import "MenuBarView.h"
#import "AppMenuWidget.h"
#import "MenuProtocolManager.h"
#import "DBusMenuImporter.h"
#import "GTKMenuImporter.h"
#import "GNUStepMenuImporter.h"
#import "RoundedCornersView.h"
#import "X11ShortcutManager.h"
#import "ActionSearch.h"
#import "MenuUtils.h"
#import "StatusItemManager.h"
#import "StatusItemsView.h"
#import "GNUstepGUI/GSTheme.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#import <sys/select.h>
#import <errno.h>
#import <dispatch/dispatch.h>

@interface TimeMenuView : NSMenuView
@end

@implementation TimeMenuView

- (void)drawRect:(NSRect)dirtyRect
{
    // Clear with transparent background to let the MenuBarView background show through
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);
    
    // Draw menu items with transparent background
    [super drawRect:dirtyRect];
}

- (BOOL)isOpaque
{
    return NO;
}

@end

@implementation MenuController

// DBus file descriptor monitoring using NSFileHandle
- (void)dbusFileDescriptorReady:(NSNotification *)notification {
    // Always handle DBus traffic on the main thread to avoid races with UI work
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dbusFileDescriptorReady:notification];
        });
        return;
    }

    NSLog(@"MenuController: DBus file descriptor reported data available");
    
    // Lock the menu window from redrawing during DBus processing to prevent flashing
    [self.menuBar disableFlushWindow];
    
    @try {
        [[MenuProtocolManager sharedManager] processDBusMessages];
    }
    @catch (NSException *exception) {
        NSLog(@"MenuController: Exception processing DBus messages: %@", exception);
    }
    @finally {
        // Re-enable window drawing and flush all pending updates at once
        [self.menuBar enableFlushWindow];
        [self.menuBar flushWindow];
    }

    // Re-arm the watcher so we continue receiving notifications
    // Only re-arm if the file handle is still valid
    if (self.dbusFileHandle) {
        @try {
            [self.dbusFileHandle waitForDataInBackgroundAndNotify];
        }
        @catch (NSException *exception) {
            NSLog(@"MenuController: Exception re-arming DBus file handle: %@", exception);
            self.dbusFileHandle = nil;
        }
    }
}

- (id)init
{
    NSLog(@"MenuController: Initializing controller...");
    self = [super init];
    if (self) {
        // Initialize trailing-edge debounce properties to prevent infinite loops
        self.lastActiveWindowScanTime = 0;
        NSLog(@"MenuController: Controller initialized successfully");
    }
    return self;
}

- (NSColor *)backgroundColor
{
    NSColor *color = [[GSTheme theme] menuItemBackgroundColor];
    return color;
}

- (NSColor *)transparentColor
{
    NSColor *color = [NSColor colorWithCalibratedRed:0.992 green:0.992 blue:0.992 alpha:0.0];
    return color;
}

- (void)createPersistentStrutWindow
{
    NSLog(@"MenuController: Creating persistent X11 strut window...");
    
    const CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight];
    
    // Open X11 display connection that will persist for the application lifetime
    self.strutDisplay = XOpenDisplay(NULL);
    if (!self.strutDisplay) {
        NSLog(@"MenuController: Cannot open X11 display for strut window");
        return;
    }
    
    int screen = DefaultScreen(self.strutDisplay);
    Window root = RootWindow(self.strutDisplay, screen);
    unsigned int width = (unsigned int)self.screenSize.width;
    unsigned int height = (unsigned int)menuBarHeight;
    
    // Create invisible strut window that reserves space but doesn't interfere with our menu
    XSetWindowAttributes attrs;
    attrs.override_redirect = False;
    attrs.background_pixel = BlackPixel(self.strutDisplay, screen);
    attrs.border_pixel = BlackPixel(self.strutDisplay, screen);
    
    // Create a 1x1 pixel window at the top-left corner to avoid visual interference
    self.strutWindow = XCreateWindow(self.strutDisplay, root, 0, 0, 1, 1, 0, 
                                   CopyFromParent, InputOutput, CopyFromParent, 
                                   CWOverrideRedirect | CWBackPixel | CWBorderPixel, &attrs);
    
    if (self.strutWindow == None) {
        NSLog(@"MenuController: Failed to create X11 strut window");
        XCloseDisplay(self.strutDisplay);
        self.strutDisplay = NULL;
        return;
    }
    
    // Set window type to dock
    Atom windowTypeAtom = XInternAtom(self.strutDisplay, "_NET_WM_WINDOW_TYPE", False);
    Atom dockAtom = XInternAtom(self.strutDisplay, "_NET_WM_WINDOW_TYPE_DOCK", False);
    XChangeProperty(self.strutDisplay, self.strutWindow, windowTypeAtom, XA_ATOM, 32, 
                   PropModeReplace, (unsigned char *)&dockAtom, 1);
    
    // Set WM_CLASS to "StrutPanel" to distinguish from our actual menu
    XClassHint classHint;
    classHint.res_name = "StrutPanel";
    classHint.res_class = "StrutPanel";
    XSetClassHint(self.strutDisplay, self.strutWindow, &classHint);
    
    // Set WM_NAME to "MenuBarStrut"
    XStoreName(self.strutDisplay, self.strutWindow, "MenuBarStrut");
    
    // Set struts - this reserves the space for the full menu bar height
    Atom strutAtom = XInternAtom(self.strutDisplay, "_NET_WM_STRUT", False);
    Atom strutPartialAtom = XInternAtom(self.strutDisplay, "_NET_WM_STRUT_PARTIAL", False);
    unsigned long strut[4] = {0, 0, height, 0}; // left, right, top, bottom
    unsigned long strutPartial[12] = {0, 0, height, 0, 0, 0, 0, 0, 0, width - 1, 0, width - 1};
    
    XChangeProperty(self.strutDisplay, self.strutWindow, strutAtom, XA_CARDINAL, 32, 
                   PropModeReplace, (unsigned char *)strut, 4);
    XChangeProperty(self.strutDisplay, self.strutWindow, strutPartialAtom, XA_CARDINAL, 32, 
                   PropModeReplace, (unsigned char *)strutPartial, 12);
    
    // Set window state to sticky but NOT above (we want our menu to be above it)
    Atom stateAtom = XInternAtom(self.strutDisplay, "_NET_WM_STATE", False);
    Atom stickyAtom = XInternAtom(self.strutDisplay, "_NET_WM_STATE_STICKY", False);
    XChangeProperty(self.strutDisplay, self.strutWindow, stateAtom, XA_ATOM, 32, 
                   PropModeReplace, (unsigned char *)&stickyAtom, 1);
    
    // Map the window to make the struts active
    XMapWindow(self.strutDisplay, self.strutWindow);
    XSync(self.strutDisplay, False);
    
    NSLog(@"MenuController: Created persistent X11 strut window (XID: %lu) - invisible 1x1 window with full-width struts", 
          (unsigned long)self.strutWindow);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSLog(@"MenuController: Application did finish launching");
    
    [self.menuBar orderFront:self];
    [self setupWindowMonitoring];
    
    NSLog(@"MenuController: Application setup complete");
    
    // Register D-Bus service immediately - run loop is active
    NSLog(@"MenuController: Registering D-Bus service now...");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self registerDBusServiceWhenReady];
    });
}

- (void)registerDBusServiceWhenReady
{
    NSLog(@"MenuController: ===== REGISTERING D-BUS SERVICE NOW =====");
    
    // Get the canonical handler
    id<MenuProtocolHandler> canonicalHandler = [[MenuProtocolManager sharedManager] handlerForType:MenuProtocolTypeCanonical];
    
    // Register the D-Bus service name immediately - this makes us visible to other applications
    // No need to process messages first - the file descriptor monitoring handles it
    NSLog(@"MenuController: Registering D-Bus service name (making Menu visible to clients)...");
    if (canonicalHandler && [canonicalHandler respondsToSelector:@selector(registerService)]) {
        if ([(id)canonicalHandler registerService]) {
            NSLog(@"MenuController: ===== Successfully registered D-Bus service - Menu is now VISIBLE =====");
            
            // DO NOT scan for menus here - it causes 15 seconds of blocking!
            // Menus will be discovered on-demand when windows become active
            NSLog(@"MenuController: Skipping menu scan at startup - menus discovered on-demand");
        } else {
            NSLog(@"MenuController: Warning - failed to register D-Bus service");
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    NSLog(@"MenuController: Application will terminate");
    
    // Unload status items first
    if (self.statusItemManager) {
        NSLog(@"MenuController: Unloading status items...");
        [self.statusItemManager unloadAllStatusItems];
        self.statusItemManager = nil;
    }
    
    // Clean up global shortcuts
    NSLog(@"MenuController: Cleaning up global shortcuts...");
    [[X11ShortcutManager sharedManager] cleanup];
    
    // Signal the X11 monitoring thread to stop
    self.shouldStopMonitoring = YES;
    
    // Wait for the thread to finish (with timeout to avoid hanging)
    if (self.x11Thread && ![self.x11Thread isFinished]) {
        // Give the thread a chance to exit gracefully
        [NSThread sleepForTimeInterval:0.1];
        
        if (![self.x11Thread isFinished]) {
            NSLog(@"MenuController: X11 thread did not exit gracefully");
        }
    }
    
    self.x11Thread = nil;
    
    // Clean up persistent strut window
    if (self.strutWindow != None && self.strutDisplay) {
        XDestroyWindow(self.strutDisplay, self.strutWindow);
        self.strutWindow = None;
    }
    
    // Close strut X11 display
    if (self.strutDisplay) {
        XCloseDisplay(self.strutDisplay);
        self.strutDisplay = NULL;
    }
    
    // Close X11 display
    if (self.display) {
        XCloseDisplay(self.display);
        self.display = NULL;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [[MenuProtocolManager sharedManager] cleanup];
    
    self.protocolManager = nil;
    
    self.roundedCornersView = nil;
}

- (void)createMenuBar
{
    NSLog(@"MenuController: ===== CREATING MENU BAR =====");
    const CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight];
    NSLog(@"MenuController: Menu bar height: %.0f", menuBarHeight);
    
    NSRect rect;
    NSColor *color;
    NSFont *menuFont = [NSFont menuBarFontOfSize:0];
    NSMutableDictionary *attributes;
    
    attributes = [NSMutableDictionary new];
    [attributes setObject:menuFont forKey:NSFontAttributeName];
    
    self.screenFrame = [[NSScreen mainScreen] frame];
    self.screenSize = self.screenFrame.size;
    NSLog(@"MenuController: Screen frame: %.0f,%.0f %.0fx%.0f", 
          self.screenFrame.origin.x, self.screenFrame.origin.y, self.screenSize.width, self.screenSize.height);
    
    color = [self backgroundColor];
    NSLog(@"MenuController: Background color: %@", color);
        
    // Creation of the menuBar at the TOP of the screen (GNUstep coordinates: bottom-left origin)
    rect = NSMakeRect(0, self.screenSize.height - menuBarHeight, self.screenSize.width, menuBarHeight);
    NSLog(@"MenuController: Menu bar rect: %.0f,%.0f %.0fx%.0f", 
          rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    
    self.menuBar = [[NSWindow alloc] initWithContentRect:rect
                                          styleMask:NSBorderlessWindowMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    NSLog(@"MenuController: Created NSWindow: %@", self.menuBar);
    
    [self.menuBar setTitle:@"MenuBar"];
    [self.menuBar setBackgroundColor:color];
    [self.menuBar setAlphaValue:1.0];
    [self.menuBar setLevel:NSMainMenuWindowLevel + 1]; // Higher than main menu, but not floating
    [self.menuBar setCanHide:NO];
    [self.menuBar setHidesOnDeactivate:NO];
    [self.menuBar setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                   NSWindowCollectionBehaviorStationary];
    
    NSLog(@"MenuController: Configured window properties");
    
    // Create and maintain a persistent X11 window for struts
    [self createPersistentStrutWindow];

    // Position the window one menu height above the screen for animation effect
    [self.menuBar setFrameTopLeftPoint:NSMakePoint(0, self.screenSize.height + menuBarHeight)];
    NSLog(@"MenuController: Window positioned above screen for animation slide-in");
    
    // Create the main menu bar view that draws the background
    self.menuBarView = [[MenuBarView alloc] initWithFrame:NSMakeRect(0, 0, self.screenSize.width, menuBarHeight)];
    NSLog(@"MenuController: Created MenuBarView: %@", self.menuBarView);
    
    // Create app menu widget for displaying menus - leave space for status items on right
    // Status items are at the far right: time (60px) + systemmonitor (140px) + spacing (10px) = 210px
    CGFloat statusItemsWidth = 210; // actual width of status items
    CGFloat menuWidgetWidth = self.screenSize.width - statusItemsWidth;
    self.appMenuWidget = [[AppMenuWidget alloc] initWithFrame:NSMakeRect(0, 0, menuWidgetWidth, menuBarHeight)];
    NSLog(@"MenuController: AppMenuWidget created successfully");
    
    NSLog(@"MenuController: Setting up protocol manager connection");
    // Set up the AppMenuWidget with the protocol manager
    [self.appMenuWidget setProtocolManager:[MenuProtocolManager sharedManager]];
    NSLog(@"MenuController: Protocol manager connected to AppMenuWidget");
    
    // Update all protocol handlers with the AppMenuWidget reference
    [[MenuProtocolManager sharedManager] updateAllHandlersWithAppMenuWidget:self.appMenuWidget];
    NSLog(@"MenuController: All protocol handlers notified of AppMenuWidget");
    
    NSLog(@"MenuController: Checking appMenuWidget before NSLog...");
    if (self.appMenuWidget) {
        NSLog(@"MenuController: appMenuWidget is valid");
    } else {
        NSLog(@"MenuController: appMenuWidget is nil!");
    }
    
    // NSLog(@"MenuController: Created AppMenuWidget with width %.0f at address %p", menuWidgetWidth, self.appMenuWidget);
    NSLog(@"MenuController: Skipping potentially problematic NSLog");
    
    // Create status item manager (but don't load yet)
    NSLog(@"MenuController: Creating StatusItemManager");
    self.statusItemManager = [[StatusItemManager alloc] initWithContainerView:[self.menuBar contentView]
                                                                   screenWidth:self.screenSize.width
                                                                 menuBarHeight:menuBarHeight];
    
    // Create status items view at right edge with proper spacing
    StatusItemsView *statusItemsView = [[StatusItemsView alloc] 
        initWithFrame:NSMakeRect(self.screenSize.width - statusItemsWidth, 0, statusItemsWidth, menuBarHeight)
            statusMenu:self.statusItemManager.statusMenu];
    
    // Remove the Action Search icon from the menu bar (search remains accessible via Command menu)
    
    // probono: Create rounded corners view for black top corners like in old/src/mainwindow.cpp
    // Position it at the top of the menu bar, with height enough for the corner radius effect
    CGFloat cornerHeight = 10.0; // 2 * corner radius (5px)
    self.roundedCornersView = [[RoundedCornersView alloc] initWithFrame:NSMakeRect(0, menuBarHeight - cornerHeight, self.screenSize.width, cornerHeight)];
    
    // Add MenuBarView as the background (spans full width)
    [[self.menuBar contentView] addSubview:self.menuBarView];
    
    // Add AppMenuWidget and StatusItemsView as children of MenuBarView (on top of the background)
    [self.menuBarView addSubview:self.appMenuWidget];
    
    // Load status items and add the display view as a child of MenuBarView
    [self.statusItemManager loadStatusItems];
    NSLog(@"MenuController: StatusItemManager items loaded");
    [self.menuBarView addSubview:statusItemsView];
    NSLog(@"MenuController: Added StatusItemsView as child of MenuBarView");
    
    // Finally add rounded corners on top of everything
    [[self.menuBar contentView] addSubview:self.roundedCornersView];

    
    // Show the window and slide it in from above with animation
    [self.menuBar makeKeyAndOrderFront:self];
    [self.menuBar orderFront:self];

    // Register global Cmd-Space shortcut to toggle the Action Search panel (if available)
    // NOTE: What we call "Cmd" here is actually the "Alt" key technically but we refer to it as "Cmd" in the UI
    NSString *cmdSpaceShortcut = @"alt+space";
    X11ShortcutManager *mgr = [X11ShortcutManager sharedManager];
    if (mgr && ![mgr isShortcutAlreadyTaken:cmdSpaceShortcut]) {
        NSMenuItem *cmdSpaceItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Action Search"
                                                               action:@selector(toggleSearch:)
                                                        keyEquivalent:@" "];
        [cmdSpaceItem setKeyEquivalentModifierMask:NSCommandKeyMask];
        // Register directly to call the ActionSearchController without DBus
        BOOL regOK = [mgr registerDirectShortcutForMenuItem:cmdSpaceItem
                                                     target:[ActionSearchController sharedController]
                                                     action:@selector(toggleSearch:)];
        if (regOK) {
            NSLog(@"MenuController: Registered global shortcut Cmd-Space for Action Search");
        } else {
            NSLog(@"MenuController: Failed to register Cmd-Space as global shortcut");
            // Notify user with alert so failure is visible
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:NSLocalizedString(@"Cannot register global shortcut", @"Alert title for shortcut failure")];
            [alert setInformativeText:NSLocalizedString(@"Menu.app failed to register the Cmd-Space global shortcut. Please check for conflicts or permissions.", @"Alert text for shortcut failure")];
            [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
            [alert setAlertStyle:NSWarningAlertStyle];
            // Run non-modally to avoid blocking the app startup
            [alert beginSheetModalForWindow:self.menuBar completionHandler:nil];
        }
    } else {
        if (!mgr) {
            NSLog(@"MenuController: Warning - cannot register Cmd-Space because X11ShortcutManager is unavailable");
        } else {
            NSLog(@"MenuController: Cmd-Space already taken - not registering global shortcut");
        }
    }

    // Animate menu sliding in immediately - no delay
    dispatch_async(dispatch_get_main_queue(), ^{
        [self animateMenuSlideIn];
    });
    NSLog(@"MenuController: Window shown, menu will slide in immediately");
}

- (void)setupMenuBar
{
    NSLog(@"MenuController: Setting up menu bar using createMenuBar method");
    [self createMenuBar];
    NSLog(@"MenuController: Menu bar setup complete at %.0f,%.0f %.0fx%.0f", self.screenFrame.origin.x, self.screenFrame.origin.y, self.screenSize.width, [[GSTheme theme] menuBarHeight]);
    NSLog(@"MenuController: Setting up X11 window monitoring");
    [self setupWindowMonitoring];
    NSLog(@"MenuController: Initializing protocol scanning");
    [self initializeProtocols];
}

- (void)updateActiveWindow
{
    // Get the currently active window and update app menu
    if (self.appMenuWidget) {
        [self.appMenuWidget updateForActiveWindow];
    } else {
        NSLog(@"MenuController: self.appMenuWidget is nil");
    }
}

- (void)initializeProtocols
{
    NSLog(@"MenuController: Initializing all menu protocols...");
    
    NSLog(@"MenuController: About to call initializeAllProtocols...");
    if (![[MenuProtocolManager sharedManager] initializeAllProtocols]) {
        NSLog(@"MenuController: Failed to initialize menu protocols - continuing anyway");
        self.dbusFileDescriptor = -1;
    } else {
        NSLog(@"MenuController: Menu protocols initialized successfully");
        
        // Get the DBus file descriptor for X11 event loop integration
        self.dbusFileDescriptor = [[MenuProtocolManager sharedManager] getDBusFileDescriptor];
        if (self.dbusFileDescriptor >= 0) {
            NSLog(@"MenuController: Got DBus file descriptor %d for event loop integration", self.dbusFileDescriptor);
            
            // Create NSFileHandle for DBus file descriptor monitoring
            self.dbusFileHandle = [[NSFileHandle alloc] initWithFileDescriptor:self.dbusFileDescriptor closeOnDealloc:NO];
            if (self.dbusFileHandle) {
                NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
                [center addObserver:self
                           selector:@selector(dbusFileDescriptorReady:)
                               name:NSFileHandleDataAvailableNotification
                             object:self.dbusFileHandle];
                [self.dbusFileHandle waitForDataInBackgroundAndNotify];
                NSLog(@"MenuController: DBus file descriptor integrated into notification system");
            } else {
                NSLog(@"MenuController: Failed to create NSFileHandle for DBus file descriptor");
            }
            
            NSLog(@"MenuController: Event loop integration setup complete");
        } else {
            NSLog(@"MenuController: Failed to get DBus file descriptor");
        }
    }
    
    // Set the app menu widget reference
    if (self.appMenuWidget) {
        [[MenuProtocolManager sharedManager] setAppMenuWidget:self.appMenuWidget];
        NSLog(@"MenuController: Set up connection between MenuProtocolManager and AppMenuWidget");
    }
    
    // D-Bus will continue initializing via the file descriptor monitoring on the main thread
    // The run loop will handle D-Bus messages asynchronously without blocking the UI
    // This ensures thread safety - D-Bus is NOT thread-safe and must run on main thread only
    NSLog(@"MenuController: D-Bus initialization will continue via main thread run loop");
    NSLog(@"MenuController: File descriptor monitoring will handle D-Bus messages asynchronously");
}

- (void)createProtocolManager
{
    NSLog(@"MenuController: Creating MenuProtocolManager...");
    self.protocolManager = [MenuProtocolManager sharedManager];
    
    // Register both Canonical and GTK protocol handlers
    GNUStepMenuImporter *gnustepHandler = [[GNUStepMenuImporter alloc] init];
    DBusMenuImporter *canonicalHandler = [[DBusMenuImporter alloc] init];
    GTKMenuImporter *gtkHandler = [[GTKMenuImporter alloc] init];
    
    [self.protocolManager registerProtocolHandler:gnustepHandler forType:MenuProtocolTypeGNUstep];
    [self.protocolManager registerProtocolHandler:canonicalHandler forType:MenuProtocolTypeCanonical];
    [self.protocolManager registerProtocolHandler:gtkHandler forType:MenuProtocolTypeGTK];
    
    NSLog(@"MenuController: Registered GNUstep, Canonical, and GTK protocol handlers");
    NSLog(@"MenuController: createProtocolManager COMPLETED");
}

- (void)setupWindowMonitoring
{
    // Prevent setting up monitoring multiple times
    if (self.x11Thread && ![self.x11Thread isFinished]) {
        NSLog(@"MenuController: X11 monitoring already set up, skipping");
        return;
    }
    
    NSLog(@"MenuController: Setting up X11 _NET_ACTIVE_WINDOW monitoring");
    
    // Initialize monitoring flag
    self.shouldStopMonitoring = NO;
    
    // Open X11 display connection
    self.display = XOpenDisplay(NULL);
    if (!self.display) {
        NSLog(@"MenuController: Cannot open X11 display for window monitoring");
        return;
    }
    
    self.rootWindow = DefaultRootWindow(self.display);
    self.netActiveWindowAtom = XInternAtom(self.display, "_NET_ACTIVE_WINDOW", False);
    
    // Select PropertyNotify events on the root window to detect active window changes
    XSelectInput(self.display, self.rootWindow, PropertyChangeMask);
    
    NSLog(@"MenuController: X11 display opened, monitoring _NET_ACTIVE_WINDOW property changes");
    
    // Start X11 event loop in a separate NSThread
    self.x11Thread = [[NSThread alloc] initWithTarget:self
                                         selector:@selector(x11ActiveWindowMonitor)
                                           object:nil];
    [self.x11Thread setName:@"X11ActiveWindowMonitor"];
    [self.x11Thread start];
    
    NSLog(@"MenuController: X11 monitoring thread started successfully");
    
    // Perform initial active window update
    [self updateActiveWindow];
    
    NSLog(@"MenuController: Window monitoring setup complete");
}

- (void)announceGlobalMenuSupport
{
    NSLog(@"MenuController: Announcing global menu support via X11 properties");
    
    // Set X11 root window properties to announce that we support global menus
    // This is essential for applications to know they should export their menus
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"MenuController: Cannot open X11 display to announce global menu support");
        return;
    }
    
    Window root = DefaultRootWindow(display);
    
    // Set _NET_SUPPORTING_WM property to identify ourselves as the window manager
    // that supports global menus (even though we're not actually a WM)
    Atom supportingWmAtom = XInternAtom(display, "_NET_SUPPORTING_WM", False);
    Atom windowAtom = XInternAtom(display, "WINDOW", False);
    
    // Use our menu bar window as the supporting window
    Window menuBarWindow = 0;
    if (self.menuBar) {
        menuBarWindow = (Window)[self.menuBar windowNumber];
    }
    
    if (menuBarWindow) {
        XChangeProperty(display, root, supportingWmAtom, windowAtom, 32,
                       PropModeReplace, (unsigned char*)&menuBarWindow, 1);
        
        NSLog(@"MenuController: Set _NET_SUPPORTING_WM property");
    }
    
    // Set _NET_SUPPORTED property to list supported features
    Atom netSupportedAtom = XInternAtom(display, "_NET_SUPPORTED", False);
    Atom atomAtom = XInternAtom(display, "ATOM", False);
    
    // List of atoms we support for global menu functionality
    Atom supportedAtoms[] = {
        XInternAtom(display, "_NET_WM_WINDOW_TYPE", False),
        XInternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", False),
        XInternAtom(display, "_NET_ACTIVE_WINDOW", False),
        XInternAtom(display, "_KDE_NET_WM_APPMENU_SERVICE_NAME", False),
        XInternAtom(display, "_KDE_NET_WM_APPMENU_OBJECT_PATH", False),
        XInternAtom(display, "_GTK_MENUBAR_OBJECT_PATH", False),
        XInternAtom(display, "_GTK_APPLICATION_OBJECT_PATH", False),
        XInternAtom(display, "_GTK_WINDOW_OBJECT_PATH", False),
        XInternAtom(display, "_GTK_APP_MENU_OBJECT_PATH", False)
    };
    
    XChangeProperty(display, root, netSupportedAtom, atomAtom, 32,
                   PropModeReplace, (unsigned char*)supportedAtoms, 
                   sizeof(supportedAtoms) / sizeof(Atom));
    
    NSLog(@"MenuController: Set _NET_SUPPORTED property with %lu atoms", 
          sizeof(supportedAtoms) / sizeof(Atom));
    
    // Set Unity-specific properties that Chrome looks for
    Atom unityGlobalMenuAtom = XInternAtom(display, "_UNITY_SUPPORTED", False);
    XChangeProperty(display, root, unityGlobalMenuAtom, atomAtom, 32,
                   PropModeReplace, (unsigned char*)supportedAtoms, 1);
    
    NSLog(@"MenuController: Set _UNITY_SUPPORTED property");
    
    XSync(display, False);
    XCloseDisplay(display);
    
    NSLog(@"MenuController: Global menu support announcement complete");
}

- (void)scanForNewMenus
{
    NSLog(@"MenuController: Scanning for new menu services");
    
    [[MenuProtocolManager sharedManager] scanForExistingMenuServices];
    
    // Force an immediate update of the current window to check if it now has a menu
    if (self.appMenuWidget) {
        [self.appMenuWidget updateForActiveWindow];
    }
}

- (void)x11ActiveWindowMonitor
{
    NSLog(@"MenuController: X11 _NET_ACTIVE_WINDOW monitor thread started");
    
    @autoreleasepool {
        // DO NOT scan for menus at startup - it causes 15 seconds of high CPU usage
        // Menus will be discovered on-demand when windows become active
        // This makes startup instant instead of blocking for 15 seconds
        
        // Schedule desktop menu load on main thread (lightweight operation)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadDesktopMenuIfAvailable];
        });
        
        // Get X11 connection file descriptor
        int x11_fd = ConnectionNumber(self.display);
        NSLog(@"MenuController: X11 file descriptor: %d", x11_fd);
        NSLog(@"MenuController: NOTE - DBus is handled separately via main thread file descriptor monitoring");
        NSLog(@"MenuController: NOTE - Menu scanning skipped at startup for instant launch");
        
        while (!self.shouldStopMonitoring) {
            // Process X11 events - simpler approach from working commit
            if (XPending(self.display) > 0) {
                XEvent event;
                XNextEvent(self.display, &event);
                
                // Check if this is a PropertyNotify event for _NET_ACTIVE_WINDOW
                if (event.type == PropertyNotify && 
                    event.xproperty.window == self.rootWindow &&
                    event.xproperty.atom == self.netActiveWindowAtom) {
                    
                    NSLog(@"MenuController: _NET_ACTIVE_WINDOW property changed - active window changed");
                    
                    // Update the app menu widget for the new active window
                    // IMPORTANT: Perform UI updates on main thread to avoid race conditions
                    if (self.appMenuWidget) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.appMenuWidget updateForActiveWindow];
                            
                            // After updating for active window, scan for menus
                            // Applications may register menus after window activation
                            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
                            if ((now - self.lastActiveWindowScanTime) > 3.0) { // Only scan once every 3 seconds max
                                NSLog(@"MenuController: Active window changed, triggering scan to discover new menus");
                                self.lastActiveWindowScanTime = now;
                                [[MenuProtocolManager sharedManager] scanForExistingMenuServices];
                            }
                        });
                    }
                }
            }
            
            // D-Bus is handled completely separately via main thread file descriptor monitoring
            // DO NOT process D-Bus messages here - it causes blocking and high CPU usage
            // The dbusFileDescriptorReady: notification handler on main thread handles all D-Bus traffic
            
            // Always sleep briefly to avoid busy waiting
            // This prevents 100% CPU usage from the monitoring loop
            [NSThread sleepForTimeInterval:0.01];
        }
    }
    
    NSLog(@"MenuController: X11 monitor thread exiting");
}

- (void)createTimeMenu
{
    NSLog(@"MenuController: createTimeMenu - ENTRY");
    
    NSLog(@"MenuController: Creating time menu");
    
    NSLog(@"MenuController: Creating time formatters...");
    // Create formatters
    self.timeFormatter = [[NSDateFormatter alloc] init];
    NSLog(@"MenuController: Created timeFormatter");
    [self.timeFormatter setDateFormat:@"HH:mm"];
    NSLog(@"MenuController: Set time format");
    self.dateFormatter = [[NSDateFormatter alloc] init];
    NSLog(@"MenuController: Created dateFormatter");
    [self.dateFormatter setDateFormat:@"EEEE, MMMM d, yyyy"];
    NSLog(@"MenuController: Set date format");

    NSLog(@"MenuController: Creating menu and items...");
    // Create the menu and items
    self.timeMenu = [[NSMenu alloc] initWithTitle:@""];
    NSLog(@"MenuController: Created timeMenu");
    [self.timeMenu setAutoenablesItems:NO];
    NSLog(@"MenuController: Set autoenablesItems");
    self.timeMenuItem = [[NSMenuItem alloc] initWithTitle:@"00:00" action:nil keyEquivalent:@""];
    NSLog(@"MenuController: Created timeMenuItem");
    /*
    NSMenu *timeSubMenu = [[NSMenu alloc] initWithTitle:@"TimeSubMenu"];
    self.dateMenuItem = [[NSMenuItem alloc] initWithTitle:@"Loading..." action:nil keyEquivalent:@""];
    [self.dateMenuItem setEnabled:NO];
    [timeSubMenu addItem:self.dateMenuItem];
    [self.timeMenuItem setSubmenu:timeSubMenu];
    */
    [self.timeMenu addItem:self.timeMenuItem];
    
    // Create the menu view at the right edge
    CGFloat timeMenuWidth = 60;
    CGFloat timeMenuX = self.screenSize.width - timeMenuWidth - 7;  // Move clock 7px left
    const CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight];
    self.timeMenuView = [[TimeMenuView alloc] initWithFrame:NSMakeRect(timeMenuX, 0, timeMenuWidth, menuBarHeight)];
    [self.timeMenuView setMenu:self.timeMenu];
    [self.timeMenuView setHorizontal:YES];
    [self.timeMenuView setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin | NSViewMinYMargin];

    NSLog(@"MenuController: About to schedule time update timer");
    // Start timer to update time
    self.timeUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                        target:self
                                                      selector:@selector(updateTimeMenu)
                                                      userInfo:nil
                                                       repeats:YES];
    NSLog(@"MenuController: Timer scheduled successfully");
    [self updateTimeMenu];
    NSLog(@"MenuController: Initial time update called");
}

- (void)updateTimeMenu
{
    NSDate *now = [NSDate date];
    NSString *timeString = [self.timeFormatter stringFromDate:now];
    [self.timeMenuItem setTitle:timeString];
    NSString *dateString = [self.dateFormatter stringFromDate:now];
    [self.dateMenuItem setTitle:dateString];
}

- (void)animateMenuSlideIn
{
    const CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight];
    
    // Start animation timer for smooth slide-in from above
    self.slideInStartTime = [NSDate timeIntervalSinceReferenceDate];
    self.slideInStartY = self.screenSize.height + menuBarHeight;
    
    self.slideInAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.016  // ~60fps
                                                                  target:self
                                                                selector:@selector(updateSlideInAnimation)
                                                                userInfo:nil
                                                                 repeats:YES];
    
    NSLog(@"MenuController: Menu slide-in animation started");
}

- (void)updateSlideInAnimation
{
    const CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight];
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - self.slideInStartTime;
    NSTimeInterval duration = 0.3;
    
    if (elapsed >= duration) {
        // Animation complete
        [self.slideInAnimationTimer invalidate];
        self.slideInAnimationTimer = nil;
        
        // Set final position (place menu bar at very top of the screen)
        [self.menuBar setFrameTopLeftPoint:NSMakePoint(0, self.screenSize.height)];
        [self revealAppMenuWidget];
        NSLog(@"MenuController: Menu slide-in animation completed");
    } else {
        // Calculate progress (0.0 to 1.0) using ease-out cubic for smooth deceleration
        CGFloat progress = elapsed / duration;
        progress = 1.0 - ((1.0 - progress) * (1.0 - progress) * (1.0 - progress));  // Ease-out cubic
        
        // Interpolate position from above screen to final position
        CGFloat currentY = self.slideInStartY - (progress * menuBarHeight);
        [self.menuBar setFrameTopLeftPoint:NSMakePoint(0, currentY)];
    }
}

- (void)revealAppMenuWidget
{
    [self.appMenuWidget setHidden:NO];
    [self.appMenuWidget setNeedsDisplay:YES];
    NSLog(@"MenuController: AppMenuWidget revealed");
}

- (void)loadDesktopMenuIfAvailable
{
    NSLog(@"MenuController: Checking for Desktop/Workspace window to load default menu...");
    
    // Get all windows
    NSArray *windows = [MenuUtils getAllWindows];
    
    // Find the desktop window
    unsigned long desktopWindowId = 0;
    for (NSNumber *windowNum in windows) {
        unsigned long windowId = [windowNum unsignedLongValue];
        if ([MenuUtils isDesktopWindow:windowId]) {
            desktopWindowId = windowId;
            NSLog(@"MenuController: Found Desktop/Workspace window: 0x%lx", desktopWindowId);
            break;
        }
    }
    
    if (desktopWindowId == 0) {
        NSLog(@"MenuController: No Desktop/Workspace window found yet - will load when it appears");
        return;
    }
    
    // Check if this desktop window has a menu registered
    if ([[MenuProtocolManager sharedManager] hasMenuForWindow:desktopWindowId]) {
        NSLog(@"MenuController: Desktop/Workspace window has menu - loading it as default");
        // Load the desktop menu in the AppMenuWidget
        if (self.appMenuWidget) {
            [self.appMenuWidget displayMenuForWindow:desktopWindowId];
        }
    } else {
        NSLog(@"MenuController: Desktop/Workspace window found but no menu registered yet");
    }
}

@end
