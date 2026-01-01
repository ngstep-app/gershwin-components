/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PrintersController.h"
#include <cups/cups.h>
#include <cups/adminutil.h>
#include <cups/ppd.h>
#include <unistd.h>
#include <grp.h>
#include <pwd.h>

#pragma mark - PrinterInfo Implementation

@implementation PrinterInfo

@synthesize name, displayName, location, makeModel, deviceURI, state;
@synthesize isDefault, isShared, acceptingJobs, jobCount;

- (id)init
{
    self = [super init];
    if (self) {
        name = nil;
        displayName = nil;
        location = nil;
        makeModel = nil;
        deviceURI = nil;
        state = nil;
        isDefault = NO;
        isShared = NO;
        acceptingJobs = YES;
        jobCount = 0;
    }
    return self;
}

- (void)dealloc
{
    [name release];
    [displayName release];
    [location release];
    [makeModel release];
    [deviceURI release];
    [state release];
    [super dealloc];
}

@end

#pragma mark - PrintJobInfo Implementation

@implementation PrintJobInfo

@synthesize jobId, printerName, title, user, state, size, creationTime;

- (id)init
{
    self = [super init];
    if (self) {
        jobId = 0;
        printerName = nil;
        title = nil;
        user = nil;
        state = nil;
        size = 0;
        creationTime = nil;
    }
    return self;
}

- (void)dealloc
{
    [printerName release];
    [title release];
    [user release];
    [state release];
    [creationTime release];
    [super dealloc];
}

@end

#pragma mark - DiscoveredDevice Implementation

@implementation DiscoveredDevice

@synthesize deviceClass, deviceId, deviceInfo, deviceMakeModel, deviceURI, deviceLocation;

- (id)init
{
    self = [super init];
    if (self) {
        deviceClass = nil;
        deviceId = nil;
        deviceInfo = nil;
        deviceMakeModel = nil;
        deviceURI = nil;
        deviceLocation = nil;
    }
    return self;
}

- (void)dealloc
{
    [deviceClass release];
    [deviceId release];
    [deviceInfo release];
    [deviceMakeModel release];
    [deviceURI release];
    [deviceLocation release];
    [super dealloc];
}

@end

#pragma mark - Device Discovery Callback

// Context for device discovery callback
typedef struct {
    NSMutableArray *devices;
    PrintersController *controller;
} DeviceCallbackContext;

// Callback function for cupsGetDevices (CUPS 1.4+)
static void deviceCallback(const char *device_class,
                          const char *device_id,
                          const char *device_info,
                          const char *device_make_and_model,
                          const char *device_uri,
                          const char *device_location,
                          void *user_data)
{
    DeviceCallbackContext *ctx = (DeviceCallbackContext *)user_data;
    
    if (!ctx || !ctx->devices) {
        return;
    }
    
    DiscoveredDevice *device = [[DiscoveredDevice alloc] init];
    
    if (device_class) {
        [device setDeviceClass:[NSString stringWithUTF8String:device_class]];
    }
    if (device_id) {
        [device setDeviceId:[NSString stringWithUTF8String:device_id]];
    }
    if (device_info) {
        [device setDeviceInfo:[NSString stringWithUTF8String:device_info]];
    }
    if (device_make_and_model) {
        [device setDeviceMakeModel:[NSString stringWithUTF8String:device_make_and_model]];
    }
    if (device_uri) {
        [device setDeviceURI:[NSString stringWithUTF8String:device_uri]];
    }
    if (device_location) {
        [device setDeviceLocation:[NSString stringWithUTF8String:device_location]];
    }
    
    [ctx->devices addObject:device];
    [device release];
    
    NSLog(@"[Printers] Discovered device: %s (%s)", device_info, device_uri);
}

#pragma mark - PrintersController Implementation

@implementation PrintersController

- (id)init
{
    self = [super init];
    if (self) {
        printers = [[NSMutableArray alloc] init];
        jobs = [[NSMutableArray alloc] init];
        discoveredDevices = [[NSMutableArray alloc] init];
        selectedPrinter = nil;
        selectedJob = nil;
        isDiscovering = NO;
        
        // Check if CUPS is available
        cupsAvailable = [self isCupsAvailable];
        NSLog(@"[Printers] Controller initialized, CUPS available: %@", cupsAvailable ? @"YES" : @"NO");
        
        // Check if user is in lpadmin group
        userInLpadminGroup = [self isUserInLpadminGroup];
        NSLog(@"[Printers] User in lpadmin group: %@", userInLpadminGroup ? @"YES" : @"NO");
    }
    return self;
}

- (void)dealloc
{
    [printers release];
    [jobs release];
    [discoveredDevices release];
    [mainView release];
    [printerTable release];
    [jobTable release];
    [printerScroll release];
    [jobScroll release];
    [addButton release];
    [removeButton release];
    [defaultButton release];
    [optionsButton release];
    [cancelJobButton release];
    [pauseJobButton release];
    [statusLabel release];
    [printerInfoLabel release];
    [privilegeWarningLabel release];
    [addPrinterPanel release];
    [deviceTable release];
    [deviceScroll release];
    [printerNameField release];
    [printerLocationField release];
    [driverPopup release];
    [discoverButton release];
    [discoverProgress release];
    [super dealloc];
}

- (BOOL)isCupsAvailable
{
    // Try to connect to CUPS server
    http_t *http = httpConnect2(cupsServer(), ippPort(), NULL, AF_UNSPEC,
                                cupsEncryption(), 1, 30000, NULL);
    if (http) {
        httpClose(http);
        return YES;
    }
    return NO;
}

- (BOOL)isUserInLpadminGroup
{
    // Get current user's UID
    uid_t uid = getuid();
    
    // Get user info
    struct passwd *pwd = getpwuid(uid);
    if (!pwd) {
        NSLog(@"[Printers] Warning: Could not get user info for UID %d", uid);
        return NO;
    }
    
    // Get lpadmin group info
    struct group *grp = getgrnam("lpadmin");
    if (!grp) {
        NSLog(@"[Printers] Warning: lpadmin group not found on system");
        return NO;
    }
    
    // Get all groups for current user
    int ngroups = 0;
    gid_t *groups = NULL;
    
    if (getgroups(0, NULL) > 0) {
        ngroups = getgroups(0, NULL);
        groups = malloc(ngroups * sizeof(gid_t));
        getgroups(ngroups, groups);
    }
    
    // Check if lpadmin group is in user's groups
    BOOL found = NO;
    gid_t lpadmin_gid = grp->gr_gid;
    
    for (int i = 0; i < ngroups; i++) {
        if (groups[i] == lpadmin_gid) {
            found = YES;
            break;
        }
    }
    
    if (groups) {
        free(groups);
    }
    
    return found;
}

