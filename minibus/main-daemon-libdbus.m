/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBDaemonLibDBus.h"
#import <signal.h>

static MBDaemonLibDBus *globalDaemon = nil;

static void signal_handler(int sig) {
    NSDebugLLog(@"gwcomp", @"Received signal %d, stopping daemon...", sig);
    if (globalDaemon) {
        [globalDaemon stop];
    }
}

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv; // Suppress unused parameter warnings
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSDebugLLog(@"gwcomp", @"Starting MiniBus daemon (libdbus version)...");
    
    MBDaemonLibDBus *daemon = [[MBDaemonLibDBus alloc] init];
    globalDaemon = daemon;
    
    // Start the daemon
    if (![daemon startWithSocketPath:@"/tmp/minibus-socket"]) {
        NSDebugLLog(@"gwcomp", @"Failed to start daemon");
        [daemon release];
        [pool drain];
        return 1;
    }
    
    // Set up signal handling
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    // Run main loop
    [daemon runMainLoop];
    
    [daemon release];
    globalDaemon = nil;
    [pool drain];
    
    NSDebugLLog(@"gwcomp", @"MiniBus daemon (libdbus version) stopped");
    return 0;
}
