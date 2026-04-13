/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// RemoteDesktop.m
// Remote Desktop - Network service discovery and remote connection
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "RemoteDesktop.h"
#import "AppearanceMetrics.h"

#pragma mark - RemoteService Implementation

@implementation RemoteService

@synthesize name = _name;
@synthesize hostname = _hostname;
@synthesize port = _port;
@synthesize type = _type;
@synthesize netService = _netService;

- (id)init
{
    self = [super init];
    if (self) {
        _name = nil;
        _hostname = nil;
        _port = 0;
        _type = RemoteServiceTypeUnknown;
        _netService = nil;
    }
    return self;
}

- (void)dealloc
{
    RELEASE(_name);
    RELEASE(_hostname);
    RELEASE(_netService);
    [super dealloc];
}

- (NSString *)typeString
{
    switch (_type) {
        case RemoteServiceTypeVNC:
            return @"VNC";
        case RemoteServiceTypeRDP:
            return @"RDP";
        default:
            return @"Unknown";
    }
}

@end

#pragma mark - RemoteDesktop Implementation

@implementation RemoteDesktop

- (id)init
{
    self = [super init];
    if (self) {
        discoveredServices = [[NSMutableArray alloc] init];
        vncWindows = [[NSMutableArray alloc] init];
        rdpWindows = [[NSMutableArray alloc] init];
        vncBrowser = nil;
        rdpBrowser = nil;
        _cliMode = NO;
    }
    return self;
}

- (void)setCliMode:(BOOL)cliMode
{
    _cliMode = cliMode;
}

- (void)dealloc
{
    [self stopServiceDiscovery];
    
    // Close all connection windows
    for (VNCWindow *vncWindow in vncWindows) {
        [vncWindow disconnectFromVNC];
        [vncWindow close];
    }
    for (RDPWindow *rdpWindow in rdpWindows) {
        [rdpWindow disconnectFromRDP];
        [rdpWindow close];
    }
    
    RELEASE(discoveredServices);
    RELEASE(vncWindows);
    RELEASE(rdpWindows);
    RELEASE(window);
    [super dealloc];
}

