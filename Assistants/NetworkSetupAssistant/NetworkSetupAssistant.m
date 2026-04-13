/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>
#import <GSAssistantUtilities.h>
#import "NetworkSetupSteps.h"

@interface NetworkSetupAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation NetworkSetupAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    NSDebugLLog(@"gwcomp", @"NetworkSetupAssistant: Last window closed, terminating application");
    return YES;
}
@end

@interface NetworkSetupDelegate : NSObject <GSAssistantWindowDelegate>
@end

@implementation NetworkSetupDelegate

- (void)assistantWindowWillFinish:(GSAssistantWindow *)window {
    NSDebugLLog(@"gwcomp", @"Network setup assistant will finish");
}

- (void)assistantWindowDidFinish:(GSAssistantWindow *)window {
    NSDebugLLog(@"gwcomp", @"Network setup assistant finished");
    [NSApp terminate:nil];
}

- (BOOL)assistantWindow:(GSAssistantWindow *)window shouldCancelWithConfirmation:(BOOL)showConfirmation {
    if (showConfirmation) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cancel Network Setup?";
        alert.informativeText = @"Are you sure you want to cancel the network setup?";
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel Setup", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Continue Setup", @"")];
        alert.alertStyle = NSWarningAlertStyle;
        
        NSModalResponse response = [alert runModal];
        return response == NSAlertFirstButtonReturn;
    }
    return YES;
}

@end

@interface NetworkSetupAssistant : NSObject
+ (void)showNetworkAssistant;
@end

@implementation NetworkSetupAssistant

+ (void)showNetworkAssistant {
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Starting showNetworkAssistant");
    NetworkSetupDelegate *delegate = [[NetworkSetupDelegate alloc] init];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Created delegate: %@", delegate);
    
    // Build the assistant using the builder
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating builder...");
    GSAssistantBuilder *builder = [GSAssistantBuilder builder];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Created builder: %@", builder);
    
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Setting title...");
    [builder withTitle:NSLocalizedString(@"Network Setup Assistant", @"")];
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Setting icon...");
    [builder withIcon:[NSImage imageNamed:@"NSApplicationIcon"]];
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Adding network config step...");
    NSNetworkConfigStep *networkConfigStep = [[NSNetworkConfigStep alloc] init];
    [builder addStep:networkConfigStep];
    [networkConfigStep release];
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Adding auth config step...");
    NSAuthConfigStep *authConfigStep = [[NSAuthConfigStep alloc] init];
    [builder addStep:authConfigStep];
    [authConfigStep release];
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Adding progress step...");
    [builder addProgressStep:@"Applying Network Settings" 
           description:@"Configuring network interfaces..."];
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Adding completion step...");
    [builder addCompletionWithMessage:@"Network setup completed successfully! Your network is now configured." 
           success:YES];
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Building assistant...");
    GSAssistantWindow *assistant = [builder build];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Built assistant: %@", assistant);
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Setting delegate...");
    assistant.delegate = delegate;
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Showing window...");
    [assistant showWindow:nil];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Making window key and front...");
    [assistant.window makeKeyAndOrderFront:nil];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Assistant window should now be visible");
}

+ (NSView *)createNetworkConfigView {
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating network config view container...");
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Container created with frame: %@", NSStringFromRect(container.frame));
    
    // Interface selection
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating interface label...");
    NSTextField *interfaceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 260, 100, 20)];
    interfaceLabel.editable = NO;
    interfaceLabel.selectable = NO;
    interfaceLabel.bordered = NO;
    interfaceLabel.bezeled = NO;
    interfaceLabel.drawsBackground = NO;
    interfaceLabel.backgroundColor = [NSColor clearColor];
    interfaceLabel.stringValue = @"Interface:";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Interface label created: %@", interfaceLabel);
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating interface popup...");
    NSPopUpButton *interfacePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 258, 200, 24)];
    [interfacePopup addItemWithTitle:NSLocalizedString(@"Ethernet (eth0)", @"")];
    [interfacePopup addItemWithTitle:NSLocalizedString(@"Wi-Fi (wlan0)", @"")];
    [interfacePopup addItemWithTitle:NSLocalizedString(@"Loopback (lo)", @"")];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Interface popup created: %@", interfacePopup);
    
    // IP configuration
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating IP config label...");
    NSTextField *ipLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 220, 100, 20)];
    ipLabel.editable = NO;
    ipLabel.selectable = NO;
    ipLabel.bordered = NO;
    ipLabel.bezeled = NO;
    ipLabel.drawsBackground = NO;
    ipLabel.backgroundColor = [NSColor clearColor];
    ipLabel.stringValue = @"IP Address:";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] IP label created: %@", ipLabel);
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating IP field...");
    NSTextField *ipField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 220, 200, 22)];
    ipField.placeholderString = @"192.168.1.100";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] IP field created: %@", ipField);
    
    // Add all subviews
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Adding subviews to container...");
    [container addSubview:interfaceLabel];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added interface label");
    [container addSubview:interfacePopup];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added interface popup");
    [container addSubview:ipLabel];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added IP label");
    [container addSubview:ipField];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added IP field");
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Container now has %lu subviews", (unsigned long)container.subviews.count);
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Network config view creation complete");
    
    return container;
}