- (void)showPrivilegeWarningIfNeeded
{
    if (!userInLpadminGroup && cupsAvailable) {
        NSString *username = [NSString stringWithUTF8String:getenv("USER") ?: "current user"];
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Insufficient Privileges"];
        [alert setInformativeText:[NSString stringWithFormat:
            @"You are not a member of the 'lpadmin' group.\n\n"
            @"To manage printers, run this command and then log out and back in:\n\n"
            @"sudo usermod -a -G lpadmin %@",
            username]];
        [alert addButtonWithTitle:@"OK"];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
    }
}

- (NSView *)createMainView
{
    if (mainView) {
        return mainView;
    }
    
    mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 380)];
    
    if (!cupsAvailable) {
        // Show error message if CUPS is not available
        NSTextField *errorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 160, 520, 60)];
        [errorLabel setStringValue:@"Printer configuration is not available.\n"
                                   @"The CUPS printing system is required but was not found.\n"
                                   @"Please install CUPS and restart."];
        [errorLabel setBezeled:NO];
        [errorLabel setDrawsBackground:NO];
        [errorLabel setEditable:NO];
        [errorLabel setSelectable:NO];
        [errorLabel setFont:[NSFont systemFontOfSize:14]];
        [errorLabel setAlignment:NSCenterTextAlignment];
        [mainView addSubview:errorLabel];
        [errorLabel release];
        
        return mainView;
    }
    
    // Add privilege warning banner at the top if user is not in lpadmin group
    int warningHeight = 0;
    if (!userInLpadminGroup) {
        // Create a simple separator line
        NSBox *warningBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 360, 560, 1)];
        [warningBox setBoxType:NSBoxSeparator];
        [mainView addSubview:warningBox];
        [warningBox release];
        
        warningHeight = 25;
        privilegeWarningLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 362, 520, 18)];
        [privilegeWarningLabel setStringValue:@"⚠️  Not in 'lpadmin' group - printer management disabled"];
        [privilegeWarningLabel setBezeled:NO];
        [privilegeWarningLabel setDrawsBackground:NO];
        [privilegeWarningLabel setEditable:NO];
        [privilegeWarningLabel setSelectable:NO];
        [privilegeWarningLabel setFont:[NSFont systemFontOfSize:10]];
        [privilegeWarningLabel setTextColor:[NSColor darkGrayColor]];
        [mainView addSubview:privilegeWarningLabel];
    }
    
    // Printers label
    NSTextField *printersLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 335 - warningHeight, 200, 16)];
    [printersLabel setStringValue:@"Printers"];
    [printersLabel setBezeled:NO];
    [printersLabel setDrawsBackground:NO];
    [printersLabel setEditable:NO];
    [printersLabel setSelectable:NO];
    [printersLabel setFont:[NSFont boldSystemFontOfSize:11]];
    [mainView addSubview:printersLabel];
    [printersLabel release];
    
    // Printer table - takes up more space
    int tableY = 180;
    int tableHeight = 155 - warningHeight;
    printerScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, tableY, 340, tableHeight)];
    [printerScroll setHasVerticalScroller:YES];
    [printerScroll setHasHorizontalScroller:NO];
    [printerScroll setBorderType:NSBezelBorder];
    [printerScroll setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
    [mainView addSubview:printerScroll];
    
    printerTable = [[NSTableView alloc] initWithFrame:[printerScroll bounds]];
    [printerTable setDelegate:self];
    [printerTable setDataSource:self];
    [printerTable setAllowsMultipleSelection:NO];
    [printerTable setAllowsEmptySelection:YES];
    
    NSTableColumn *printerNameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [printerNameColumn setTitle:@"Name"];
    [printerNameColumn setWidth:140];
    [printerNameColumn setEditable:NO];
    [printerTable addTableColumn:printerNameColumn];
    [printerNameColumn release];
    
    NSTableColumn *printerStatusColumn = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    [printerStatusColumn setTitle:@"Status"];
    [printerStatusColumn setWidth:80];
    [printerStatusColumn setEditable:NO];
    [printerTable addTableColumn:printerStatusColumn];
    [printerStatusColumn release];
    
    NSTableColumn *printerJobsColumn = [[NSTableColumn alloc] initWithIdentifier:@"jobs"];
    [printerJobsColumn setTitle:@"Jobs"];
    [printerJobsColumn setWidth:50];
    [printerJobsColumn setEditable:NO];
    [printerTable addTableColumn:printerJobsColumn];
    [printerJobsColumn release];
    
    NSTableColumn *printerDefaultColumn = [[NSTableColumn alloc] initWithIdentifier:@"default"];
    [printerDefaultColumn setTitle:@"Default"];
    [printerDefaultColumn setWidth:50];
    [printerDefaultColumn setEditable:NO];
    [printerTable addTableColumn:printerDefaultColumn];
    [printerDefaultColumn release];
    
    [printerScroll setDocumentView:printerTable];
    
    // Printer buttons - compact 2x2 grid on the right
    int buttonStartY = 335 - warningHeight;
    
    addButton = [[NSButton alloc] initWithFrame:NSMakeRect(370, buttonStartY - 24, 85, 22)];
    [addButton setTitle:@"Add..."];
    [addButton setBezelStyle:NSRoundedBezelStyle];
    [addButton setTarget:self];
    [addButton setAction:@selector(addPrinter:)];
    [mainView addSubview:addButton];
    
    removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(460, buttonStartY - 24, 80, 22)];
    [removeButton setTitle:@"Remove"];
    [removeButton setBezelStyle:NSRoundedBezelStyle];
    [removeButton setTarget:self];
    [removeButton setAction:@selector(removePrinter:)];
    [removeButton setEnabled:NO];
    [mainView addSubview:removeButton];
    
    defaultButton = [[NSButton alloc] initWithFrame:NSMakeRect(370, buttonStartY - 50, 85, 22)];
    [defaultButton setTitle:@"Default"];
    [defaultButton setBezelStyle:NSRoundedBezelStyle];
    [defaultButton setTarget:self];
    [defaultButton setAction:@selector(setDefaultPrinter:)];
    [defaultButton setEnabled:NO];
    [mainView addSubview:defaultButton];
    
    optionsButton = [[NSButton alloc] initWithFrame:NSMakeRect(460, buttonStartY - 50, 80, 22)];
    [optionsButton setTitle:@"Options..."];
    [optionsButton setBezelStyle:NSRoundedBezelStyle];
    [optionsButton setTarget:self];
    [optionsButton setAction:@selector(showPrinterOptions:)];
    [optionsButton setEnabled:NO];
    [mainView addSubview:optionsButton];
    
    // Printer info label
    printerInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(370, buttonStartY - 80, 170, 25)];
    [printerInfoLabel setStringValue:@""];
    [printerInfoLabel setBezeled:NO];
    [printerInfoLabel setDrawsBackground:NO];
    [printerInfoLabel setEditable:NO];
    [printerInfoLabel setSelectable:YES];
    [printerInfoLabel setFont:[NSFont systemFontOfSize:9]];
    [printerInfoLabel setTextColor:[NSColor darkGrayColor]];
    [mainView addSubview:printerInfoLabel];
    
    // Print queue label
    NSTextField *queueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 160, 200, 16)];
    [queueLabel setStringValue:@"Print Queue"];
    [queueLabel setBezeled:NO];
    [queueLabel setDrawsBackground:NO];
    [queueLabel setEditable:NO];
    [queueLabel setSelectable:NO];
    [queueLabel setFont:[NSFont boldSystemFontOfSize:11]];
    [mainView addSubview:queueLabel];
    [queueLabel release];
    
    // Job table - more compact
    jobScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 80, 420, 75)];
    [jobScroll setHasVerticalScroller:YES];
    [jobScroll setHasHorizontalScroller:NO];
    [jobScroll setBorderType:NSBezelBorder];
    [jobScroll setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
    [mainView addSubview:jobScroll];
    
    jobTable = [[NSTableView alloc] initWithFrame:[jobScroll bounds]];
    [jobTable setDelegate:self];
    [jobTable setDataSource:self];
    [jobTable setAllowsMultipleSelection:NO];
    [jobTable setAllowsEmptySelection:YES];
    
    NSTableColumn *jobIdColumn = [[NSTableColumn alloc] initWithIdentifier:@"jobId"];
    [jobIdColumn setTitle:@"ID"];
    [jobIdColumn setWidth:40];
    [jobIdColumn setEditable:NO];
    [jobTable addTableColumn:jobIdColumn];
    [jobIdColumn release];
    
    NSTableColumn *jobTitleColumn = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    [jobTitleColumn setTitle:@"Document"];
    [jobTitleColumn setWidth:180];
    [jobTitleColumn setEditable:NO];
    [jobTable addTableColumn:jobTitleColumn];
    [jobTitleColumn release];
    
    NSTableColumn *jobUserColumn = [[NSTableColumn alloc] initWithIdentifier:@"user"];
    [jobUserColumn setTitle:@"User"];
    [jobUserColumn setWidth:80];
    [jobUserColumn setEditable:NO];
    [jobTable addTableColumn:jobUserColumn];
    [jobUserColumn release];
    
    NSTableColumn *jobStatusColumn = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    [jobStatusColumn setTitle:@"Status"];
    [jobStatusColumn setWidth:80];
    [jobStatusColumn setEditable:NO];
    [jobTable addTableColumn:jobStatusColumn];
    [jobStatusColumn release];
    
    [jobScroll setDocumentView:jobTable];
    
    // Job control buttons - compact
    cancelJobButton = [[NSButton alloc] initWithFrame:NSMakeRect(450, 107, 90, 22)];
    [cancelJobButton setTitle:@"Cancel"];
    [cancelJobButton setBezelStyle:NSRoundedBezelStyle];
    [cancelJobButton setTarget:self];
    [cancelJobButton setAction:@selector(cancelJob:)];
    [cancelJobButton setEnabled:NO];
    [mainView addSubview:cancelJobButton];
    
    pauseJobButton = [[NSButton alloc] initWithFrame:NSMakeRect(450, 82, 90, 22)];
    [pauseJobButton setTitle:@"Hold"];
    [pauseJobButton setBezelStyle:NSRoundedBezelStyle];
    [pauseJobButton setTarget:self];
    [pauseJobButton setAction:@selector(pauseResumeJob:)];
    [pauseJobButton setEnabled:NO];
    [mainView addSubview:pauseJobButton];
    
    // Status label - at bottom
    statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 8, 520, 28)];
    [statusLabel setStringValue:@""];
    [statusLabel setBezeled:NO];
    [statusLabel setDrawsBackground:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setFont:[NSFont systemFontOfSize:9]];
    [statusLabel setTextColor:[NSColor darkGrayColor]];
    [mainView addSubview:statusLabel];
    
    // Disable admin buttons if user is not in lpadmin group
    if (!userInLpadminGroup) {
        [addButton setEnabled:NO];
        [removeButton setEnabled:NO];
        [defaultButton setEnabled:NO];
        [optionsButton setEnabled:NO];
    }
    
    return mainView;
}