#pragma mark - Application Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Create menu (needed even in CLI mode)
    [self createMenu];
    
    // Skip creating browser window in CLI mode
    if (_cliMode) {
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Running in CLI mode, skipping browser window");
        return;
    }
    
    // Create main window
    // Using METRICS_WIN_MIN_WIDTH (500px) * 1.6 for appropriate width per HIG
    NSRect windowFrame = NSMakeRect(100, 100, METRICS_WIN_MIN_WIDTH * 1.6, 400);
    window = [[NSWindow alloc]
        initWithContentRect:windowFrame
        styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                   NSMiniaturizableWindowMask | NSResizableWindowMask)
        backing:NSBackingStoreBuffered
        defer:NO];
    
    [window setTitle:@"Remote Desktop"];
    [window setMinSize:NSMakeSize(600, 300)];
    [window setDelegate:self];
    
    NSView *contentView = [window contentView];
    NSRect contentRect = [contentView bounds];
    // Using METRICS_CONTENT_SIDE_MARGIN (24px) for padding per HIG
    CGFloat padding = METRICS_CONTENT_SIDE_MARGIN;
    
    // Create split layout: left panel for services list, right panel for details/manual connect
    CGFloat leftWidth = 350;
    CGFloat rightWidth = contentRect.size.width - leftWidth - (padding * 3);
    
    // Left panel: Discovered Services
    NSRect leftRect = NSMakeRect(padding, padding, leftWidth, contentRect.size.height - (padding * 2));
    
    NSBox *servicesBox = [[NSBox alloc] initWithFrame:leftRect];
    [servicesBox setTitle:@"Discovered Services"];
    [servicesBox setAutoresizingMask:NSViewHeightSizable | NSViewMaxXMargin];
    
    // Using METRICS_SPACE_16 (16px) for spacing between group box edges and enclosed controls per HIG
    NSRect servicesContentRect = NSMakeRect(METRICS_SPACE_16, 50, leftWidth - (2 * METRICS_SPACE_16), leftRect.size.height - 80);
    NSScrollView *servicesScroll = [[NSScrollView alloc] initWithFrame:servicesContentRect];
    [servicesScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [servicesScroll setHasVerticalScroller:YES];
    [servicesScroll setHasHorizontalScroller:NO];
    [servicesScroll setBorderType:NSBezelBorder];
    
    servicesTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    [servicesTable setDataSource:self];
    [servicesTable setDelegate:self];
    [servicesTable setAllowsEmptySelection:YES];
    [servicesTable setAllowsMultipleSelection:NO];
    [servicesTable setDoubleAction:@selector(tableDoubleClicked:)];
    [servicesTable setTarget:self];
    
    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [[nameCol headerCell] setStringValue:@"Name"];
    [nameCol setWidth:leftWidth - 40];
    [nameCol setEditable:NO];
    [servicesTable addTableColumn:nameCol];
    RELEASE(nameCol);
    
    [servicesScroll setDocumentView:servicesTable];
    [servicesBox addSubview:servicesScroll];
    RELEASE(servicesScroll);
    
    // Connect button below service list
    // Using METRICS_BUTTON_HEIGHT (20px) for button height per HIG
    // Using METRICS_CONTENT_BOTTOM_MARGIN (20px) from bottom edge per HIG
    CGFloat buttonY = METRICS_CONTENT_BOTTOM_MARGIN;
    CGFloat buttonWidth = 100;
    NSRect connectRect = NSMakeRect(METRICS_SPACE_16, buttonY, buttonWidth, METRICS_BUTTON_HEIGHT);
    connectButton = [[NSButton alloc] initWithFrame:connectRect];
    [connectButton setTitle:@"Connect"];
    [connectButton setTarget:self];
    [connectButton setAction:@selector(connectButtonClicked:)];
    [connectButton setBezelStyle:NSRoundedBezelStyle];
    [connectButton setEnabled:NO];
    [servicesBox addSubview:connectButton];
    
    [contentView addSubview:servicesBox];
    RELEASE(servicesBox);
    
    // Right panel: Manual Connection
    NSRect rightRect = NSMakeRect(leftWidth + (padding * 2), padding, rightWidth, contentRect.size.height - (padding * 2));
    
    NSBox *manualBox = [[NSBox alloc] initWithFrame:rightRect];
    [manualBox setTitle:@"Manual Connection"];
    [manualBox setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    // Using METRICS_TEXT_INPUT_FIELD_HEIGHT (22px) for text input field height per HIG
    // Using METRICS_SPACE_16 (16px) for vertical spacing between controls per HIG
    // Using METRICS_SPACE_8 (8px) for horizontal gap between label and control per HIG
    CGFloat fieldHeight = METRICS_TEXT_INPUT_FIELD_HEIGHT;
    CGFloat labelWidth = 80;
    CGFloat fieldWidth = rightWidth - labelWidth - (3 * METRICS_SPACE_16);
    CGFloat yPos = rightRect.size.height - 60;
    
    // Protocol selection
    NSTextField *protocolLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(METRICS_SPACE_16, yPos, labelWidth, fieldHeight)];
    [protocolLabel setStringValue:@"Protocol:"];
    [protocolLabel setBezeled:NO];
    [protocolLabel setDrawsBackground:NO];
    [protocolLabel setEditable:NO];
    [protocolLabel setSelectable:NO];
    [protocolLabel setFont:METRICS_FONT_SYSTEM_REGULAR_13];
    [manualBox addSubview:protocolLabel];
    RELEASE(protocolLabel);
    
    protocolPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + METRICS_SPACE_16 + METRICS_SPACE_8, yPos - 1, fieldWidth, fieldHeight) pullsDown:NO];
    [protocolPopup addItemWithTitle:@"VNC"];
    [protocolPopup addItemWithTitle:@"RDP"];
    [manualBox addSubview:protocolPopup];
    
    yPos -= METRICS_SPACE_16 + fieldHeight;
    
    // Host field
    NSTextField *hostLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(METRICS_SPACE_16, yPos, labelWidth, fieldHeight)];
    [hostLabel setStringValue:@"Host:"];
    [hostLabel setBezeled:NO];
    [hostLabel setDrawsBackground:NO];
    [hostLabel setEditable:NO];
    [hostLabel setSelectable:NO];
    [hostLabel setFont:METRICS_FONT_SYSTEM_REGULAR_13];
    [manualBox addSubview:hostLabel];
    RELEASE(hostLabel);
    
    hostField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + METRICS_SPACE_16 + METRICS_SPACE_8, yPos, fieldWidth, fieldHeight)];
    [hostField setPlaceholderString:@"hostname or IP address"];
    [hostField setFont:METRICS_FONT_SYSTEM_REGULAR_13];
    [manualBox addSubview:hostField];
    
    yPos -= METRICS_SPACE_16 + fieldHeight;
    
    // Port field
    NSTextField *portLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(METRICS_SPACE_16, yPos, labelWidth, fieldHeight)];
    [portLabel setStringValue:@"Port:"];
    [portLabel setBezeled:NO];
    [portLabel setDrawsBackground:NO];
    [portLabel setEditable:NO];
    [portLabel setSelectable:NO];
    [portLabel setFont:METRICS_FONT_SYSTEM_REGULAR_13];
    [manualBox addSubview:portLabel];
    RELEASE(portLabel);
    
    portField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + METRICS_SPACE_16 + METRICS_SPACE_8, yPos, 80, fieldHeight)];
    [portField setPlaceholderString:@"5900"];
    [portField setFont:METRICS_FONT_SYSTEM_REGULAR_13];
    [manualBox addSubview:portField];
    
    yPos -= METRICS_SPACE_20 + METRICS_BUTTON_HEIGHT;
    
    // Manual connect button
    // Using METRICS_BUTTON_HEIGHT (20px) for button height per HIG
    // Using METRICS_SPACE_20 (20px) for vertical spacing between control groups per HIG
    NSButton *manualConnectButton = [[NSButton alloc] initWithFrame:NSMakeRect(labelWidth + METRICS_SPACE_16 + METRICS_SPACE_8, yPos, 120, METRICS_BUTTON_HEIGHT)];
    [manualConnectButton setTitle:@"Connect"];
    [manualConnectButton setTarget:self];
    [manualConnectButton setAction:@selector(manualConnectButtonClicked:)];
    [manualConnectButton setBezelStyle:NSRoundedBezelStyle];
    [manualBox addSubview:manualConnectButton];
    RELEASE(manualConnectButton);
    
    [contentView addSubview:manualBox];
    RELEASE(manualBox);
    
    [window makeKeyAndOrderFront:nil];
    
    // Start service discovery
    [self startServiceDiscovery];
}

