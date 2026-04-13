/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SystemMonitorProvider.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#ifdef __linux__
#include <unistd.h>
#endif

#ifdef __FreeBSD__
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <vm/vm_param.h>
#endif

@implementation SystemMonitorProvider

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.cpuUsage = 0.0;
        self.ramUsage = 0.0;
        self.perCoreCPU = [NSMutableArray array];
        self.lastTotalTicks = 0;
        self.lastIdleTicks = 0;
        self.cachedFixedWidth = 0.0;
    }
    return self;
}

- (NSString *)identifier
{
    return @"org.gershwin.menu.statusitem.systemmonitor";
}

- (NSString *)title
{
    // Format: "CPU 45% RAM 67%"
    return [NSString stringWithFormat:@"CPU %.0f%% RAM %.0f%%", self.cpuUsage, self.ramUsage];
}

- (CGFloat)width
{
    /*
     * Return a fixed width large enough for the widest possible title.
     * Computed once at load time and cached so the cell never resizes.
     */
    return self.cachedFixedWidth;
}

- (NSInteger)displayPriority
{
    // Higher than default (100), but lower than time (1000)
    return 500;
}

- (NSTimeInterval)updateInterval
{
    return 1.0; // Update every second
}

- (void)loadWithManager:(id)manager
{
    NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: Loading system monitor");
    self.manager = manager;

    /* Create detail menu */
    self.detailMenu = [[NSMenu alloc] initWithTitle:@"System Monitor"];
    [self.detailMenu setAutoenablesItems:NO];

    NSMenuItem *cpuHeader = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"CPU Usage", @"CPU section header")
                                                       action:nil keyEquivalent:@""];
    [cpuHeader setEnabled:NO];
    [self.detailMenu addItem:cpuHeader];

    NSMenuItem *ramHeader = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Memory Usage", @"RAM section header")
                                                       action:nil keyEquivalent:@""];
    [ramHeader setEnabled:NO];
    [self.detailMenu addItem:ramHeader];

    /*
     * Compute fixed width from the widest possible title string.
     * "CPU 100% RAM 100%" is the maximum; add 8 px padding on each side.
     */
    NSFont *font = [NSFont menuBarFontOfSize:0];
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    NSSize size = [@"CPU 100% RAM 100%" sizeWithAttributes:attrs];
    self.cachedFixedWidth = ceil(size.width) + 16.0;

    NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: Computed fixed width: %.0f", self.cachedFixedWidth);

    /* Initial update */
    [self update];
}

- (void)update
{
    [self updateCPUUsage];
    [self updateRAMUsage];
    [self updateDetailMenu];
}

- (void)handleClick
{
    NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: Clicked (menu will be shown automatically)");
}

- (NSMenu *)menu
{
    return self.detailMenu;
}

- (void)unload
{
    NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: Unloading");
    self.detailMenu = nil;
    self.perCoreCPU = nil;
}

#pragma mark - Platform-Specific Implementation

#ifdef __linux__

- (void)updateCPUUsage
{
    FILE *fp = fopen("/proc/stat", "r");
    if (!fp) {
        NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: Failed to open /proc/stat");
        return;
    }
    
    char line[256];
    unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
    
    if (fgets(line, sizeof(line), fp)) {
        int matches = sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
                            &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal);
        
        if (matches >= 4) {
            unsigned long long total = user + nice + system + idle + iowait + irq + softirq + steal;
            
            if (self.lastTotalTicks > 0) {
                unsigned long long totalDelta = total - self.lastTotalTicks;
                unsigned long long idleDelta = idle - self.lastIdleTicks;
                
                if (totalDelta > 0) {
                    self.cpuUsage = 100.0 * (1.0 - ((double)idleDelta / (double)totalDelta));
                }
            }
            
            self.lastTotalTicks = total;
            self.lastIdleTicks = idle;
        }
    }
    
    // Read per-core CPU usage
    [self.perCoreCPU removeAllObjects];
    rewind(fp);
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "cpu", 3) == 0 && line[3] >= '0' && line[3] <= '9') {
            unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
            int matches = sscanf(line, "cpu%*d %llu %llu %llu %llu %llu %llu %llu %llu",
                                &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal);
            
            if (matches >= 4) {
                unsigned long long total = user + nice + system + idle + iowait + irq + softirq + steal;
                unsigned long long active = total - idle;
                double usage = total > 0 ? (100.0 * active / total) : 0.0;
                [self.perCoreCPU addObject:@(usage)];
            }
        }
    }
    
    fclose(fp);
}

- (void)updateRAMUsage
{
    FILE *fp = fopen("/proc/meminfo", "r");
    if (!fp) {
        NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: Failed to open /proc/meminfo");
        return;
    }
    
    char line[256];
    unsigned long long memTotal = 0, memAvailable = 0;
    
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "MemTotal: %llu kB", &memTotal) == 1) {
            continue;
        }
        if (sscanf(line, "MemAvailable: %llu kB", &memAvailable) == 1) {
            break;
        }
    }
    
    fclose(fp);
    
    if (memTotal > 0) {
        unsigned long long memUsed = memTotal - memAvailable;
        self.ramUsage = 100.0 * memUsed / memTotal;
    }
}