#pragma mark - Refresh Methods

- (void)refreshPrinters:(NSTimer *)timer
{
    if (!cupsAvailable) {
        return;
    }
    
    NSLog(@"[Printers] Refreshing printer list...");
    
    // Get all destinations (printers and classes)
    cups_dest_t *dests = NULL;
    int num_dests = cupsGetDests(&dests);
    
    // Store the currently selected printer name
    NSString *selectedName = nil;
    if (selectedPrinter) {
        selectedName = [[selectedPrinter name] retain];
    }
    
    [printers removeAllObjects];
    selectedPrinter = nil;
    
    for (int i = 0; i < num_dests; i++) {
        cups_dest_t *dest = &dests[i];
        PrinterInfo *printer = [[PrinterInfo alloc] init];
        
        [printer setName:[NSString stringWithUTF8String:dest->name]];
        [printer setIsDefault:(dest->is_default != 0)];
        
        // Get printer options
        const char *info = cupsGetOption("printer-info", dest->num_options, dest->options);
        if (info) {
            [printer setDisplayName:[NSString stringWithUTF8String:info]];
        } else {
            [printer setDisplayName:[printer name]];
        }
        
        const char *location = cupsGetOption("printer-location", dest->num_options, dest->options);
        if (location) {
            [printer setLocation:[NSString stringWithUTF8String:location]];
        }
        
        const char *makeModel = cupsGetOption("printer-make-and-model", dest->num_options, dest->options);
        if (makeModel) {
            [printer setMakeModel:[NSString stringWithUTF8String:makeModel]];
        }
        
        const char *uri = cupsGetOption("device-uri", dest->num_options, dest->options);
        if (uri) {
            [printer setDeviceURI:[NSString stringWithUTF8String:uri]];
        }
        
        const char *state = cupsGetOption("printer-state", dest->num_options, dest->options);
        if (state) {
            int stateVal = atoi(state);
            switch (stateVal) {
                case 3: [printer setState:@"Idle"]; break;
                case 4: [printer setState:@"Printing"]; break;
                case 5: [printer setState:@"Stopped"]; break;
                default: [printer setState:@"Unknown"]; break;
            }
        } else {
            [printer setState:@"Unknown"];
        }
        
        const char *accepting = cupsGetOption("printer-is-accepting-jobs", dest->num_options, dest->options);
        if (accepting) {
            [printer setAcceptingJobs:(strcmp(accepting, "true") == 0)];
        }
        
        const char *shared = cupsGetOption("printer-is-shared", dest->num_options, dest->options);
        if (shared) {
            [printer setIsShared:(strcmp(shared, "true") == 0)];
        }
        
        [printers addObject:printer];
        [printer release];
    }
    
    cupsFreeDests(num_dests, dests);
    
    [printerTable reloadData];
    
    // Restore selection if possible
    if (selectedName) {
        for (NSUInteger i = 0; i < [printers count]; i++) {
            PrinterInfo *p = [printers objectAtIndex:i];
            if ([[p name] isEqualToString:selectedName]) {
                // Select the row - this will trigger tableViewSelectionDidChange
                [printerTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                // Also set directly in case delegate isn't called
                selectedPrinter = p;
                break;
            }
        }
        [selectedName release];
    } else {
        // Clear selection if nothing was previously selected
        selectedPrinter = nil;
    }
    
    // Update button states
    [self updateButtonStates];
    
    // Refresh jobs for selected printer
    [self refreshJobs];
    
    // Update status
    NSString *statusText = [NSString stringWithFormat:@"%lu printer(s) available", (unsigned long)[printers count]];
    [statusLabel setStringValue:statusText];
}

- (void)refreshJobs
{
    if (!cupsAvailable) {
        return;
    }
    
    [jobs removeAllObjects];
    selectedJob = nil;
    
    // Get jobs for all printers or selected printer
    const char *printerName = NULL;
    if (selectedPrinter) {
        printerName = [[selectedPrinter name] UTF8String];
    }
    
    cups_job_t *cupsJobs = NULL;
    int numJobs = cupsGetJobs(&cupsJobs, printerName, 0, CUPS_WHICHJOBS_ACTIVE);
    
    for (int i = 0; i < numJobs; i++) {
        cups_job_t *job = &cupsJobs[i];
        PrintJobInfo *jobInfo = [[PrintJobInfo alloc] init];
        
        [jobInfo setJobId:job->id];
        [jobInfo setPrinterName:[NSString stringWithUTF8String:job->dest]];
        [jobInfo setTitle:[NSString stringWithUTF8String:job->title]];
        [jobInfo setUser:[NSString stringWithUTF8String:job->user]];
        [jobInfo setSize:job->size];
        
        // Convert job state
        switch (job->state) {
            case IPP_JOB_PENDING:
                [jobInfo setState:@"Pending"];
                break;
            case IPP_JOB_HELD:
                [jobInfo setState:@"Held"];
                break;
            case IPP_JOB_PROCESSING:
                [jobInfo setState:@"Printing"];
                break;
            case IPP_JOB_STOPPED:
                [jobInfo setState:@"Stopped"];
                break;
            case IPP_JOB_CANCELED:
                [jobInfo setState:@"Canceled"];
                break;
            case IPP_JOB_ABORTED:
                [jobInfo setState:@"Aborted"];
                break;
            case IPP_JOB_COMPLETED:
                [jobInfo setState:@"Completed"];
                break;
            default:
                [jobInfo setState:@"Unknown"];
                break;
        }
        
        // Convert creation time
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:job->creation_time];
        [jobInfo setCreationTime:date];
        
        [jobs addObject:jobInfo];
        [jobInfo release];
    }
    
    cupsFreeJobs(numJobs, cupsJobs);
    
    [jobTable reloadData];
    [self updateJobButtonStates];
    
    // Update job count for selected printer
    if (selectedPrinter) {
        [selectedPrinter setJobCount:(int)[jobs count]];
    }
}

