/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTextView.h>
#import <Foundation/NSNetServices.h>

@interface NetworkBrowser : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
  NSWindow *window;
  NSTableView *typesTable;
  NSTableView *servicesTable;
  NSTextView *detailsText;
  NSNetServiceBrowser *typeBrowser;
  NSNetServiceBrowser *serviceBrowser;
  NSMutableArray *types;
  NSMutableArray *services;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApp;
- (void)windowWillClose:(NSNotification *)aNotification;

@end
