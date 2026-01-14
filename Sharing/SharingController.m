/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sharing Controller Implementation
 */

#import "SharingController.h"
#import <sys/utsname.h>
#import <arpa/inet.h>
#import <ifaddrs.h>

@implementation SharingController

- (id)init
{
    self = [super init];
    if (self) {
        sshEnabled = NO;
        vncEnabled = NO;
        currentHostname = nil;
        
        // Find helper path
        NSString *systemLibrary = @"/System/Library";
        helperPath = [[systemLibrary stringByAppendingPathComponent:@"Tools/sharing-helper"] retain];
        
        NSLog(@"SharingController: Initialized with helper path: %@", helperPath);
    }
    return self;
}

- (void)dealloc
{
    [hostnameField release];
    [applyHostnameButton release];
    [hostnameStatusLabel release];
    [sshCheckbox release];
    [vncCheckbox release];
    [sshStatusLabel release];
    [vncStatusLabel release];
    [sshInfoLabel release];
    [vncInfoLabel release];
    [currentHostname release];
    [helperPath release];
    [super dealloc];
}

#pragma mark - Helper Execution

- (NSString *)runHelper:(NSString *)command
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:helperPath]) {
        NSLog(@"SharingController: Helper not found at %@", helperPath);
        return nil;
    }
    
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    
    [task setLaunchPath:helperPath];
    [task setArguments:[NSArray arrayWithObject:command]];
    [task setStandardOutput:pipe];
    [task setStandardError:errorPipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    NSFileHandle *errorFile = [errorPipe fileHandleForReading];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [file readDataToEndOfFile];
        NSData *errorData = [errorFile readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        
        int status = [task terminationStatus];
        
        if (status != 0) {
            NSLog(@"SharingController: Helper command '%@' failed with status %d: %@", 
                  command, status, errorOutput);
        }
        
        [errorOutput release];
        [task release];
        
        return [output autorelease];
    } @catch (NSException *exception) {
        NSLog(@"SharingController: Exception running helper: %@", exception);
        [task release];
        return nil;
    }
}

- (BOOL)runHelperWithSudo:(NSString *)command
{
    // Use sudo -A -E to prompt for password if needed
    // -A uses SUDO_ASKPASS for graphical password prompt (if set in environment)
    // -E preserves environment
    NSString *fullCommand = [NSString stringWithFormat:@"sudo -A -E %@ %@", helperPath, command];
    
    // Use NSTask with /bin/sh to run the sudo command
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:[NSArray arrayWithObjects:@"-c", fullCommand, nil]];
    [task setStandardOutput:pipe];
    [task setStandardError:errorPipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        int status = [task terminationStatus];
        
        if (status != 0) {
            NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
            NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            NSLog(@"SharingController: Command failed with status %d: %@\nError: %@", status, command, errorOutput);
            [errorOutput release];
        } else {
            NSLog(@"SharingController: Successfully executed: %@", command);
        }
        
        [task release];
        return (status == 0);
    } @catch (NSException *exception) {
        NSLog(@"SharingController: Exception running sudo command: %@", exception);
        [task release];
        return NO;
    }
}

#pragma mark - Status Queries

