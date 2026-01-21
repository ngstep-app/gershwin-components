/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ProcessesController.h"
#import <dirent.h>
#import <pwd.h>
#import <sys/stat.h>
#include <stdint.h>
#ifndef __linux__
#import <sys/sysctl.h>
#endif
#import <unistd.h>
#import <errno.h>
#import <sys/wait.h>

// Helper function to get total system memory in KB
static long getTotalSystemMemoryKB(void) {
    long totalMemory = 0;
    
#ifdef __linux__
    // Linux: Read from /proc/meminfo
    FILE *memFile = fopen("/proc/meminfo", "r");
    if (memFile) {
        char line[256];
        while (fgets(line, sizeof(line), memFile)) {
            if (strncmp(line, "MemTotal:", 9) == 0) {
                sscanf(line, "MemTotal: %ld", &totalMemory);
                break;
            }
        }
        fclose(memFile);
    }
#else
    // BSD and other Unix-like systems: prefer sysctlbyname for portability
    uint64_t memsize = 0;
    size_t len = sizeof(memsize);
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
    // Try several common sysctl names across BSDs/macOS
    const char *names[] = { "hw.memsize", "hw.physmem", "hw.realmem", "hw.physmem64", NULL };
    const char **n;
    for (n = names; *n != NULL; n++) {
        len = sizeof(memsize);
        if (sysctlbyname(*n, &memsize, &len, NULL, 0) == 0 && len > 0) {
            totalMemory = (long)(memsize / 1024);
            break;
        }
    }
    if (totalMemory == 0) {
#ifdef HW_MEMSIZE
        int mib[2] = {CTL_HW, HW_MEMSIZE};
        len = sizeof(memsize);
        if (sysctl(mib, 2, &memsize, &len, NULL, 0) == 0) {
            totalMemory = (long)(memsize / 1024);
        }
#endif
    }
#else
#ifdef HW_MEMSIZE
    int mib[2] = {CTL_HW, HW_MEMSIZE};
    unsigned long memsize_ul = 0;
    size_t len_ul = sizeof(memsize_ul);
    if (sysctl(mib, 2, &memsize_ul, &len_ul, NULL, 0) == 0) {
        totalMemory = memsize_ul / 1024;
    }
#endif
#endif
#endif
    
    return totalMemory;
}



@implementation ProcessesController

@synthesize processes = _processes;

static ProcessesController *sharedController = nil;

+ (ProcessesController *)sharedController
{
    if (!sharedController) {
        sharedController = [[ProcessesController alloc] init];
    }
    return sharedController;
}

- (id)init
{
    self = [super init];
    if (self) {
        _processes = [[NSMutableArray alloc] init];
        _processesLock = [[NSLock alloc] init];
        _refreshInterval = 5.0; // Refresh every 5 seconds
        _prevCpuTimes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    // Cleanup not involving object releases (ARC handles memory)
    [self stopMonitoring];
    // Other cleanup if necessary
}

- (void)awakeFromNib
{
    // Not using nib
}

- (void)startMonitoring
{
    if (!_refreshTimer) {
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:_refreshInterval
                                                          target:self
                                                        selector:@selector(refreshProcesses)
                                                        userInfo:nil
                                                         repeats:YES];
    }
}

- (void)stopMonitoring
{
    if (_refreshTimer) {
        [_refreshTimer invalidate];
        _refreshTimer = nil;
    }
}