- (void)updateButtonStates
{
    BOOL hasSelection = (selectedPrinter != nil);
    
    [removeButton setEnabled:hasSelection];
    [defaultButton setEnabled:hasSelection && ![selectedPrinter isDefault]];
    [optionsButton setEnabled:hasSelection];
    
    // Update printer info label
    if (selectedPrinter) {
        NSMutableString *info = [NSMutableString string];
        if ([selectedPrinter makeModel]) {
            [info appendString:[selectedPrinter makeModel]];
        }
        if ([selectedPrinter location] && [[selectedPrinter location] length] > 0) {
            if ([info length] > 0) {
                [info appendString:@"\n"];
            }
            [info appendFormat:@"Location: %@", [selectedPrinter location]];
        }
        [printerInfoLabel setStringValue:info];
    } else {
        [printerInfoLabel setStringValue:@""];
    }
}

- (void)updateJobButtonStates
{
    BOOL hasSelection = (selectedJob != nil);
    
    [cancelJobButton setEnabled:hasSelection];
    [pauseJobButton setEnabled:hasSelection];
    
    // Update pause/resume button title
    if (selectedJob && [[selectedJob state] isEqualToString:@"Held"]) {
        [pauseJobButton setTitle:@"Resume"];
    } else {
        [pauseJobButton setTitle:@"Hold Job"];
    }
}

#pragma mark - NSTableView DataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == printerTable) {
        return [printers count];
    } else if (tableView == jobTable) {
        return [jobs count];
    } else if (tableView == deviceTable) {
        return [discoveredDevices count];
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSString *identifier = [tableColumn identifier];
    
    if (tableView == printerTable && row < (NSInteger)[printers count]) {
        PrinterInfo *printer = [printers objectAtIndex:row];
        
        if ([identifier isEqualToString:@"name"]) {
            return [printer displayName];
        } else if ([identifier isEqualToString:@"status"]) {
            return [printer state];
        } else if ([identifier isEqualToString:@"jobs"]) {
            return [NSNumber numberWithInt:[printer jobCount]];
        } else if ([identifier isEqualToString:@"default"]) {
            return [printer isDefault] ? @"✓" : @"";
        }
    } else if (tableView == jobTable && row < (NSInteger)[jobs count]) {
        PrintJobInfo *job = [jobs objectAtIndex:row];
        
        if ([identifier isEqualToString:@"jobId"]) {
            return [NSNumber numberWithInt:[job jobId]];
        } else if ([identifier isEqualToString:@"title"]) {
            return [job title];
        } else if ([identifier isEqualToString:@"user"]) {
            return [job user];
        } else if ([identifier isEqualToString:@"status"]) {
            return [job state];
        }
    } else if (tableView == deviceTable && row < (NSInteger)[discoveredDevices count]) {
        DiscoveredDevice *device = [discoveredDevices objectAtIndex:row];
        
        if ([identifier isEqualToString:@"device"]) {
            NSString *info = [device deviceInfo];
            if (!info || [info length] == 0) {
                info = [device deviceMakeModel];
            }
            return info ? info : @"Unknown Device";
        } else if ([identifier isEqualToString:@"type"]) {
            return [device deviceClass];
        }
    }
    
    return nil;
}