- (void)createMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] init];
    
    // Application menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"RemoteDesktop" action:NULL keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];
    
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenuItem setSubmenu:appMenu];
    
    [appMenu addItemWithTitle:@"About Remote Desktop" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Remote Desktop" action:@selector(terminate:) keyEquivalent:@"q"];
    
    RELEASE(appMenu);
    RELEASE(appMenuItem);
    
    // File menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    [mainMenu addItem:fileMenuItem];
    
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenuItem setSubmenu:fileMenu];
    
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    
    RELEASE(fileMenu);
    RELEASE(fileMenuItem);
    
    // Edit menu
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    [mainMenu addItem:editMenuItem];
    
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenuItem setSubmenu:editMenu];
    
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    
    RELEASE(editMenu);
    RELEASE(editMenuItem);
    
    // Window menu
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:NULL keyEquivalent:@""];
    [mainMenu addItem:windowMenuItem];
    
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenuItem setSubmenu:windowMenu];
    
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    
    RELEASE(windowMenu);
    RELEASE(windowMenuItem);
    
    // Help menu
    NSMenuItem *helpMenuItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:NULL keyEquivalent:@""];
    [mainMenu addItem:helpMenuItem];
    
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpMenuItem setSubmenu:helpMenu];
    
    [helpMenu addItemWithTitle:@"About Remote Desktop" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    
    RELEASE(helpMenu);
    RELEASE(helpMenuItem);
    
    [NSApp setMainMenu:mainMenu];
    RELEASE(mainMenu);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApp
{
    // Don't terminate if there are active connection windows
    if ([vncWindows count] > 0 || [rdpWindows count] > 0) {
        return NO;
    }
    return YES;
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    if ([aNotification object] == window) {
        [self stopServiceDiscovery];
        
        // Close all connection windows
        for (VNCWindow *vncWindow in [NSArray arrayWithArray:vncWindows]) {
            [vncWindow close];
        }
        for (RDPWindow *rdpWindow in [NSArray arrayWithArray:rdpWindows]) {
            [rdpWindow close];
        }
        
        if ([vncWindows count] == 0 && [rdpWindows count] == 0) {
            [NSApp terminate:self];
        }
    }
}

#pragma mark - Service Discovery

- (void)startServiceDiscovery
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Starting service discovery...");
    
    // Check if mDNS-SD support is available
    Class netServiceBrowserClass = NSClassFromString(@"NSNetServiceBrowser");
    if (!netServiceBrowserClass) {
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: WARNING - mDNS-SD support is not available. Network service discovery will not work.");
        return;
    }
    
    // Start VNC browser
    vncBrowser = [[NSNetServiceBrowser alloc] init];
    [vncBrowser setDelegate:self];
    [vncBrowser searchForServicesOfType:@"_rfb._tcp" inDomain:@"local"];
    
    // Start RDP browser
    rdpBrowser = [[NSNetServiceBrowser alloc] init];
    [rdpBrowser setDelegate:self];
    [rdpBrowser searchForServicesOfType:@"_rdp._tcp" inDomain:@"local"];
    
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Service discovery started for VNC and RDP");
}