- (void)refreshProcesses
{
    [_processesLock lock];
    [_processes removeAllObjects];
    
    // Get system info for calculations
    long totalMemory = getTotalSystemMemoryKB();
    
    DIR *procDir = opendir("/proc");
    if (procDir) {
        struct dirent *entry;
        while ((entry = readdir(procDir)) != NULL) {
            // Check if entry is a number (PID)
            char *endptr;
            int pid = (int)strtol(entry->d_name, &endptr, 10);
            if (*endptr == '\0' && pid > 0) {
                // Read /proc/pid/stat
                char statPath[256];
                snprintf(statPath, sizeof(statPath), "/proc/%d/stat", pid);
                
                FILE *statFile = fopen(statPath, "r");
                if (statFile) {
                    char statLine[1024];
                    if (fgets(statLine, sizeof(statLine), statFile)) {
                        ProcessInfo *info = [[ProcessInfo alloc] init];
                        info.pid = pid;
                        
                        // Parse stat line: pid (comm) state ppid ... uid vsize rss ...
                        char comm[256];
                        
                        // Simplified parsing - find the fields we need
                        int parsedPid, parsedPpid;
                        unsigned long parsedVsize, parsedRss;
                        char parsedState;
                        sscanf(statLine, "%d (%[^)]) %c %d %*d %*d %*d %*d %*u %*u %*u %*u %*u %*d %*d %*d %*d %*d %*d %*u %*u %*d %*u %lu %lu", 
                               &parsedPid, comm, &parsedState, &parsedPpid, &parsedVsize, &parsedRss);
                        
                        info.pid = parsedPid;
                        info.ppid = parsedPpid;
                        info.state = [NSString stringWithFormat:@"%c", parsedState];
                        // Parse fields after the closing parenthesis in /proc/[pid]/stat
                        char *rparen = strrchr(statLine, ')');
                        unsigned long utime = 0, stime = 0;
                        unsigned long parsedVsizeUL = 0;
                        long parsedRssLong = 0;
                        int parsedPpidLocal = 0;
                        if (rparen) {
                            char *rest = rparen + 2; // skip ") "
                            int field = 1;
                            char *saveptr = NULL;
                            char *token = strtok_r(rest, " ", &saveptr);
                            while (token) {
                                if (field == 1) {
                                    // state
                                } else if (field == 2) {
                                    parsedPpidLocal = atoi(token);
                                } else if (field == 12) {
                                    utime = strtoul(token, NULL, 10);
                                } else if (field == 13) {
                                    stime = strtoul(token, NULL, 10);
                                } else if (field == 21) {
                                    parsedVsizeUL = strtoul(token, NULL, 10);
                                } else if (field == 22) {
                                    parsedRssLong = atol(token);
                                    break; // we have what we need
                                }
                                token = strtok_r(NULL, " ", &saveptr);
                                field++;
                            }
                        }

                        info.pid = parsedPid;
                        info.ppid = parsedPpidLocal ? parsedPpidLocal : parsedPpid;
                        info.state = [NSString stringWithFormat:@"%c", parsedState];
                        long pageSize = sysconf(_SC_PAGESIZE);
                        info.virtualMemory = parsedVsizeUL / 1024; // KB
                        info.residentMemory = (parsedRssLong * pageSize) / 1024; // convert pages -> KB
                        
                        // Read command line
                        char cmdPath[256];
                        snprintf(cmdPath, sizeof(cmdPath), "/proc/%d/cmdline", pid);
                        FILE *cmdFile = fopen(cmdPath, "r");
                        if (cmdFile) {
                            char cmdLine[1024];
                            size_t len = fread(cmdLine, 1, sizeof(cmdLine) - 1, cmdFile);
                            if (len > 0) {
                                cmdLine[len] = '\0';
                                // Replace null bytes with spaces
                                for (size_t i = 0; i < len; i++) {
                                    if (cmdLine[i] == '\0') cmdLine[i] = ' ';
                                }
                                info.command = [NSString stringWithUTF8String:cmdLine];
                            }
                            fclose(cmdFile);
                        }
                        
                        if (!info.command || [info.command length] == 0) {
                            info.command = [NSString stringWithUTF8String:comm];
                        }
                        
                        // Compute CPU% using previous samples
                        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                        unsigned long totalTicks = utime + stime;
                        NSString *pidKey = [NSString stringWithFormat:@"%d", info.pid];
                        NSDictionary *prev = [_prevCpuTimes objectForKey:pidKey];
                        float cpuPercent = 0.0;
                        long ticksPerSec = sysconf(_SC_CLK_TCK);
                        if (prev) {
                            unsigned long prevTicks = [[prev objectForKey:@"totalTicks"] unsignedLongValue];
                            NSTimeInterval prevTime = [[prev objectForKey:@"time"] doubleValue];
                            NSTimeInterval dt = now - prevTime;
                            if (dt > 0 && totalTicks >= prevTicks) {
                                double dTicks = (double)(totalTicks - prevTicks);
                                double dSeconds = dTicks / (double)ticksPerSec;
                                cpuPercent = (float)((dSeconds / dt) * 100.0);
                                if (cpuPercent < 0) cpuPercent = 0.0;
                            }
                        }
                        // Store this sample for next round
                        NSDictionary *sample = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:totalTicks], @"totalTicks", [NSNumber numberWithDouble:now], @"time", nil];
                        [_prevCpuTimes setObject:sample forKey:pidKey];
                        info.cpu = cpuPercent;
                        
                        // Memory percentage
                        if (totalMemory > 0) {
                            long rss_kb = info.residentMemory; // already KB
                            info.memory = (float)(rss_kb * 100.0 / totalMemory);
                        } else {
                            info.memory = 0.0;
                        }
                        
                        info.user = @"unknown"; // Would need to read uid and map to username
                        
                        [_processes addObject:info];
                    }
                    fclose(statFile);
                }
            }
        }
        closedir(procDir);
    }
    
    [_processesLock unlock];
    

    
    [_processesTableView reloadData];
    
    [self sortProcesses];
}