#elif defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__DragonFly__)

- (void)updateCPUUsage
{
    // BSD uses sysctl for CPU statistics
    size_t size;
    
#ifdef __FreeBSD__
    // Get CPU time info
    long cp_time[5]; // CPUSTATES = 5 on FreeBSD
    size = sizeof(cp_time);
    
    if (sysctlbyname("kern.cp_time", &cp_time, &size, NULL, 0) == 0) {
        unsigned long long user = cp_time[0];
        unsigned long long nice = cp_time[1];
        unsigned long long system = cp_time[2];
        unsigned long long idle = cp_time[4];
        unsigned long long total = user + nice + system + idle;
        
        if (self.lastTotalTicks > 0) {
            unsigned long long totalDelta = total - self.lastTotalTicks;
            unsigned long long idleDelta = idle - self.lastIdleTicks;
            
            if (totalDelta > 0) {
                self.cpuUsage = 100.0 * (1.0 - ((double)idleDelta / (double)totalDelta));
            }
        }
        
        self.lastTotalTicks = total;
        self.lastIdleTicks = idle;
    }
#else
    // OpenBSD/NetBSD have similar but slightly different sysctl interfaces
    // For simplicity, report 0% for now (can be enhanced later)
    self.cpuUsage = 0.0;
#endif
    
    // TODO: Per-core CPU on BSD (requires kern.cp_times)
    [self.perCoreCPU removeAllObjects];
}

- (void)updateRAMUsage
{
#ifdef __FreeBSD__
    size_t size;
    
    // Get total memory
    unsigned long memTotal = 0;
    size = sizeof(memTotal);
    if (sysctlbyname("hw.physmem", &memTotal, &size, NULL, 0) != 0) {
        return;
    }
    
    // Get free memory
    unsigned int pageSize = 0;
    size = sizeof(pageSize);
    if (sysctlbyname("hw.pagesize", &pageSize, &size, NULL, 0) != 0) {
        return;
    }
    
    unsigned int freePages = 0;
    size = sizeof(freePages);
    if (sysctlbyname("vm.stats.vm.v_free_count", &freePages, &size, NULL, 0) != 0) {
        return;
    }
    
    unsigned long memFree = (unsigned long)freePages * pageSize;
    unsigned long memUsed = memTotal - memFree;
    
    if (memTotal > 0) {
        self.ramUsage = 100.0 * memUsed / memTotal;
    }
#else
    // OpenBSD/NetBSD - simplified version
    self.ramUsage = 0.0;
#endif
}

#else

// Fallback for unsupported platforms
- (void)updateCPUUsage
{
    self.cpuUsage = 0.0;
    NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: CPU monitoring not supported on this platform");
}

- (void)updateRAMUsage
{
    self.ramUsage = 0.0;
    NSDebugLLog(@"gwcomp", @"SystemMonitorProvider: RAM monitoring not supported on this platform");
}

#endif

- (void)updateDetailMenu
{
    // Remove all items and rebuild
    [self.detailMenu removeAllItems];
    
    // CPU section
    NSMenuItem *cpuHeader = [[NSMenuItem alloc] initWithTitle:@"CPU Usage" action:nil keyEquivalent:@""];
    [cpuHeader setEnabled:NO];
    [self.detailMenu addItem:cpuHeader];
    
    NSMenuItem *cpuTotal = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"  Total: %.1f%%", self.cpuUsage]
                                                      action:nil
                                               keyEquivalent:@""];
    [cpuTotal setEnabled:NO];
    [self.detailMenu addItem:cpuTotal];
    
    // Per-core CPU
    for (NSUInteger i = 0; i < [self.perCoreCPU count]; i++) {
        double usage = [[self.perCoreCPU objectAtIndex:i] doubleValue];
        NSMenuItem *coreItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"  Core %lu: %.1f%%", (unsigned long)i, usage]
                                                          action:nil
                                                   keyEquivalent:@""];
        [coreItem setEnabled:NO];
        [self.detailMenu addItem:coreItem];
    }
    
    [self.detailMenu addItem:[NSMenuItem separatorItem]];
    
    // RAM section
    NSMenuItem *ramHeader = [[NSMenuItem alloc] initWithTitle:@"Memory Usage" action:nil keyEquivalent:@""];
    [ramHeader setEnabled:NO];
    [self.detailMenu addItem:ramHeader];
    
    NSMenuItem *ramTotal = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"  Used: %.1f%%", self.ramUsage]
                                                      action:nil
                                               keyEquivalent:@""];
    [ramTotal setEnabled:NO];
    [self.detailMenu addItem:ramTotal];
}

@end