- (void)stopServiceDiscovery
{
    if (vncBrowser) {
        [vncBrowser stop];
        RELEASE(vncBrowser);
        vncBrowser = nil;
    }
    
    if (rdpBrowser) {
        [rdpBrowser stop];
        RELEASE(rdpBrowser);
        rdpBrowser = nil;
    }
}

#pragma mark - UI Actions

- (void)connectButtonClicked:(id)sender
{
    NSInteger selectedRow = [servicesTable selectedRow];
    if (selectedRow >= 0 && selectedRow < (NSInteger)[discoveredServices count]) {
        RemoteService *service = [discoveredServices objectAtIndex:selectedRow];
        [self connectToService:service];
    }
}

- (void)manualConnectButtonClicked:(id)sender
{
    NSString *host = [hostField stringValue];
    if ([host length] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Host Required"];
        [alert setInformativeText:@"Please enter a hostname or IP address."];
        [alert runModal];
        [alert release];
        return;
    }
    
    NSString *portString = [portField stringValue];
    NSInteger selectedProtocol = [protocolPopup indexOfSelectedItem];
    
    NSInteger port;
    if ([portString length] > 0) {
        port = [portString integerValue];
    } else {
        // Default ports
        port = (selectedProtocol == 0) ? 5900 : 3389;
    }
    
    if (selectedProtocol == 0) {
        // VNC
        [self connectToVNCHost:host port:port username:nil password:nil];
    } else {
        // RDP
        [self connectToRDPHost:host port:port username:nil password:nil];
    }
}

- (void)tableDoubleClicked:(id)sender
{
    NSInteger selectedRow = [servicesTable selectedRow];
    if (selectedRow >= 0 && selectedRow < (NSInteger)[discoveredServices count]) {
        RemoteService *service = [discoveredServices objectAtIndex:selectedRow];
        [self connectToService:service];
    }
}

#pragma mark - Connection Management

