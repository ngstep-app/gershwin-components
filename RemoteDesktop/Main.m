/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// main.m
// Remote Desktop - Application entry point
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "RemoteDesktop.h"

int main(int argc, char *argv[])
{
    CREATE_AUTORELEASE_POOL(pool);
    
    NSApplication *app = [NSApplication sharedApplication];
    RemoteDesktop *controller = [[RemoteDesktop alloc] init];
    
    [app setDelegate:controller];
    
    // Parse command line arguments
    NSString *hostname = nil;
    NSString *username = nil;
    NSString *password = nil;
    NSString *protocol = @"vnc"; // Default to VNC
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--host") == 0 || strcmp(argv[i], "-h") == 0) {
            if (i + 1 < argc) {
                hostname = [NSString stringWithUTF8String:argv[++i]];
            }
        } else if (strcmp(argv[i], "--user") == 0 || strcmp(argv[i], "-u") == 0) {
            if (i + 1 < argc) {
                username = [NSString stringWithUTF8String:argv[++i]];
            }
        } else if (strcmp(argv[i], "--password") == 0 || strcmp(argv[i], "-p") == 0) {
            if (i + 1 < argc) {
                password = [NSString stringWithUTF8String:argv[++i]];
            }
        } else if (strcmp(argv[i], "--protocol") == 0) {
            if (i + 1 < argc) {
                protocol = [NSString stringWithUTF8String:argv[++i]];
            }
        } else if (strcmp(argv[i], "--help") == 0) {
            printf("RemoteDesktop - VNC/RDP Client\n");
            printf("\nUsage: %s [options]\n", argv[0]);
            printf("\nOptions:\n");
            printf("  -h, --host <hostname>        Connect to specified host\n");
            printf("  --protocol <vnc|rdp>         Protocol to use (default: vnc)\n");
            printf("  -u, --user <username>        Username for connection (optional)\n");
            printf("  -p, --password <pass>        Password for connection (optional)\n");
            printf("  --help                       Show this help message\n");
            printf("\nExamples:\n");
            printf("  %s --host Users-Mac-mini.local\n", argv[0]);
            printf("  %s --host 192.168.1.100 --protocol vnc --password secret\n", argv[0]);
            printf("  %s --host 192.168.1.200 --protocol rdp --user admin --password secret\n", argv[0]);
            exit(0);
        }
    }
    
    // Schedule auto-connect if hostname provided
    if (hostname) {
        NSLog(@"RemoteDesktop: Command line connection requested to %@", hostname);
        
        // Set CLI mode to skip browser window
        [controller setCliMode:YES];
        
        // Use NSInvocation to call method with multiple arguments after delay
        NSMethodSignature *signature = [controller methodSignatureForSelector:@selector(connectFromCommandLine:protocol:username:password:)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:controller];
        [invocation setSelector:@selector(connectFromCommandLine:protocol:username:password:)];
        [invocation setArgument:&hostname atIndex:2];
        [invocation setArgument:&protocol atIndex:3];
        [invocation setArgument:&username atIndex:4];
        [invocation setArgument:&password atIndex:5];
        [invocation retainArguments];
        
        [invocation performSelector:@selector(invoke) withObject:nil afterDelay:0.5];
    }
    
    [app run];
    
    RELEASE(controller);
    RELEASE(pool);
    
    return 0;
}
