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
    }
    return self;
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
    // Create menu
    [self createMenu];
    
    // Create main window
    NSRect windowFrame = NSMakeRect(100, 100, 800, 600);
    window = [[NSWindow alloc]
        initWithContentRect:windowFrame
        styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                   NSMiniaturizableWindowMask | NSResizableWindowMask)
        backing:NSBackingStoreBuffered
        defer:NO];
    
    [window setTitle:@"Remote Desktop"];
    [window setMinSize:NSMakeSize(600, 400)];
    [window setDelegate:self];
    
    NSView *contentView = [window contentView];
    NSRect contentRect = [contentView bounds];
    CGFloat padding = 10;
    
    // Create split layout: left panel for services list, right panel for details/manual connect
    CGFloat leftWidth = 350;
    CGFloat rightWidth = contentRect.size.width - leftWidth - (padding * 3);
    
    // Left panel: Discovered Services
    NSRect leftRect = NSMakeRect(padding, padding, leftWidth, contentRect.size.height - (padding * 2));
    
    NSBox *servicesBox = [[NSBox alloc] initWithFrame:leftRect];
    [servicesBox setTitle:@"Discovered Services"];
    [servicesBox setAutoresizingMask:NSViewHeightSizable | NSViewMaxXMargin];
    
    NSRect servicesContentRect = NSMakeRect(10, 50, leftWidth - 20, leftRect.size.height - 80);
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
    [nameCol setWidth:200];
    [nameCol setEditable:NO];
    [servicesTable addTableColumn:nameCol];
    RELEASE(nameCol);
    
    NSTableColumn *typeCol = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    [[typeCol headerCell] setStringValue:@"Type"];
    [typeCol setWidth:50];
    [typeCol setEditable:NO];
    [servicesTable addTableColumn:typeCol];
    RELEASE(typeCol);
    
    NSTableColumn *hostCol = [[NSTableColumn alloc] initWithIdentifier:@"host"];
    [[hostCol headerCell] setStringValue:@"Host"];
    [hostCol setWidth:80];
    [hostCol setEditable:NO];
    [servicesTable addTableColumn:hostCol];
    RELEASE(hostCol);
    
    [servicesScroll setDocumentView:servicesTable];
    [servicesBox addSubview:servicesScroll];
    RELEASE(servicesScroll);
    
    // Buttons below service list
    NSRect refreshRect = NSMakeRect(10, 10, 100, 30);
    refreshButton = [[NSButton alloc] initWithFrame:refreshRect];
    [refreshButton setTitle:@"Refresh"];
    [refreshButton setTarget:self];
    [refreshButton setAction:@selector(refreshButtonClicked:)];
    [refreshButton setBezelStyle:NSRoundedBezelStyle];
    [servicesBox addSubview:refreshButton];
    
    NSRect connectRect = NSMakeRect(120, 10, 100, 30);
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
    
    CGFloat fieldHeight = 25;
    CGFloat labelWidth = 80;
    CGFloat fieldWidth = rightWidth - labelWidth - 40;
    CGFloat yPos = rightRect.size.height - 60;
    
    // Protocol selection
    NSTextField *protocolLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, yPos, labelWidth, fieldHeight)];
    [protocolLabel setStringValue:@"Protocol:"];
    [protocolLabel setBezeled:NO];
    [protocolLabel setDrawsBackground:NO];
    [protocolLabel setEditable:NO];
    [protocolLabel setSelectable:NO];
    [manualBox addSubview:protocolLabel];
    RELEASE(protocolLabel);
    
    protocolPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + 20, yPos, fieldWidth, fieldHeight) pullsDown:NO];
    [protocolPopup addItemWithTitle:@"VNC"];
    [protocolPopup addItemWithTitle:@"RDP"];
    [manualBox addSubview:protocolPopup];
    
    yPos -= 35;
    
    // Host field
    NSTextField *hostLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, yPos, labelWidth, fieldHeight)];
    [hostLabel setStringValue:@"Host:"];
    [hostLabel setBezeled:NO];
    [hostLabel setDrawsBackground:NO];
    [hostLabel setEditable:NO];
    [hostLabel setSelectable:NO];
    [manualBox addSubview:hostLabel];
    RELEASE(hostLabel);
    
    hostField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 20, yPos, fieldWidth, fieldHeight)];
    [hostField setPlaceholderString:@"hostname or IP address"];
    [manualBox addSubview:hostField];
    
    yPos -= 35;
    
    // Port field
    NSTextField *portLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, yPos, labelWidth, fieldHeight)];
    [portLabel setStringValue:@"Port:"];
    [portLabel setBezeled:NO];
    [portLabel setDrawsBackground:NO];
    [portLabel setEditable:NO];
    [portLabel setSelectable:NO];
    [manualBox addSubview:portLabel];
    RELEASE(portLabel);
    
    portField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 20, yPos, 80, fieldHeight)];
    [portField setPlaceholderString:@"5900"];
    [manualBox addSubview:portField];
    
    yPos -= 35;
    
    // Username field (for RDP)
    NSTextField *usernameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, yPos, labelWidth, fieldHeight)];
    [usernameLabel setStringValue:@"Username:"];
    [usernameLabel setBezeled:NO];
    [usernameLabel setDrawsBackground:NO];
    [usernameLabel setEditable:NO];
    [usernameLabel setSelectable:NO];
    [manualBox addSubview:usernameLabel];
    RELEASE(usernameLabel);
    
    usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 20, yPos, fieldWidth, fieldHeight)];
    [usernameField setPlaceholderString:@"(optional for RDP)"];
    [manualBox addSubview:usernameField];
    
    yPos -= 35;
    
    // Password field
    NSTextField *passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, yPos, labelWidth, fieldHeight)];
    [passwordLabel setStringValue:@"Password:"];
    [passwordLabel setBezeled:NO];
    [passwordLabel setDrawsBackground:NO];
    [passwordLabel setEditable:NO];
    [passwordLabel setSelectable:NO];
    [manualBox addSubview:passwordLabel];
    RELEASE(passwordLabel);
    
    passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(labelWidth + 20, yPos, fieldWidth, fieldHeight)];
    [passwordField setPlaceholderString:@"(optional)"];
    [manualBox addSubview:passwordField];
    
    yPos -= 45;
    
    // Manual connect button
    NSButton *manualConnectButton = [[NSButton alloc] initWithFrame:NSMakeRect(labelWidth + 20, yPos, 120, 30)];
    [manualConnectButton setTitle:@"Connect"];
    [manualConnectButton setTarget:self];
    [manualConnectButton setAction:@selector(manualConnectButtonClicked:)];
    [manualConnectButton setBezelStyle:NSRoundedBezelStyle];
    [manualBox addSubview:manualConnectButton];
    RELEASE(manualConnectButton);
    
    yPos -= 60;
    
    // Details text view
    NSRect detailsRect = NSMakeRect(10, 10, rightWidth - 20, yPos - 10);
    NSScrollView *detailsScroll = [[NSScrollView alloc] initWithFrame:detailsRect];
    [detailsScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [detailsScroll setHasVerticalScroller:YES];
    [detailsScroll setHasHorizontalScroller:NO];
    [detailsScroll setBorderType:NSBezelBorder];
    
    detailsText = [[NSTextView alloc] initWithFrame:NSZeroRect];
    [detailsText setEditable:NO];
    [detailsText setSelectable:YES];
    [detailsText setString:@"Select a discovered service to see details, or enter connection information manually above.\n\n"
                           @"Supported protocols:\n"
                           @"• VNC (Virtual Network Computing) - Port 5900\n"
                           @"• RDP (Remote Desktop Protocol) - Port 3389\n\n"
                           @"Note: VNC requires libvncclient, RDP requires FreeRDP."];
    
    [detailsScroll setDocumentView:detailsText];
    [manualBox addSubview:detailsScroll];
    RELEASE(detailsScroll);
    
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
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenuItem setSubmenu:appMenu];
    
    [appMenu addItemWithTitle:@"About Remote Desktop" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Remote Desktop" action:@selector(terminate:) keyEquivalent:@"q"];
    
    RELEASE(appMenu);
    RELEASE(appMenuItem);
    
    // File menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileMenuItem];
    
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenuItem setSubmenu:fileMenu];
    
    [fileMenu addItemWithTitle:@"Refresh Services" action:@selector(refreshButtonClicked:) keyEquivalent:@"r"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    
    RELEASE(fileMenu);
    RELEASE(fileMenuItem);
    
    // Edit menu
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
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
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:windowMenuItem];
    
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenuItem setSubmenu:windowMenu];
    
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    
    RELEASE(windowMenu);
    RELEASE(windowMenuItem);
    
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
    NSLog(@"RemoteDesktop: Starting service discovery...");
    
    // Check if mDNS-SD support is available
    Class netServiceBrowserClass = NSClassFromString(@"NSNetServiceBrowser");
    if (!netServiceBrowserClass) {
        [detailsText setString:@"mDNS-SD support is not available.\n\n"
                               @"Network service discovery will not work. "
                               @"You can still connect manually by entering the host address above.\n\n"
                               @"To enable service discovery:\n"
                               @"1. Install libavahi-compat-libdnssd-dev\n"
                               @"2. Rebuild GNUstep with DNS-SD support"];
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
    
    NSLog(@"RemoteDesktop: Service discovery started for VNC and RDP");
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

- (void)refreshButtonClicked:(id)sender
{
    NSLog(@"RemoteDesktop: Refreshing services...");
    
    [discoveredServices removeAllObjects];
    [servicesTable reloadData];
    
    [self stopServiceDiscovery];
    [self startServiceDiscovery];
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
    NSString *username = [usernameField stringValue];
    NSString *password = [passwordField stringValue];
    
    NSInteger port;
    if ([portString length] > 0) {
        port = [portString integerValue];
    } else {
        // Default ports
        port = (selectedProtocol == 0) ? 5900 : 3389;
    }
    
    if (selectedProtocol == 0) {
        // VNC
        [self connectToVNCHost:host port:port username:username password:password];
    } else {
        // RDP
        [self connectToRDPHost:host port:port username:username password:password];
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
    NSLog(@"RemoteDesktop: Connecting to service: %@ (%@:%ld)", 
          [service name], [service hostname], (long)[service port]);
    
    if ([service type] == RemoteServiceTypeVNC) {
        [self connectToVNCHost:[service hostname] port:[service port] username:nil password:nil];
    } else if ([service type] == RemoteServiceTypeRDP) {
        [self connectToRDPHost:[service hostname] port:[service port] username:nil password:nil];
    }
}

- (void)connectToVNCHost:(NSString *)hostname port:(NSInteger)port username:(NSString *)username password:(NSString *)password
{
    NSLog(@"RemoteDesktop: Opening VNC connection to %@:%ld", hostname, (long)port);
    
    if (![VNCClient isLibVNCClientAvailable]) {
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
    [vncWindow setVncDelegate:self];
    [vncWindow center];
    [vncWindow connectToVNC];
    
    [vncWindows addObject:vncWindow];
    [vncWindow release];
}

- (void)connectToRDPHost:(NSString *)hostname port:(NSInteger)port 
                username:(NSString *)username password:(NSString *)password
{
    NSLog(@"RemoteDesktop: Opening RDP connection to %@:%ld", hostname, (long)port);
    
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
    [rdpWindow center];
    [rdpWindow makeKeyAndOrderFront:nil];
    [rdpWindow connectToRDP];
    
    [rdpWindows addObject:rdpWindow];
    [rdpWindow release];
}

#pragma mark - Command Line Connection

- (void)connectFromCommandLine:(NSString *)hostname username:(NSString *)username password:(NSString *)password
{
    NSLog(@"RemoteDesktop: Command line auto-connect to %@ (username: %@, password: %@)", 
          hostname,
          username ? username : @"(none)",
          password ? @"<provided>" : @"(none)");
    
    // Default to VNC on port 5900
    NSInteger port = 5900;
    
    [self connectToVNCHost:hostname port:port username:username password:password];
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
        
        [detailsText setString:details];
        RELEASE(details);
        
        [connectButton setEnabled:YES];
    } else {
        [detailsText setString:@"Select a discovered service to see details, or enter connection information manually above."];
        [connectButton setEnabled:NO];
    }
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    if (aNetServiceBrowser == vncBrowser) {
        NSLog(@"RemoteDesktop: Starting VNC service discovery...");
    } else if (aNetServiceBrowser == rdpBrowser) {
        NSLog(@"RemoteDesktop: Starting RDP service discovery...");
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
    NSLog(@"RemoteDesktop: Service browser stopped");
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
           didFindService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    NSLog(@"RemoteDesktop: Found service: %@ (%@)", [aNetService name], [aNetService type]);
    
    // Check for duplicates
    for (RemoteService *existing in discoveredServices) {
        if ([[existing name] isEqual:[aNetService name]] && 
            [existing netService] == aNetService) {
            return;
        }
    }
    
    // Create a new RemoteService
    RemoteService *service = [[RemoteService alloc] init];
    [service setName:[aNetService name]];
    [service setNetService:aNetService];
    
    // Determine service type
    NSString *type = [aNetService type];
    if ([type hasPrefix:@"_rfb."]) {
        [service setType:RemoteServiceTypeVNC];
        [service setPort:5900]; // Default VNC port
    } else if ([type hasPrefix:@"_rdp."]) {
        [service setType:RemoteServiceTypeRDP];
        [service setPort:3389]; // Default RDP port
    }
    
    // Start resolving the service
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:10.0];
    
    [discoveredServices addObject:service];
    RELEASE(service);
    
    [servicesTable reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
         didRemoveService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    NSLog(@"RemoteDesktop: Service removed: %@", [aNetService name]);
    
    for (RemoteService *service in [NSArray arrayWithArray:discoveredServices]) {
        if ([service netService] == aNetService) {
            [discoveredServices removeObject:service];
            break;
        }
    }
    
    [servicesTable reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
             didNotSearch:(NSDictionary *)errorDict
{
    NSLog(@"RemoteDesktop: Service discovery error: %@", errorDict);
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    NSLog(@"RemoteDesktop: Service resolved: %@ -> %@:%ld", 
          [sender name], [sender hostName], (long)[sender port]);
    
    // Update the RemoteService with resolved information
    for (RemoteService *service in discoveredServices) {
        if ([service netService] == sender) {
            [service setHostname:[sender hostName]];
            [service setPort:[sender port]];
            break;
        }
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
    NSLog(@"RemoteDesktop: Failed to resolve service %@: %@", [sender name], errorDict);
}

#pragma mark - VNCWindowDelegate

- (void)vncWindowWillClose:(VNCWindow *)vncWindow
{
    NSLog(@"RemoteDesktop: VNC window closing");
    [vncWindows removeObject:vncWindow];
}

#pragma mark - RDPWindowDelegate

- (void)rdpWindowWillClose:(RDPWindow *)rdpWindow
{
    NSLog(@"RemoteDesktop: RDP window closing");
    [rdpWindows removeObject:rdpWindow];
}

@end