- (void)connectToService:(RemoteService *)service
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Connecting to service: %@ (%@:%ld)", 
          [service name], [service hostname], (long)[service port]);
    
    if ([service type] == RemoteServiceTypeVNC) {
        [self connectToVNCHost:[service hostname] port:[service port] username:nil password:nil serviceName:[service name]];
    } else if ([service type] == RemoteServiceTypeRDP) {
        [self connectToRDPHost:[service hostname] port:[service port] username:nil password:nil serviceName:[service name]];
    }
}

- (void)connectToVNCHost:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password
{
    [self connectToVNCHost:hostname port:port username:username password:password headless:NO serviceName:nil];
}

- (void)connectToVNCHost:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password serviceName:(NSString *)serviceName
{
    [self connectToVNCHost:hostname port:port username:username password:password headless:NO serviceName:serviceName];
}

- (void)connectToVNCHost:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password headless:(BOOL)headless
{
    [self connectToVNCHost:hostname port:port username:username password:password headless:headless serviceName:nil];
}

- (void)connectToVNCHost:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password headless:(BOOL)headless serviceName:(NSString *)serviceName
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Opening VNC connection to %@:%ld%@", hostname, (long)port, headless ? @" [headless]" : @"");
    
    if (![VNCClient isLibVNCClientAvailable]) {
        if (headless) {
            NSDebugLLog(@"gwcomp", @"RemoteDesktop: ERROR - libvncclient is not installed");
            [NSApp terminate:nil];
            return;
        }
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"VNC Library Not Found"];
        [alert setInformativeText:@"libvncclient is not installed. Please install the libvncserver package."];
        [alert runModal];
        [alert release];
        return;
    }
    
    NSRect contentRect = NSMakeRect(0, 0, 800, 600);
    VNCWindow *vncWindow = [[VNCWindow alloc] initWithContentRect:contentRect 
                                                         hostname:hostname 
                                                             port:port 
                                                         username:username
                                                         password:password];
    [vncWindow setHeadlessMode:headless];
    [vncWindow setVncDelegate:self];
    if (serviceName) {
        [vncWindow setTitle:serviceName];
    }
    if (!headless) {
        [vncWindow center];
    }
    [vncWindow connectToVNC];
    
    [vncWindows addObject:vncWindow];
    [vncWindow release];
}

- (void)connectToRDPHost:(NSString *)hostname port:(NSInteger)port 
                username:(NSString *)username password:(NSString *)password
{
    [self connectToRDPHost:hostname port:port username:username password:password serviceName:nil];
}

- (void)connectToRDPHost:(NSString *)hostname port:(NSInteger)port 
                username:(NSString *)username password:(NSString *)password serviceName:(NSString *)serviceName
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Opening RDP connection to %@:%ld", hostname, (long)port);
    
    if (![RDPClient isFreeRDPAvailable]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"RDP Library Not Found"];
        [alert setInformativeText:@"FreeRDP is not installed. Please install the freerdp2 package."];
        [alert runModal];
        [alert release];
        return;
    }
    
    NSRect contentRect = NSMakeRect(0, 0, 1024, 768);
    RDPWindow *rdpWindow = [[RDPWindow alloc] initWithContentRect:contentRect 
                                                         hostname:hostname 
                                                             port:port 
                                                         username:username 
                                                         password:password];
    [rdpWindow setRdpDelegate:self];
    if (serviceName) {
        [rdpWindow setTitle:serviceName];
    }
    // Note: Window will be shown after successful connection via rdpClient:didConnect:
    [rdpWindow connectToRDP];
    
    [rdpWindows addObject:rdpWindow];
    [rdpWindow release];
}

#pragma mark - Command Line Connection