#pragma mark - NSTableView Delegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSTableView *tableView = [notification object];
    
    if (tableView == printerTable) {
        NSInteger row = [printerTable selectedRow];
        if (row >= 0 && row < (NSInteger)[printers count]) {
            selectedPrinter = [printers objectAtIndex:row];
        } else {
            selectedPrinter = nil;
        }
        [self updateButtonStates];
        [self refreshJobs];
    } else if (tableView == jobTable) {
        NSInteger row = [jobTable selectedRow];
        if (row >= 0 && row < (NSInteger)[jobs count]) {
            selectedJob = [jobs objectAtIndex:row];
        } else {
            selectedJob = nil;
        }
        [self updateJobButtonStates];
    } else if (tableView == deviceTable) {
        NSInteger row = [deviceTable selectedRow];
        if (row >= 0 && row < (NSInteger)[discoveredDevices count]) {
            DiscoveredDevice *device = [discoveredDevices objectAtIndex:row];
            // Auto-fill printer name from device info
            NSString *name = [device deviceInfo];
            if (!name || [name length] == 0) {
                name = [device deviceMakeModel];
            }
            if (name) {
                // Sanitize name for printer queue name
                NSString *sanitized = [[name componentsSeparatedByCharactersInSet:
                    [[NSCharacterSet alphanumericCharacterSet] invertedSet]] 
                    componentsJoinedByString:@"_"];
                [printerNameField setStringValue:sanitized];
            }
        }
    }
}

#pragma mark - Printer Actions

- (IBAction)addPrinter:(id)sender
{
    [self showAddPrinterPanel];
}

- (IBAction)removePrinter:(id)sender
{
    if (!selectedPrinter) {
        return;
    }
    
    NSString *printerName = [selectedPrinter name];
    
    // Confirm deletion
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Remove Printer"];
    [alert setInformativeText:[NSString stringWithFormat:@"Are you sure you want to remove the printer \"%@\"?", 
                               [selectedPrinter displayName]]];
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        // Use IPP to delete printer
        http_t *http = httpConnect2(cupsServer(), ippPort(), NULL, AF_UNSPEC,
                                    cupsEncryption(), 1, 30000, NULL);
        
        BOOL success = NO;
        if (http) {
            ipp_t *request = ippNewRequest(IPP_OP_CUPS_DELETE_PRINTER);
            
            char uri[HTTP_MAX_URI];
            httpAssembleURIf(HTTP_URI_CODING_ALL, uri, sizeof(uri), "ipp", NULL,
                            "localhost", 0, "/printers/%s", [printerName UTF8String]);
            ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", NULL, uri);
            ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", NULL, cupsUser());
            
            ipp_t *response = cupsDoRequest(http, request, "/admin/");
            
            if (response) {
                ipp_status_t status = ippGetStatusCode(response);
                if (status == IPP_OK) {
                    success = YES;
                    NSLog(@"[Printers] Removed printer: %@", printerName);
                    [statusLabel setStringValue:[NSString stringWithFormat:@"Printer \"%@\" removed", printerName]];
                } else {
                    NSLog(@"[Printers] Failed to remove printer: %s", ippErrorString(status));
                }
                ippDelete(response);
            }
            
            httpClose(http);
        }
        
        if (!success) {
            NSLog(@"[Printers] Failed to remove printer: %@", printerName);
            [statusLabel setStringValue:@"Failed to remove printer. Add yourself to the 'lpadmin' group to manage printers."];
        }
        
        [self refreshPrinters:nil];
    }
    
    [alert release];
}

- (IBAction)setDefaultPrinter:(id)sender
{
    if (!selectedPrinter) {
        return;
    }
    
    const char *printerName = [[selectedPrinter name] UTF8String];
    
    // Get destinations and set default
    cups_dest_t *dests = NULL;
    int num_dests = cupsGetDests(&dests);
    
    cups_dest_t *dest = cupsGetDest(printerName, NULL, num_dests, dests);
    if (dest) {
        cupsSetDefaultDest(printerName, NULL, num_dests, dests);
        
        NSLog(@"[Printers] Set default printer: %@", [selectedPrinter name]);
        [statusLabel setStringValue:[NSString stringWithFormat:@"\"%@\" is now the default printer", 
                                     [selectedPrinter displayName]]];
    }
    
    cupsFreeDests(num_dests, dests);
    
    [self refreshPrinters:nil];
}

- (IBAction)showPrinterOptions:(id)sender
{
    if (!selectedPrinter) {
        return;
    }
    
    [self showOptionsPanel];
}

- (IBAction)enablePrinter:(id)sender
{
    if (!selectedPrinter) {
        return;
    }
    
    const char *printerName = [[selectedPrinter name] UTF8String];
    
    // Use IPP to enable printer
    http_t *http = httpConnect2(cupsServer(), ippPort(), NULL, AF_UNSPEC,
                                cupsEncryption(), 1, 30000, NULL);
    if (http) {
        ipp_t *request = ippNewRequest(IPP_RESUME_PRINTER);
        
        char uri[HTTP_MAX_URI];
        httpAssembleURIf(HTTP_URI_CODING_ALL, uri, sizeof(uri), "ipp", NULL,
                        "localhost", 0, "/printers/%s", printerName);
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", NULL, uri);
        
        ipp_t *response = cupsDoRequest(http, request, "/admin/");
        
        if (response) {
            ipp_status_t status = ippGetStatusCode(response);
            if (status == IPP_OK) {
                NSLog(@"[Printers] Enabled printer: %@", [selectedPrinter name]);
                [statusLabel setStringValue:[NSString stringWithFormat:@"Printer \"%@\" enabled", 
                                             [selectedPrinter displayName]]];
            } else {
                NSLog(@"[Printers] Failed to enable printer: %s", ippErrorString(status));
            }
            ippDelete(response);
        }
        
        httpClose(http);
    }
    
    [self refreshPrinters:nil];
}