- (NSString *)getHostname
{
    NSString *output = [self runHelper:@"get-hostname"];
    if (output) {
        return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    
    // Fallback to uname
    struct utsname buf;
    if (uname(&buf) == 0) {
        return [NSString stringWithUTF8String:buf.nodename];
    }
    
    return @"localhost";
}

- (BOOL)getSSHStatus
{
    NSString *output = [self runHelper:@"ssh-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getVNCStatus
{
    NSString *output = [self runHelper:@"vnc-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (NSString *)getLocalIPAddress
{
    NSMutableString *addresses = [NSMutableString string];
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            // Defensive: ifa_addr can be NULL on some systems
            if (temp_addr->ifa_addr != NULL && temp_addr->ifa_addr->sa_family == AF_INET) {
                // Skip loopback
                if (strcmp(temp_addr->ifa_name, "lo") != 0 &&
                    strcmp(temp_addr->ifa_name, "lo0") != 0) {
                    char addressBuffer[INET_ADDRSTRLEN];
                    const void *addr = &((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr;
                    if (inet_ntop(AF_INET, addr, addressBuffer, sizeof(addressBuffer)) != NULL) {
                        if ([addresses length] > 0) {
                            [addresses appendString:@", "];
                        }
                        [addresses appendString:[NSString stringWithUTF8String:addressBuffer]];
                    } else {
                        NSLog(@"SharingController: inet_ntop failed for interface %s", temp_addr->ifa_name);
                    }
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    return [addresses length] > 0 ? addresses : @"No network connection";
}

#pragma mark - Actions

- (void)applyHostname:(id)sender
{
    NSString *newHostname = [hostnameField stringValue];
    
    // Validate hostname
    if ([newHostname length] == 0) {
        NSRunAlertPanel(@"Invalid Hostname", 
                       @"Hostname cannot be empty.", 
                       @"OK", nil, nil);
        return;
    }
    
    // Basic hostname validation (RFC 1123)
    NSCharacterSet *allowedChars = [NSCharacterSet characterSetWithCharactersInString:
                                   @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:newHostname];
    
    if (![allowedChars isSupersetOfSet:inputChars] || 
        [newHostname hasPrefix:@"-"] || 
        [newHostname hasSuffix:@"-"] ||
        [newHostname length] > 63) {
        NSRunAlertPanel(@"Invalid Hostname", 
                       @"Hostname must contain only letters, numbers, and hyphens, "
                       @"cannot start or end with a hyphen, and must be 63 characters or less.", 
                       @"OK", nil, nil);
        return;
    }
    
    NSLog(@"SharingController: Setting hostname to: %@", newHostname);
    
    NSString *command = [NSString stringWithFormat:@"set-hostname %@", newHostname];
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        [hostnameStatusLabel setStringValue:@"Hostname updated successfully"];
        [hostnameStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];
        ASSIGN(currentHostname, newHostname);
        NSLog(@"SharingController: Hostname changed to %@", newHostname);
        
        // Clear status after 3 seconds
        [self performSelector:@selector(clearHostnameStatus) withObject:nil afterDelay:3.0];
    } else {
        [hostnameStatusLabel setStringValue:@"Failed to update hostname"];
        [hostnameStatusLabel setTextColor:[NSColor redColor]];
    }
}

- (void)clearHostnameStatus
{
    [hostnameStatusLabel setStringValue:@""];
}

- (void)toggleSSH:(id)sender
{
    BOOL shouldEnable = [sshCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"ssh-start" : @"ssh-stop";
    
    NSLog(@"SharingController: %@ SSH", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        sshEnabled = shouldEnable;
        [self refreshStatus:nil];
        NSLog(@"SharingController: SSH %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [sshCheckbox setState:sshEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"SSH Error", 
                       @"Failed to modify SSH service. Check system logs for details.", 
                       @"OK", nil, nil);
    }
}

- (void)toggleVNC:(id)sender
{
    BOOL shouldEnable = [vncCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"vnc-start" : @"vnc-stop";
    
    NSLog(@"SharingController: %@ VNC", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        vncEnabled = shouldEnable;
        [self refreshStatus:nil];
        NSLog(@"SharingController: VNC %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [vncCheckbox setState:vncEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"VNC Error", 
                       @"Failed to modify VNC service. Check system logs for details.", 
                       @"OK", nil, nil);
    }
}

- (void)refreshStatus:(id)sender
{
    NSLog(@"SharingController: Refreshing service status");
    
    // Update hostname
    NSString *hostname = [self getHostname];
    [hostnameField setStringValue:hostname];
    ASSIGN(currentHostname, hostname);
    
    // Update SSH status
    sshEnabled = [self getSSHStatus];
    [sshCheckbox setState:sshEnabled ? NSOnState : NSOffState];
    
    if (sshEnabled) {
        [sshStatusLabel setStringValue:@"On"];
        [sshStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];
        
        NSString *ipAddress = [self getLocalIPAddress];
        NSString *info = [NSString stringWithFormat:@"To connect: ssh user@%@", ipAddress];
        [sshInfoLabel setStringValue:info];
        [sshInfoLabel setHidden:NO];
    } else {
        [sshStatusLabel setStringValue:@"Off"];
        [sshStatusLabel setTextColor:[NSColor grayColor]];
        [sshInfoLabel setHidden:YES];
    }
    
    // Update VNC status
    vncEnabled = [self getVNCStatus];
    [vncCheckbox setState:vncEnabled ? NSOnState : NSOffState];
    
    if (vncEnabled) {
        [vncStatusLabel setStringValue:@"On"];
        [vncStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];
        
        NSString *ipAddress = [self getLocalIPAddress];
        NSString *info = [NSString stringWithFormat:@"To connect: %@ (port 5900)", ipAddress];
        [vncInfoLabel setStringValue:info];
        [vncInfoLabel setHidden:NO];
    } else {
        [vncStatusLabel setStringValue:@"Off"];
        [vncStatusLabel setTextColor:[NSColor grayColor]];
        [vncInfoLabel setHidden:YES];
    }
}

#pragma mark - UI Creation

- (NSView *)createMainView
{
    NSView *mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 595, 400)];
    [mainView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    CGFloat yPos = 360;
    CGFloat leftMargin = 20;
    CGFloat rightMargin = 20;
    CGFloat width = 595 - leftMargin - rightMargin;
    
    // Computer Name Section
    NSBox *hostnameBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, yPos - 80, width, 80)];
    [hostnameBox setTitle:@"Computer Name"];
    [hostnameBox setTitlePosition:NSAtTop];
    
    NSView *hostnameContentView = [hostnameBox contentView];
    CGFloat boxWidth = [hostnameContentView bounds].size.width;
    
    NSTextField *hostnameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 40, 100, 20)];
    [hostnameLabel setStringValue:@"Name:"];
    [hostnameLabel setBezeled:NO];
    [hostnameLabel setDrawsBackground:NO];
    [hostnameLabel setEditable:NO];
    [hostnameLabel setSelectable:NO];
    [hostnameContentView addSubview:hostnameLabel];
    [hostnameLabel release];
    
    hostnameField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 40, boxWidth - 240, 22)];
    [hostnameField setStringValue:@""];
    [hostnameContentView addSubview:hostnameField];
    
    applyHostnameButton = [[NSButton alloc] initWithFrame:NSMakeRect(boxWidth - 110, 38, 100, 24)];
    [applyHostnameButton setTitle:@"Apply"];
    [applyHostnameButton setTarget:self];
    [applyHostnameButton setAction:@selector(applyHostname:)];
    [applyHostnameButton setBezelStyle:NSRoundedBezelStyle];
    [hostnameContentView addSubview:applyHostnameButton];
    
    hostnameStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 10, boxWidth - 240, 20)];
    [hostnameStatusLabel setStringValue:@""];
    [hostnameStatusLabel setBezeled:NO];
    [hostnameStatusLabel setDrawsBackground:NO];
    [hostnameStatusLabel setEditable:NO];
    [hostnameStatusLabel setSelectable:NO];
    [hostnameStatusLabel setFont:[NSFont systemFontOfSize:11]];
    [hostnameContentView addSubview:hostnameStatusLabel];
    
    [mainView addSubview:hostnameBox];
    [hostnameBox release];
    
    yPos -= 100;
    
    // Services Section
    NSBox *servicesBox = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, yPos - 200, width, 200)];
    [servicesBox setTitle:@"Services"];
    [servicesBox setTitlePosition:NSAtTop];
    
    NSView *servicesContentView = [servicesBox contentView];
    CGFloat servicesBoxWidth = [servicesContentView bounds].size.width;
    
    CGFloat serviceYPos = 150;
    
    // SSH Service
    sshCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(10, serviceYPos, 200, 20)];
    [sshCheckbox setTitle:@"Remote Login (SSH)"];
    [sshCheckbox setButtonType:NSSwitchButton];
    [sshCheckbox setTarget:self];
    [sshCheckbox setAction:@selector(toggleSSH:)];
    [servicesContentView addSubview:sshCheckbox];
    
    sshStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(220, serviceYPos, 60, 20)];
    [sshStatusLabel setStringValue:@"Off"];
    [sshStatusLabel setBezeled:NO];
    [sshStatusLabel setDrawsBackground:NO];
    [sshStatusLabel setEditable:NO];
    [sshStatusLabel setSelectable:NO];
    [sshStatusLabel setFont:[NSFont boldSystemFontOfSize:12]];
    [sshStatusLabel setTextColor:[NSColor grayColor]];
    [servicesContentView addSubview:sshStatusLabel];
    
    sshInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(30, serviceYPos - 25, servicesBoxWidth - 40, 20)];
    [sshInfoLabel setStringValue:@""];
    [sshInfoLabel setBezeled:NO];
    [sshInfoLabel setDrawsBackground:NO];
    [sshInfoLabel setEditable:NO];
    [sshInfoLabel setSelectable:YES];
    [sshInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [sshInfoLabel setTextColor:[NSColor darkGrayColor]];
    [sshInfoLabel setHidden:YES];
    [servicesContentView addSubview:sshInfoLabel];
    
    serviceYPos -= 70;
    
    // VNC Service
    vncCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(10, serviceYPos, 200, 20)];
    [vncCheckbox setTitle:@"Screen Sharing (VNC)"];
    [vncCheckbox setButtonType:NSSwitchButton];
    [vncCheckbox setTarget:self];
    [vncCheckbox setAction:@selector(toggleVNC:)];
    [servicesContentView addSubview:vncCheckbox];
    
    vncStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(220, serviceYPos, 60, 20)];
    [vncStatusLabel setStringValue:@"Off"];
    [vncStatusLabel setBezeled:NO];
    [vncStatusLabel setDrawsBackground:NO];
    [vncStatusLabel setEditable:NO];
    [vncStatusLabel setSelectable:NO];
    [vncStatusLabel setFont:[NSFont boldSystemFontOfSize:12]];
    [vncStatusLabel setTextColor:[NSColor grayColor]];
    [servicesContentView addSubview:vncStatusLabel];
    
    vncInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(30, serviceYPos - 25, servicesBoxWidth - 40, 20)];
    [vncInfoLabel setStringValue:@""];
    [vncInfoLabel setBezeled:NO];
    [vncInfoLabel setDrawsBackground:NO];
    [vncInfoLabel setEditable:NO];
    [vncInfoLabel setSelectable:YES];
    [vncInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [vncInfoLabel setTextColor:[NSColor darkGrayColor]];
    [vncInfoLabel setHidden:YES];
    [servicesContentView addSubview:vncInfoLabel];
    
    [mainView addSubview:servicesBox];
    [servicesBox release];
    
    // Don't call refreshStatus here - it will be called in mainViewDidLoad
    // when the pane is actually displayed
    
    return [mainView autorelease];
}

@end