- (void)connectFromCommandLine:(NSString *)hostname protocol:(NSString *)protocol username:(NSString *)username password:(NSString *)password
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Command line auto-connect to %@ via %@ (username: %@, password: %@)", 
          hostname,
          [protocol uppercaseString],
          username ? username : @"(none)",
          password ? @"<provided>" : @"(none)");
    
    // Determine protocol and use appropriate connection method
    BOOL isRDP = [[protocol lowercaseString] isEqual:@"rdp"];
    
    if (isRDP) {
        // RDP connection on default port 3389
        NSInteger port = 3389;
        [self connectToRDPHost:hostname port:port username:username password:password];
    } else {
        // VNC connection on default port 5900 (default)
        NSInteger port = 5900;
        [self connectToVNCHost:hostname port:port username:username password:password headless:YES];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [discoveredServices count];
}

- (id)tableView:(NSTableView *)tableView
  objectValueForTableColumn:(NSTableColumn *)tableColumn
  row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)[discoveredServices count]) {
        return nil;
    }
    
    RemoteService *service = [discoveredServices objectAtIndex:row];
    NSString *identifier = [tableColumn identifier];
    
    if ([identifier isEqual:@"name"]) {
        return [service name];
    } else if ([identifier isEqual:@"type"]) {
        return [service typeString];
    } else if ([identifier isEqual:@"host"]) {
        return [service hostname] ? [service hostname] : @"(resolving...)";
    }
    
    return nil;
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    NSInteger selectedRow = [servicesTable selectedRow];
    
    if (selectedRow >= 0 && selectedRow < (NSInteger)[discoveredServices count]) {
        RemoteService *service = [discoveredServices objectAtIndex:selectedRow];
        
        NSMutableString *details = [[NSMutableString alloc] init];
        [details appendFormat:@"Name: %@\n", [service name]];
        [details appendFormat:@"Type: %@\n", [service typeString]];
        [details appendFormat:@"Host: %@\n", [service hostname] ? [service hostname] : @"(resolving...)"];
        [details appendFormat:@"Port: %ld\n", (long)[service port]];
        
        if ([service netService]) {
            NSNetService *netService = [service netService];
            [details appendFormat:@"Domain: %@\n", [netService domain]];
            
            NSArray *addresses = [netService addresses];
            if ([addresses count] > 0) {
                [details appendString:@"\nAddresses:\n"];
                for (NSData *addr in addresses) {
                    [details appendFormat:@"  %@\n", addr];
                }
            }
        }
        
        [details appendString:@"\nDouble-click or press Connect to open a session."];
        
        RELEASE(details);
        
        [connectButton setEnabled:YES];
    } else {
        [connectButton setEnabled:NO];
    }
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    if (aNetServiceBrowser == vncBrowser) {
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Starting VNC service discovery...");
    } else if (aNetServiceBrowser == rdpBrowser) {
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Starting RDP service discovery...");
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Service browser stopped");
}