- (IBAction)disablePrinter:(id)sender
{
    if (!selectedPrinter) {
        return;
    }
    
    const char *printerName = [[selectedPrinter name] UTF8String];
    
    http_t *http = httpConnect2(cupsServer(), ippPort(), NULL, AF_UNSPEC,
                                cupsEncryption(), 1, 30000, NULL);
    if (http) {
        ipp_t *request = ippNewRequest(IPP_PAUSE_PRINTER);
        
        char uri[HTTP_MAX_URI];
        httpAssembleURIf(HTTP_URI_CODING_ALL, uri, sizeof(uri), "ipp", NULL,
                        "localhost", 0, "/printers/%s", printerName);
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", NULL, uri);
        
        ipp_t *response = cupsDoRequest(http, request, "/admin/");
        
        if (response) {
            ipp_status_t status = ippGetStatusCode(response);
            if (status == IPP_OK) {
                NSLog(@"[Printers] Disabled printer: %@", [selectedPrinter name]);
                [statusLabel setStringValue:[NSString stringWithFormat:@"Printer \"%@\" disabled", 
                                             [selectedPrinter displayName]]];
            } else {
                NSLog(@"[Printers] Failed to disable printer: %s", ippErrorString(status));
            }
            ippDelete(response);
        }
        
        httpClose(http);
    }
    
    [self refreshPrinters:nil];
}

#pragma mark - Job Actions

- (IBAction)cancelJob:(id)sender
{
    if (!selectedJob) {
        return;
    }
    
    int jobId = [selectedJob jobId];
    const char *printerName = [[selectedJob printerName] UTF8String];
    
    // Cancel the job
    if (cupsCancelJob2(CUPS_HTTP_DEFAULT, printerName, jobId, 0) == 0) {
        NSLog(@"[Printers] Cancelled job: %d", jobId);
        [statusLabel setStringValue:[NSString stringWithFormat:@"Job %d cancelled", jobId]];
    } else {
        NSLog(@"[Printers] Failed to cancel job: %d - %s", jobId, cupsLastErrorString());
        [statusLabel setStringValue:[NSString stringWithFormat:@"Failed to cancel job: %s", cupsLastErrorString()]];
    }
    
    [self refreshJobs];
}

- (IBAction)pauseResumeJob:(id)sender
{
    if (!selectedJob) {
        return;
    }
    
    int jobId = [selectedJob jobId];
    BOOL isHeld = [[selectedJob state] isEqualToString:@"Held"];
    
    http_t *http = httpConnect2(cupsServer(), ippPort(), NULL, AF_UNSPEC,
                                cupsEncryption(), 1, 30000, NULL);
    if (http) {
        ipp_t *request = ippNewRequest(isHeld ? IPP_RELEASE_JOB : IPP_HOLD_JOB);
        
        char uri[HTTP_MAX_URI];
        httpAssembleURIf(HTTP_URI_CODING_ALL, uri, sizeof(uri), "ipp", NULL,
                        "localhost", 0, "/jobs/%d", jobId);
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "job-uri", NULL, uri);
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", NULL, cupsUser());
        
        ipp_t *response = cupsDoRequest(http, request, "/jobs/");
        
        if (response) {
            ipp_status_t status = ippGetStatusCode(response);
            if (status == IPP_OK) {
                NSLog(@"[Printers] %@ job: %d", isHeld ? @"Released" : @"Held", jobId);
                [statusLabel setStringValue:[NSString stringWithFormat:@"Job %d %@", 
                                             jobId, isHeld ? @"released" : @"held"]];
            } else {
                NSLog(@"[Printers] Failed to %@ job: %s", isHeld ? @"release" : @"hold", ippErrorString(status));
            }
            ippDelete(response);
        }
        
        httpClose(http);
    }
    
    [self refreshJobs];
}

#pragma mark - Add Printer Panel

- (void)showAddPrinterPanel
{
    if (!addPrinterPanel) {
        addPrinterPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
                                                     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                       backing:NSBackingStoreBuffered
                                                         defer:YES];
        [addPrinterPanel setTitle:@"Add Printer"];
        [addPrinterPanel setReleasedWhenClosed:NO];
        
        NSView *content = [addPrinterPanel contentView];
        
        // Instructions
        NSTextField *instructLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 460, 30)];
        [instructLabel setStringValue:@"Select a printer from the list below or enter the printer address manually."];
        [instructLabel setBezeled:NO];
        [instructLabel setDrawsBackground:NO];
        [instructLabel setEditable:NO];
        [instructLabel setSelectable:NO];
        [content addSubview:instructLabel];
        [instructLabel release];
        
        // Discover button and progress
        discoverButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 325, 100, 24)];
        [discoverButton setTitle:@"Discover"];
        [discoverButton setBezelStyle:NSRoundedBezelStyle];
        [discoverButton setTarget:self];
        [discoverButton setAction:@selector(discoverDevices:)];
        [content addSubview:discoverButton];
        
        discoverProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(130, 330, 20, 20)];
        [discoverProgress setStyle:NSProgressIndicatorSpinningStyle];
        [discoverProgress setDisplayedWhenStopped:NO];
        [content addSubview:discoverProgress];
        
        // Device table
        deviceScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 160, 460, 160)];
        [deviceScroll setHasVerticalScroller:YES];
        [deviceScroll setHasHorizontalScroller:NO];
        [deviceScroll setBorderType:NSBezelBorder];
        [content addSubview:deviceScroll];
        
        deviceTable = [[NSTableView alloc] initWithFrame:[deviceScroll bounds]];
        [deviceTable setDelegate:self];
        [deviceTable setDataSource:self];
        [deviceTable setAllowsMultipleSelection:NO];
        [deviceTable setAllowsEmptySelection:YES];
        
        NSTableColumn *deviceColumn = [[NSTableColumn alloc] initWithIdentifier:@"device"];
        [deviceColumn setTitle:@"Printer"];
        [deviceColumn setWidth:320];
        [deviceColumn setEditable:NO];
        [deviceTable addTableColumn:deviceColumn];
        [deviceColumn release];
        
        NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
        [typeColumn setTitle:@"Type"];
        [typeColumn setWidth:120];
        [typeColumn setEditable:NO];
        [deviceTable addTableColumn:typeColumn];
        [typeColumn release];
        
        [deviceScroll setDocumentView:deviceTable];
        
        // Printer name field
        NSTextField *nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 125, 100, 20)];
        [nameLabel setStringValue:@"Name:"];
        [nameLabel setBezeled:NO];
        [nameLabel setDrawsBackground:NO];
        [nameLabel setEditable:NO];
        [nameLabel setSelectable:NO];
        [content addSubview:nameLabel];
        [nameLabel release];
        
        printerNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 122, 350, 24)];
        [printerNameField setPlaceholderString:@"Enter printer name"];
        [content addSubview:printerNameField];
        
        // Location field
        NSTextField *locationLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 90, 100, 20)];
        [locationLabel setStringValue:@"Location:"];
        [locationLabel setBezeled:NO];
        [locationLabel setDrawsBackground:NO];
        [locationLabel setEditable:NO];
        [locationLabel setSelectable:NO];
        [content addSubview:locationLabel];
        [locationLabel release];
        
        printerLocationField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 87, 350, 24)];
        [printerLocationField setPlaceholderString:@"Optional location description"];
        [content addSubview:printerLocationField];
        
        // Driver popup
        NSTextField *driverLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 55, 100, 20)];
        [driverLabel setStringValue:@"Driver:"];
        [driverLabel setBezeled:NO];
        [driverLabel setDrawsBackground:NO];
        [driverLabel setEditable:NO];
        [driverLabel setSelectable:NO];
        [content addSubview:driverLabel];
        [driverLabel release];
        
        driverPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 52, 350, 26)];
        [driverPopup addItemWithTitle:@"Generic PostScript Printer"];
        [driverPopup addItemWithTitle:@"Generic PCL Laser Printer"];
        [driverPopup addItemWithTitle:@"Raw Queue (No Driver)"];
        [driverPopup addItemWithTitle:@"IPP Everywhere"];
        [content addSubview:driverPopup];
        
        // Load additional drivers
        [self populateDriverPopup];
        
        // Buttons
        NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(310, 10, 80, 24)];
        [cancelButton setTitle:@"Cancel"];
        [cancelButton setBezelStyle:NSRoundedBezelStyle];
        [cancelButton setTarget:self];
        [cancelButton setAction:@selector(cancelAddPrinter:)];
        [content addSubview:cancelButton];
        [cancelButton release];
        
        NSButton *addBtn = [[NSButton alloc] initWithFrame:NSMakeRect(400, 10, 80, 24)];
        [addBtn setTitle:@"Add"];
        [addBtn setBezelStyle:NSRoundedBezelStyle];
        [addBtn setTarget:self];
        [addBtn setAction:@selector(confirmAddPrinter:)];
        [content addSubview:addBtn];
        [addBtn release];
    }
    
    // Clear previous data
    [discoveredDevices removeAllObjects];
    [deviceTable reloadData];
    [printerNameField setStringValue:@""];
    [printerLocationField setStringValue:@""];
    
    // Center the panel
    [addPrinterPanel center];
    [addPrinterPanel makeKeyAndOrderFront:nil];
    
    // Auto-discover devices
    [self discoverDevices:nil];
}

