/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PreferencesController.h"
#import "AppDelegate.h"
#import "SIPManager.h"

@interface PreferencesController ()
@property (strong) NSTextField *serverField;
@property (strong) NSTextField *usernameField;
@property (strong) NSTextField *passwordField;
@property (strong) NSPopUpButton *audioInputPopup;
@property (strong) NSPopUpButton *audioOutputPopup;
@property (strong) NSButton *testRegisterBtn;
@property (strong) NSButton *discoverBtn;
@property (strong) NSTextField *regStatusLabel;
@property (strong) NSMutableArray *discoveredServers;
@end

@implementation PreferencesController

+ (PreferencesController *)sharedController {
    static PreferencesController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PreferencesController alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 450, 400)
                                                   styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Preferences"];
    [window center];
    
    self = [super initWithWindow:window];
    if (self) {
        _discoveredServers = [NSMutableArray array];
        [self setupUI];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(registrationChanged:) 
                                                     name:@"SIPRegistrationStateChanged" 
                                                   object:nil];
    }
    return self;
}

- (void)registrationChanged:(NSNotification *)notif {
    NSString *state = [notif object];
    [self.regStatusLabel setStringValue:state];
}

- (void)setupUI {
    NSView *contentView = [self.window contentView];
    
    CGFloat y = 350;
    
    // Server
    NSTextField *serverLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    [serverLabel setStringValue:@"SIP Server:"];
    [serverLabel setBezeled:NO];
    [serverLabel setDrawsBackground:NO];
    [serverLabel setEditable:NO];
    [serverLabel setSelectable:NO];
    [contentView addSubview:serverLabel];
    
    self.serverField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 200, 22)];
    [contentView addSubview:self.serverField];
    
    self.discoverBtn = [[NSButton alloc] initWithFrame:NSMakeRect(340, y-5, 90, 32)];
    [self.discoverBtn setTitle:@"Discover"];
    [self.discoverBtn setTarget:self];
    [self.discoverBtn setAction:@selector(discoverServers:)];
    [contentView addSubview:self.discoverBtn];
    
    y -= 40;
    
    // Username
    NSTextField *userLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    [userLabel setStringValue:@"Username:"];
    [userLabel setBezeled:NO];
    [userLabel setDrawsBackground:NO];
    [userLabel setEditable:NO];
    [userLabel setSelectable:NO];
    [contentView addSubview:userLabel];
    
    self.usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 250, 22)];
    [contentView addSubview:self.usernameField];
    
    y -= 40;
    
    // Password
    NSTextField *passLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    [passLabel setStringValue:@"Password:"];
    [passLabel setBezeled:NO];
    [passLabel setDrawsBackground:NO];
    [passLabel setEditable:NO];
    [passLabel setSelectable:NO];
    [contentView addSubview:passLabel];
    
    self.passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(130, y, 250, 22)];
    [contentView addSubview:self.passwordField];
    
    y -= 50;

    // Register Button (Test)
    self.testRegisterBtn = [[NSButton alloc] initWithFrame:NSMakeRect(130, y, 120, 32)];
    [self.testRegisterBtn setTitle:@"Register Now"];
    [self.testRegisterBtn setTarget:self];
    [self.testRegisterBtn setAction:@selector(testRegister:)];
    [contentView addSubview:self.testRegisterBtn];

    self.regStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(260, y+5, 150, 20)];
    [self.regStatusLabel setBezeled:NO];
    [self.regStatusLabel setDrawsBackground:NO];
    [self.regStatusLabel setEditable:NO];
    [self.regStatusLabel setSelectable:NO];
    [self.regStatusLabel setFont:[NSFont systemFontOfSize:11]];
    [self.regStatusLabel setStringValue:@""];
    [contentView addSubview:self.regStatusLabel];

    y -= 60;

    // Audio Settings
    NSTextField *audioInLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    [audioInLabel setStringValue:@"Audio Input:"];
    [audioInLabel setBezeled:NO];
    [audioInLabel setDrawsBackground:NO];
    [audioInLabel setEditable:NO];
    [audioInLabel setSelectable:NO];
    [contentView addSubview:audioInLabel];

    self.audioInputPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, y, 250, 22) pullsDown:NO];
    [contentView addSubview:self.audioInputPopup];

    y -= 40;

    NSTextField *audioOutLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 20)];
    [audioOutLabel setStringValue:@"Audio Output:"];
    [audioOutLabel setBezeled:NO];
    [audioOutLabel setDrawsBackground:NO];
    [audioOutLabel setEditable:NO];
    [audioOutLabel setSelectable:NO];
    [contentView addSubview:audioOutLabel];

    self.audioOutputPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, y, 250, 22) pullsDown:NO];
    [contentView addSubview:self.audioOutputPopup];

    // Build buttons at bottom
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(220, 20, 100, 32)];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancel:)];
    [contentView addSubview:cancelButton];

    // Save Button
    NSButton *saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(330, 20, 100, 32)];
    [saveButton setTitle:@"Save"];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(savePreferences:)];
    [saveButton setKeyEquivalent:@"\r"];
    [contentView addSubview:saveButton];
}