+ (NSView *)createWiFiSelectionView {
    NSView *container = [[NSView alloc] init];
    
    // WiFi network selection
    NSTextField *networkLabel = [GSAssistantUIHelper createTitleLabelWithText:@"Available Networks:"];
    NSPopUpButton *networkPopup = [GSAssistantUIHelper createPopUpButtonWithItems:@[
        @"Home-WiFi", @"Office-Guest", @"CoffeeShop-Free", @"MyNetwork-5G", @"Other..."
    ]];
    
    // WiFi password
    NSTextField *passwordLabel = [GSAssistantUIHelper createTitleLabelWithText:@"Password:"];
    NSSecureTextField *passwordField = [GSAssistantUIHelper createSecureFieldWithPlaceholder:@"Network password"];
    
    // Security type
    NSTextField *securityLabel = [GSAssistantUIHelper createTitleLabelWithText:@"Security:"];
    NSPopUpButton *securityPopup = [GSAssistantUIHelper createPopUpButtonWithItems:@[
        @"WPA2/WPA3 Personal", @"WPA Personal", @"WEP", @"None (Open)"
    ]];
    
    // Advanced options
    NSButton *advancedCheck = [GSAssistantUIHelper createCheckboxWithTitle:NSLocalizedString(@"Show advanced options", @"")];
    NSButton *rememberCheck = [GSAssistantUIHelper createCheckboxWithTitle:NSLocalizedString(@"Remember this network", @"")];
    [rememberCheck setState:NSOnState];
    
    // Create layout
    NSArray *views = @[networkLabel, networkPopup, passwordLabel, passwordField, 
                      securityLabel, securityPopup, advancedCheck, rememberCheck];
    NSView *stackView = [GSAssistantUIHelper createVerticalStackViewWithViews:views spacing:8.0];
    
    [container addSubview:stackView];
    [GSAssistantUIHelper addStandardConstraintsToView:stackView inContainer:container];
    
    return container;
}

+ (NSView *)createAuthConfigView {
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating auth config view container...");
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Container created with frame: %@", NSStringFromRect(container.frame));
    
    // Username field
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating username label...");
    NSTextField *usernameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 260, 100, 20)];
    usernameLabel.editable = NO;
    usernameLabel.selectable = NO;
    usernameLabel.bordered = NO;
    usernameLabel.bezeled = NO;
    usernameLabel.drawsBackground = NO;
    usernameLabel.backgroundColor = [NSColor clearColor];
    usernameLabel.stringValue = @"Username:";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Username label created: %@", usernameLabel);
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating username field...");
    NSTextField *usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 260, 200, 22)];
    usernameField.placeholderString = @"Enter network username";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Username field created: %@", usernameField);
    
    // Password field
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating password label...");
    NSTextField *passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 220, 100, 20)];
    passwordLabel.editable = NO;
    passwordLabel.selectable = NO;
    passwordLabel.bordered = NO;
    passwordLabel.bezeled = NO;
    passwordLabel.drawsBackground = NO;
    passwordLabel.backgroundColor = [NSColor clearColor];
    passwordLabel.stringValue = @"Password:";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Password label created: %@", passwordLabel);
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Creating password field...");
    NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(130, 220, 200, 22)];
    passwordField.placeholderString = @"Enter network password";
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Password field created: %@", passwordField);
    
    // Add all subviews
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Adding subviews to container...");
    [container addSubview:usernameLabel];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added username label");
    [container addSubview:usernameField];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added username field");
    [container addSubview:passwordLabel];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added password label");
    [container addSubview:passwordField];
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Added password field");
    
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Container now has %lu subviews", (unsigned long)container.subviews.count);
    NSDebugLLog(@"gwcomp", @"[NetworkSetupAssistant] Auth config view creation complete");
    
    return container;
}
@end

// Main application entry point
int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        
        // Set up application delegate to ensure proper termination
        NetworkSetupAppDelegate *appDelegate = [[NetworkSetupAppDelegate alloc] init];
        [NSApp setDelegate:appDelegate];
        
        // Create menu bar
        NSMenu *mainMenu = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [mainMenu addItem:appMenuItem];
        [NSApp setMainMenu:mainMenu];
        
        NSMenu *appMenu = [[NSMenu alloc] init];
        NSMenuItem *quitMenuItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenu addItem:quitMenuItem];
        [appMenuItem setSubmenu:appMenu];
        
        // Show the assistant immediately
        [NetworkSetupAssistant showNetworkAssistant];
        
        [NSApp run];
        
        [appDelegate release];
    }
    return 0;
}