- (void)populateDriverPopup
{
    // Get list of available PPD files
    NSArray *drivers = [self getAvailableDrivers];
    
    for (NSString *driver in drivers) {
        if (![driverPopup itemWithTitle:driver]) {
            [driverPopup addItemWithTitle:driver];
        }
    }
}

- (NSArray *)getAvailableDrivers
{
    NSMutableArray *drivers = [NSMutableArray array];
    
    // Get PPD list from CUPS
    ipp_t *request = ippNewRequest(CUPS_GET_PPDS);
    
    ipp_t *response = cupsDoRequest(CUPS_HTTP_DEFAULT, request, "/");
    
    if (response) {
        ipp_attribute_t *attr;
        
        for (attr = ippFirstAttribute(response); attr; attr = ippNextAttribute(response)) {
            const char *name = ippGetName(attr);
            
            if (name && strcmp(name, "ppd-make-and-model") == 0) {
                const char *value = ippGetString(attr, 0, NULL);
                if (value) {
                    NSString *driverName = [NSString stringWithUTF8String:value];
                    if (![drivers containsObject:driverName]) {
                        [drivers addObject:driverName];
                    }
                }
            }
        }
        
        ippDelete(response);
    }
    
    // Sort drivers alphabetically
    [drivers sortUsingSelector:@selector(caseInsensitiveCompare:)];
    
    // Limit to first 100 to avoid overwhelming the popup
    if ([drivers count] > 100) {
        return [drivers subarrayWithRange:NSMakeRange(0, 100)];
    }
    
    return drivers;
}

- (IBAction)discoverDevices:(id)sender
{
    if (isDiscovering) {
        return;
    }
    
    isDiscovering = YES;
    [discoverButton setEnabled:NO];
    [discoverProgress startAnimation:nil];
    
    [discoveredDevices removeAllObjects];
    [deviceTable reloadData];
    
    // Run discovery in background
    [NSThread detachNewThreadSelector:@selector(discoverDevicesInBackground) toTarget:self withObject:nil];
}

- (void)discoverDevicesInBackground
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    DeviceCallbackContext ctx;
    ctx.devices = discoveredDevices;
    ctx.controller = self;
    
    // Discover devices using CUPS (timeout 10 seconds)
    cupsGetDevices(CUPS_HTTP_DEFAULT, 10000, NULL, NULL, deviceCallback, &ctx);
    
    // Update UI on main thread
    [self performSelectorOnMainThread:@selector(discoveryComplete) withObject:nil waitUntilDone:NO];
    
    [pool release];
}

- (void)discoveryComplete
{
    isDiscovering = NO;
    [discoverButton setEnabled:YES];
    [discoverProgress stopAnimation:nil];
    
    [deviceTable reloadData];
    
    NSLog(@"[Printers] Discovery complete, found %lu devices", (unsigned long)[discoveredDevices count]);
}

