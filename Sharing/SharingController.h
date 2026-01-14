/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sharing Controller - Manages UI and service control
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface SharingController : NSObject
{
    // Hostname section
    NSTextField *hostnameField;
    NSButton *applyHostnameButton;
    NSTextField *hostnameStatusLabel;
    
    // Service checkboxes
    NSButton *sshCheckbox;
    NSButton *vncCheckbox;
    
    // Status labels
    NSTextField *sshStatusLabel;
    NSTextField *vncStatusLabel;
    
    // Information displays
    NSTextField *sshInfoLabel;
    NSTextField *vncInfoLabel;
    
    // Current status
    BOOL sshEnabled;
    BOOL vncEnabled;
    NSString *currentHostname;
    
    // Path to helper
    NSString *helperPath;
}

- (NSView *)createMainView;
- (void)refreshStatus:(id)sender;
- (void)applyHostname:(id)sender;
- (void)toggleSSH:(id)sender;
- (void)toggleVNC:(id)sender;

@end