- (IBAction)forceQuitProcess:(id)sender
{
    NSInteger selectedRow = [_processesTableView selectedRow];
    if (selectedRow >= 0) {
        [_processesLock lock];
        ProcessInfo *info = nil;
        if (selectedRow < [_processes count]) {
            info = [_processes objectAtIndex:selectedRow];
        }
        [_processesLock unlock];
        
        if (info) {
            // First try to send SIGKILL directly
            if (kill(info.pid, SIGKILL) == -1) {
                if (errno == EPERM) {
                    // Permission denied - try using sudo
                    char pidstr[16];
                    snprintf(pidstr, sizeof(pidstr), "%d", info.pid);
                    pid_t child = fork();
                    if (child == 0) {
                        // In child
                        execlp("sudo", "sudo", "-A", "-E", "kill", "-9", pidstr, (char *)NULL);
                        _exit(127); // exec failed
                    } else if (child > 0) {
                        int status = 0;
                        waitpid(child, &status, 0);
                    } else {
                        // fork failed
                    }
                } else {
                    // Other errors - nothing to do
                }
            }
            
            // Refresh after a short delay
            [self performSelector:@selector(refreshProcesses) withObject:nil afterDelay:0.5];
        }
    }
}

- (void)sortProcesses
{
    if (_sortDescriptors && [_sortDescriptors count] > 0) {
        [_processes sortUsingDescriptors:_sortDescriptors];
    }
}

// NSTableViewDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    [_processesLock lock];
    NSInteger count = [_processes count];
    [_processesLock unlock];
    return count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    [_processesLock lock];
    if (row < 0 || row >= [_processes count]) {
        [_processesLock unlock];
        return @"";
    }
    ProcessInfo *info = [_processes objectAtIndex:row];
    [_processesLock unlock];
    
    NSString *identifier = [tableColumn identifier];
    NSString *result = @"";
    
    if ([identifier isEqualToString:@"pid"]) {
        result = [NSString stringWithFormat:@"%d", info.pid];
    } else if ([identifier isEqualToString:@"user"]) {
        result = info.user ? info.user : @"";
    } else if ([identifier isEqualToString:@"cpu"]) {
        result = [NSString stringWithFormat:@"%.1f", info.cpu];
    } else if ([identifier isEqualToString:@"memory"]) {
        result = [NSString stringWithFormat:@"%.1f", info.memory];
    } else if ([identifier isEqualToString:@"command"]) {
        result = info.command ? info.command : @"";
    } else if ([identifier isEqualToString:@"state"]) {
        result = info.state ? info.state : @"";
    }
    
    return result;
}

// NSTableViewDelegate
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger selectedRow = [_processesTableView selectedRow];
    if (selectedRow >= 0) {
        [_processesLock lock];
        ProcessInfo *info = nil;
        if (selectedRow < [_processes count]) {
            info = [_processes objectAtIndex:selectedRow];
        }
        [_processesLock unlock];
        
        if (info) {
            // Create drawer lazily if needed
            if (!_infoDrawer) {
                _infoDrawer = [[NSDrawer alloc] initWithContentSize:NSMakeSize(300, 400) preferredEdge:NSMaxXEdge];
                [_infoDrawer setParentWindow:_mainWindow];
                [_infoDrawer setDelegate:self];
                
                NSView *drawerContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
                [_infoDrawer setContentView:drawerContent];
                
                // Info text field
                _infoTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 50, 280, 320)];
                [_infoTextField setEditable:NO];
                [_infoTextField setSelectable:YES];
                [_infoTextField setBordered:YES];
                [_infoTextField setBezeled:YES];
                [[_infoDrawer contentView] addSubview:_infoTextField];
                
                // Force quit button
                _forceQuitButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 100, 24)];
                [_forceQuitButton setTitle:@"Force Quit"];
                [_forceQuitButton setTarget:self];
                [_forceQuitButton setAction:@selector(forceQuitProcess:)];
                [_forceQuitButton setEnabled:NO];
                [[_infoDrawer contentView] addSubview:_forceQuitButton];
            }
            
            // Populate drawer with safe access
            NSMutableString *infoString = [NSMutableString string];
            [infoString appendString:@"Process Information:\n\n"];
            [infoString appendFormat:@"PID: %d\n", info.pid];
            [infoString appendFormat:@"User: %@\n", (info.user ? info.user : @"N/A")];
            [infoString appendFormat:@"CPU: %.1f%%\n", info.cpu];
            [infoString appendFormat:@"Memory: %.1f%%\n", info.memory];
            [infoString appendFormat:@"State: %@\n", (info.state ? info.state : @"N/A")];
            [infoString appendFormat:@"Command: %@\n", (info.command ? info.command : @"N/A")];
            
            [_infoTextField setStringValue:infoString];

            
            [_forceQuitButton setEnabled:YES];
            [_infoDrawer open];
        } else {
            [_processesLock unlock];
            [_forceQuitButton setEnabled:NO];
            if (_infoDrawer) [_infoDrawer close];
        }
    } else {
        [_forceQuitButton setEnabled:NO];
        if (_infoDrawer) [_infoDrawer close];
    }
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
    // Not needed, handled by sortDescriptorsDidChange
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    _sortDescriptors = [tableView sortDescriptors];
    [_processesLock lock];
    [self sortProcesses];
    [_processesLock unlock];
    [_processesTableView reloadData];
}

// NSApplicationDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self createUI];
    [self startMonitoring];
    [_mainWindow makeKeyAndOrderFront:self];
    
    // Delay refresh to avoid race conditions
    [self performSelector:@selector(refreshProcesses) withObject:nil afterDelay:0.5];
}

- (void)createUI
{
    // Create main window
    _mainWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 800, 600)
                                                styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [_mainWindow setTitle:@"Processes"];
    [_mainWindow setDelegate:self];
    
    // Create scroll view for table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:[[_mainWindow contentView] bounds]];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setBorderType:NSBezelBorder];
    
    // Create table view
    _processesTableView = [[NSTableView alloc] initWithFrame:[scrollView bounds]];
    [_processesTableView setDataSource:self];
    [_processesTableView setDelegate:self];
    [_processesTableView setAllowsMultipleSelection:NO];
    
    NSTableColumn *pidColumn = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
    [[pidColumn headerCell] setStringValue:@"PID"];
    [pidColumn setWidth:60];
    [pidColumn setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"pid" ascending:YES]];
    [_processesTableView addTableColumn:pidColumn];
    
    NSTableColumn *userColumn = [[NSTableColumn alloc] initWithIdentifier:@"user"];
    [[userColumn headerCell] setStringValue:@"User"];
    [userColumn setWidth:80];
    [userColumn setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"user" ascending:YES]];
    [_processesTableView addTableColumn:userColumn];
    
    NSTableColumn *cpuColumn = [[NSTableColumn alloc] initWithIdentifier:@"cpu"];
    [[cpuColumn headerCell] setStringValue:@"CPU %"];
    [cpuColumn setWidth:60];
    [cpuColumn setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"cpu" ascending:YES]];
    [_processesTableView addTableColumn:cpuColumn];
    
    NSTableColumn *memColumn = [[NSTableColumn alloc] initWithIdentifier:@"memory"];
    [[memColumn headerCell] setStringValue:@"Memory %"];
    [memColumn setWidth:80];
    [memColumn setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"memory" ascending:YES]];
    [_processesTableView addTableColumn:memColumn];
    
    NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
    [[stateColumn headerCell] setStringValue:@"State"];
    [stateColumn setWidth:50];
    [stateColumn setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"state" ascending:YES]];
    [_processesTableView addTableColumn:stateColumn];
    
    NSTableColumn *commandColumn = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    [[commandColumn headerCell] setStringValue:@"Command"];
    [commandColumn setWidth:300];
    [commandColumn setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"command" ascending:YES]];
    [_processesTableView addTableColumn:commandColumn];
    
    [scrollView setDocumentView:_processesTableView];
    [[_mainWindow contentView] addSubview:scrollView];
    
    // Buttons removed as requested
    
    // Create drawer - temporarily disabled to debug crash
    /*
    _infoDrawer = [[NSDrawer alloc] initWithContentSize:NSMakeSize(300, 400) preferredEdge:NSMaxXEdge];
    [_infoDrawer setParentWindow:_mainWindow];
    [_infoDrawer setDelegate:self];
    
    NSView *drawerContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
    [_infoDrawer setContentView:drawerContent];
    
    // Info text field
    _infoTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 50, 280, 320)];
    [_infoTextField setEditable:NO];
    [_infoTextField setSelectable:YES];
    [_infoTextField setBordered:YES];
    [_infoTextField setBezeled:YES];
    [drawerContent addSubview:_infoTextField];
    
    // Force quit button
    _forceQuitButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 100, 24)];
    [_forceQuitButton setTitle:@"Force Quit"];
    [_forceQuitButton setTarget:self];
    [_forceQuitButton setAction:@selector(forceQuitProcess:)];
    [_forceQuitButton setEnabled:NO];
    [drawerContent addSubview:_forceQuitButton];
    */
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

@end