- (IBAction)confirmAddPrinter:(id)sender
{
    NSString *printerName = [printerNameField stringValue];
    
    if ([printerName length] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Printer Name Required"];
        [alert setInformativeText:@"Please enter a name for the printer."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        return;
    }
    
    // Get selected device
    NSInteger row = [deviceTable selectedRow];
    NSString *deviceURI = nil;
    
    if (row >= 0 && row < (NSInteger)[discoveredDevices count]) {
        DiscoveredDevice *device = [discoveredDevices objectAtIndex:row];
        deviceURI = [device deviceURI];
    }
    
    if (!deviceURI || [deviceURI length] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Printer Not Selected"];
        [alert setInformativeText:@"Please select a printer from the discovered devices list."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        return;
    }
    
    NSString *location = [printerLocationField stringValue];
    NSString *driver = [driverPopup titleOfSelectedItem];
    
    // Determine PPD file based on driver selection
    const char *ppdFile = NULL;
    
    if ([driver isEqualToString:@"Generic PostScript Printer"]) {
        ppdFile = "drv:///sample.drv/generic.ppd";
    } else if ([driver isEqualToString:@"Generic PCL Laser Printer"]) {
        ppdFile = "drv:///sample.drv/generpcl.ppd";
    } else if ([driver isEqualToString:@"Raw Queue (No Driver)"]) {
        ppdFile = "raw";
    } else if ([driver isEqualToString:@"IPP Everywhere"]) {
        ppdFile = "everywhere";
    }
    
    // Add the printer using IPP
    http_t *http = httpConnect2(cupsServer(), ippPort(), NULL, AF_UNSPEC,
                                cupsEncryption(), 1, 30000, NULL);
    
    if (http) {
        ipp_t *request = ippNewRequest(IPP_OP_CUPS_ADD_MODIFY_PRINTER);
        
        char uri[HTTP_MAX_URI];
        httpAssembleURIf(HTTP_URI_CODING_ALL, uri, sizeof(uri), "ipp", NULL,
                        "localhost", 0, "/printers/%s", [printerName UTF8String]);
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", NULL, uri);
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", NULL, cupsUser());
        
        // Add printer attributes
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_URI, "device-uri", NULL, [deviceURI UTF8String]);
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_TEXT, "printer-info", NULL, [printerName UTF8String]);
        
        if ([location length] > 0) {
            ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_TEXT, "printer-location", NULL, [location UTF8String]);
        }
        
        ippAddInteger(request, IPP_TAG_PRINTER, IPP_TAG_ENUM, "printer-state", IPP_PRINTER_IDLE);
        ippAddBoolean(request, IPP_TAG_PRINTER, "printer-is-accepting-jobs", 1);
        
        // Set PPD if specified
        if (ppdFile) {
            ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_NAME, "ppd-name", NULL, ppdFile);
        }
        
        ipp_t *response = cupsDoRequest(http, request, "/admin/");
        
        BOOL success = NO;
        if (response) {
            ipp_status_t status = ippGetStatusCode(response);
            if (status == IPP_OK || status == IPP_OK_SUBST || status == IPP_OK_CONFLICT) {
                success = YES;
                NSLog(@"[Printers] Added printer: %@", printerName);
            } else {
                NSLog(@"[Printers] Failed to add printer: %s", ippErrorString(status));
            }
            ippDelete(response);
        }
        
        httpClose(http);
        
        if (success) {
            [addPrinterPanel orderOut:nil];
            [statusLabel setStringValue:[NSString stringWithFormat:@"Printer \"%@\" added successfully", printerName]];
            [self refreshPrinters:nil];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Failed to Add Printer"];
            [alert setInformativeText:@"Could not add the printer. To manage printers, add yourself to the 'lpadmin' group:\n\nsudo usermod -a -G lpadmin $USER\n\nThen log out and log back in."];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
            [alert release];
        }
    }
}

- (IBAction)cancelAddPrinter:(id)sender
{
    [addPrinterPanel orderOut:nil];
}

#pragma mark - Options Panel

- (void)showOptionsPanel
{
    if (!selectedPrinter) {
        return;
    }
    
    // Create options panel
    NSPanel *optionsPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
    [optionsPanel setTitle:[NSString stringWithFormat:@"Options for %@", [selectedPrinter displayName]]];
    
    NSView *content = [optionsPanel contentView];
    
    // Printer info
    NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 250, 360, 40)];
    NSMutableString *infoText = [NSMutableString string];
    [infoText appendFormat:@"Name: %@\n", [selectedPrinter displayName]];
    if ([selectedPrinter makeModel]) {
        [infoText appendFormat:@"Model: %@", [selectedPrinter makeModel]];
    }
    [infoLabel setStringValue:infoText];
    [infoLabel setBezeled:NO];
    [infoLabel setDrawsBackground:NO];
    [infoLabel setEditable:NO];
    [infoLabel setSelectable:YES];
    [content addSubview:infoLabel];
    [infoLabel release];
    
    // URI
    NSTextField *uriLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 210, 360, 30)];
    [uriLabel setStringValue:[NSString stringWithFormat:@"URI: %@", [selectedPrinter deviceURI] ?: @"Unknown"]];
    [uriLabel setBezeled:NO];
    [uriLabel setDrawsBackground:NO];
    [uriLabel setEditable:NO];
    [uriLabel setSelectable:YES];
    [uriLabel setFont:[NSFont systemFontOfSize:10]];
    [content addSubview:uriLabel];
    [uriLabel release];
    
    // Status
    NSTextField *statusLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 180, 360, 20)];
    [statusLbl setStringValue:[NSString stringWithFormat:@"Status: %@", [selectedPrinter state]]];
    [statusLbl setBezeled:NO];
    [statusLbl setDrawsBackground:NO];
    [statusLbl setEditable:NO];
    [statusLbl setSelectable:NO];
    [content addSubview:statusLbl];
    [statusLbl release];
    
    // Accepting jobs checkbox
    NSButton *acceptingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 140, 200, 20)];
    [acceptingCheckbox setButtonType:NSSwitchButton];
    [acceptingCheckbox setTitle:@"Accepting Print Jobs"];
    [acceptingCheckbox setState:[selectedPrinter acceptingJobs] ? NSOnState : NSOffState];
    [content addSubview:acceptingCheckbox];
    [acceptingCheckbox release];
    
    // Shared checkbox
    NSButton *sharedCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 110, 200, 20)];
    [sharedCheckbox setButtonType:NSSwitchButton];
    [sharedCheckbox setTitle:@"Share this Printer"];
    [sharedCheckbox setState:[selectedPrinter isShared] ? NSOnState : NSOffState];
    [content addSubview:sharedCheckbox];
    [sharedCheckbox release];
    
    // Enable/Disable button
    NSButton *enableButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 60, 120, 24)];
    if ([[selectedPrinter state] isEqualToString:@"Stopped"]) {
        [enableButton setTitle:@"Enable"];
        [enableButton setTarget:self];
        [enableButton setAction:@selector(enablePrinter:)];
    } else {
        [enableButton setTitle:@"Disable"];
        [enableButton setTarget:self];
        [enableButton setAction:@selector(disablePrinter:)];
    }
    [enableButton setBezelStyle:NSRoundedBezelStyle];
    [content addSubview:enableButton];
    [enableButton release];
    
    // Close button
    NSButton *closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, 10, 80, 24)];
    [closeButton setTitle:@"Close"];
    [closeButton setBezelStyle:NSRoundedBezelStyle];
    [closeButton setTarget:optionsPanel];
    [closeButton setAction:@selector(orderOut:)];
    [content addSubview:closeButton];
    [closeButton release];
    
    [optionsPanel center];
    [optionsPanel makeKeyAndOrderFront:nil];
    [optionsPanel autorelease];
}

@end
