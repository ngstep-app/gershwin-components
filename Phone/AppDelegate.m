/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "SIPManager.h"
#import "PreferencesController.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Setup Menu
	NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
	
	// App Menu
	NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"Phone" action:NULL keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Phone"];
	[appMenuItem setSubmenu:appMenu];
	[mainMenu addItem:appMenuItem];
	
	[appMenu addItemWithTitle:@"About Phone" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItemWithTitle:@"Preferences..." action:@selector(showPreferences:) keyEquivalent:@","];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Quit Phone" action:@selector(terminate:) keyEquivalent:@"q"];
	
    // Edit Menu (Standard)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];
    
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

	[NSApp setMainMenu:mainMenu];

	// Initialize SIP Manager
	self.sipManager = [[SIPManager alloc] init];
	[self.sipManager start];

	// Show Main Window
	self.mainWindowController = [[MainWindowController alloc] initWithSIPManager:self.sipManager];
	[self.mainWindowController showWindow:self];

	// Auto-open Preferences only when there is no SIP config
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *username = [defaults stringForKey:@"SIPUsername"];
	NSString *server = [defaults stringForKey:@"SIPServer"];
	if ((username == nil || username.length == 0) || (server == nil || server.length == 0)) {
		NSLog(@"AppDelegate: No SIP config found, opening Preferences");
		[self showPreferences:nil];
	}
}

- (void)showPreferences:(id)sender
{
    NSLog(@"AppDelegate: showPreferences called");
	[[PreferencesController sharedController] showWindow:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Close any active alerts cleanly before stopping SIP to avoid race conditions
    if (self.mainWindowController) {
        [self.mainWindowController closeActiveAlert];
    }
    // Give UI a moment to close the sheet
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self.sipManager stop];
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end