- (BOOL)serviceAlreadyExists:(NSNetService *)aNetService withType:(RemoteServiceType)serviceType
{
    // Check for existing service by NetService object first
    for (RemoteService *existing in discoveredServices) {
        if ([existing netService] == aNetService) {
            return YES;
        }
    }
    
    return NO;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
           didFindService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    NSString *type = [aNetService type];
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Found service: %@ (type: %@)", [aNetService name], type);
    
    // Determine service type
    RemoteServiceType serviceType = RemoteServiceTypeUnknown;
    if ([type hasPrefix:@"_rfb."]) {
        serviceType = RemoteServiceTypeVNC;
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Detected VNC service");
    } else if ([type hasPrefix:@"_rdp."]) {
        serviceType = RemoteServiceTypeRDP;
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Detected RDP service (Windows Remote Desktop or compatible)");
    } else {
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Warning - Unknown service type: %@", type);
    }
    
    // Check for duplicates by NetService object
    if ([self serviceAlreadyExists:aNetService withType:serviceType]) {
        NSDebugLLog(@"gwcomp", @"RemoteDesktop: Service already in list, skipping: %@", [aNetService name]);
        return;
    }
    
    // Create a new RemoteService
    RemoteService *service = [[RemoteService alloc] init];
    [service setName:[aNetService name]];
    [service setNetService:aNetService];
    [service setType:serviceType];
    
    // Set default ports based on service type
    switch (serviceType) {
        case RemoteServiceTypeVNC:
            [service setPort:5900];
            break;
        case RemoteServiceTypeRDP:
            [service setPort:3389];
            break;
        default:
            [service setPort:0];
            break;
    }
    
    // Start resolving the service to get hostname and actual port
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:10.0];
    
    [discoveredServices addObject:service];
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Added service to list (total: %lu)", (unsigned long)[discoveredServices count]);
    RELEASE(service);
    
    [servicesTable reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
         didRemoveService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Service removed: %@ (type: %@)", [aNetService name], [aNetService type]);
    
    // Use a copy of the array to safely remove items during iteration
    NSArray *servicesCopy = [NSArray arrayWithArray:discoveredServices];
    for (RemoteService *service in servicesCopy) {
        if ([service netService] == aNetService) {
            NSDebugLLog(@"gwcomp", @"RemoteDesktop: Removing %@ from service list", [service name]);
            [discoveredServices removeObject:service];
            break;
        }
    }
    
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Services remaining: %lu", (unsigned long)[discoveredServices count]);
    [servicesTable reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
             didNotSearch:(NSDictionary *)errorDict
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Service discovery error: %@", errorDict);
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    NSString *hostname = [sender hostName];
    NSInteger port = [sender port];
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Service resolved: %@ -> %@:%ld", 
          [sender name], hostname, (long)port);
    
    // Update the RemoteService with resolved information
    RemoteService *resolvedService = nil;
    for (RemoteService *service in discoveredServices) {
        if ([service netService] == sender) {
            [service setHostname:hostname];
            [service setPort:port];
            resolvedService = service;
            NSDebugLLog(@"gwcomp", @"RemoteDesktop: Updated %@ (%@) - %@:%ld", 
                  [service name], [service typeString], hostname, (long)port);
            break;
        }
    }
    
    if (resolvedService) {
        // Check for duplicate services with same hostname, port, and type
        NSMutableArray *toRemove = [[NSMutableArray alloc] init];
        for (RemoteService *service in discoveredServices) {
            // Skip the service we just resolved
            if (service == resolvedService) continue;
            
            // If another service has the same hostname, port, and type, mark it for removal
            if ([service hostname] && [resolvedService hostname] &&
                [[service hostname] isEqual:[resolvedService hostname]] &&
                [service port] == [resolvedService port] &&
                [service type] == [resolvedService type]) {
                NSDebugLLog(@"gwcomp", @"RemoteDesktop: Found duplicate service: %@ (same as %@)", 
                      [service name], [resolvedService name]);
                [toRemove addObject:service];
            }
        }
        
        // Remove duplicates
        if ([toRemove count] > 0) {
            NSDebugLLog(@"gwcomp", @"RemoteDesktop: Removing %lu duplicate services", (unsigned long)[toRemove count]);
            [discoveredServices removeObjectsInArray:toRemove];
        }
        [toRemove release];
    }
    
    [servicesTable reloadData];
    
    // Update details if this service is selected
    NSInteger selectedRow = [servicesTable selectedRow];
    if (selectedRow >= 0 && selectedRow < (NSInteger)[discoveredServices count]) {
        RemoteService *selectedService = [discoveredServices objectAtIndex:selectedRow];
        if ([selectedService netService] == sender) {
            [self tableViewSelectionDidChange:nil];
        }
    }
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: Failed to resolve service %@: %@", [sender name], errorDict);
}

#pragma mark - VNCWindowDelegate

- (void)vncWindowWillClose:(VNCWindow *)vncWindow
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: VNC window closing");
    [vncWindows removeObject:vncWindow];
}

#pragma mark - RDPWindowDelegate

- (void)rdpWindowWillClose:(RDPWindow *)rdpWindow
{
    NSDebugLLog(@"gwcomp", @"RemoteDesktop: RDP window closing");
    [rdpWindows removeObject:rdpWindow];
}

@end