- (void)showWindow:(id)sender {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showWindow:sender];
        });
        return;
    }
    NSLog(@"PreferencesController: showWindow called (before) - window instance: %@", self.window);
    if (self.window) {
        NSLog(@"PreferencesController: current frame before show: %@, visible: %d", NSStringFromRect(self.window.frame), self.window.isVisible);
    }
    // Load Defaults every time we show
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [self.serverField setStringValue:[defaults stringForKey:@"SIPServer"] ?: @""];
    [self.usernameField setStringValue:[defaults stringForKey:@"SIPUsername"] ?: @""];
    [self.passwordField setStringValue:[defaults stringForKey:@"SIPPassword"] ?: @""];
    
    // Load Audio Devices
    AppDelegate *appDelegate = (AppDelegate *)[NSApp delegate];
    NSArray *inputs = [appDelegate.sipManager availableAudioInputs];
    NSArray *outputs = [appDelegate.sipManager availableAudioOutputs];
    
    [self.audioInputPopup removeAllItems];
    [self.audioInputPopup addItemsWithTitles:inputs];
    NSString *selIn = [defaults stringForKey:@"AudioInput"];
    if (selIn) [self.audioInputPopup selectItemWithTitle:selIn];
    
    [self.audioOutputPopup removeAllItems];
    [self.audioOutputPopup addItemsWithTitles:outputs];
    NSString *selOut = [defaults stringForKey:@"AudioOutput"];
    if (selOut) [self.audioOutputPopup selectItemWithTitle:selOut];

    [super showWindow:sender];
    // Ensure the window is ordered front and key/visible
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeMainWindow];

    // Fallback for environments where makeKeyAndOrderFront may not be sufficient
    if (!self.window.isVisible) {
        NSLog(@"PreferencesController: window not visible after makeKeyAndOrderFront - applying fallback orderFront");
        [self.window orderFront:nil];
        [self.window makeKeyAndOrderFront:nil];
    }

    // Prevent the window from being released when closed on older GNUStep versions
    if ([self.window respondsToSelector:@selector(setReleasedWhenClosed:)]) {
        [self.window setReleasedWhenClosed:NO];
    }

    NSLog(@"PreferencesController: showWindow called (after) - frame: %@, visible: %d", NSStringFromRect(self.window.frame), self.window.isVisible);
}

- (void)cancel:(id)sender {
    [self.window close];
}

- (void)savePreferences:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[self.serverField stringValue] forKey:@"SIPServer"];
    [defaults setObject:[self.usernameField stringValue] forKey:@"SIPUsername"];
    [defaults setObject:[self.passwordField stringValue] forKey:@"SIPPassword"];
    [defaults setObject:[self.audioInputPopup titleOfSelectedItem] forKey:@"AudioInput"];
    [defaults setObject:[self.audioOutputPopup titleOfSelectedItem] forKey:@"AudioOutput"];
    [defaults synchronize];
    
    AppDelegate *appDelegate = (AppDelegate *)[NSApp delegate];
    [appDelegate.sipManager updateSettings];
    
    [self.window close];
}

- (void)testRegister:(id)sender {
    // Just force a re-registration
    AppDelegate *appDelegate = (AppDelegate *)[NSApp delegate];
    [appDelegate.sipManager updateSettings];
}

#pragma mark - mDNS Discovery

- (void)discoverServers:(id)sender {
    [self.discoverBtn setEnabled:NO];
    [self.discoverBtn setTitle:@"Searching..."];
    [self.discoveredServers removeAllObjects];
    
    NSString *browsePath = @"/usr/bin/avahi-browse";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:browsePath]) {
        browsePath = @"/usr/local/bin/avahi-browse";
    }

    if (![[NSFileManager defaultManager] isExecutableFileAtPath:browsePath]) {
        [self.discoverBtn setEnabled:YES];
        [self.discoverBtn setTitle:@"Discover"];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Discovery Error"];
        [alert setInformativeText:@"avahi-browse not found. Please install avahi-utils."];
        // Non-blocking: present as a sheet attached to the Preferences window if possible
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.window) {
                [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
                    // no-op
                }];
            } else {
                // Fallback to runModal if no window available (rare)
                [alert runModal];
            }
        });
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:browsePath];
        [task setArguments:@[@"-t", @"-r", @"_sip._udp"]];
        
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self parseAvahiOutput:output];
            [self.discoverBtn setEnabled:YES];
            [self.discoverBtn setTitle:@"Discover"];
        });
    });
}

- (void)parseAvahiOutput:(NSString *)output {
    // Example output from avahi-browse -t -r _sip._udp:
    // = eth0 IPv4 Asterisk                                    SIP Call Manager     local
    //   hostname = [asterisk.local]
    //   address = [192.168.0.100]
    //   port = [5060]
    
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line containsString:@"address = ["]) {
            NSRange r1 = [line rangeOfString:@"["];
            NSRange r2 = [line rangeOfString:@"]"];
            if (r1.location != NSNotFound && r2.location != NSNotFound) {
                NSString *addr = [line substringWithRange:NSMakeRange(r1.location + 1, r2.location - r1.location - 1)];
                [self.serverField setStringValue:addr]; // Just take the first one for now
                break;
            }
        }
    }
}

@end
