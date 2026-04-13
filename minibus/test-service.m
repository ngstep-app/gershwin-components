/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBClient.h"
#import "MBMessage.h"

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSString *socketPath = @"/tmp/minibus-socket";
        NSString *serviceName = @"com.example.TestService";
        int sleepTime = 10;
        
        // Parse command line arguments
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "-socket") == 0 && i + 1 < argc) {
                socketPath = [NSString stringWithUTF8String:argv[i + 1]];
                i++;
            } else if (strcmp(argv[i], "-name") == 0 && i + 1 < argc) {
                serviceName = [NSString stringWithUTF8String:argv[i + 1]];
                i++;
            } else if (strcmp(argv[i], "-sleep") == 0 && i + 1 < argc) {
                sleepTime = atoi(argv[i + 1]);
                i++;
            }
        }
        
        NSDebugLLog(@"gwcomp", @"Test Service Starting:");
        NSDebugLLog(@"gwcomp", @"  Socket: %@", socketPath);
        NSDebugLLog(@"gwcomp", @"  Service Name: %@", serviceName);
        NSDebugLLog(@"gwcomp", @"  Sleep Time: %d seconds", sleepTime);
        NSDebugLLog(@"gwcomp", @"  DBUS_STARTER_ADDRESS: %s", getenv("DBUS_STARTER_ADDRESS") ?: "(not set)");
        NSDebugLLog(@"gwcomp", @"  DBUS_STARTER_BUS_TYPE: %s", getenv("DBUS_STARTER_BUS_TYPE") ?: "(not set)");
        
        // Use DBUS_STARTER_ADDRESS if provided by the daemon
        const char *starterAddress = getenv("DBUS_STARTER_ADDRESS");
        if (starterAddress) {
            NSString *starterAddressStr = [NSString stringWithUTF8String:starterAddress];
            NSDebugLLog(@"gwcomp", @"Using starter address: %@", starterAddressStr);
            
            // Parse D-Bus address format: unix:path=/tmp/socket
            if ([starterAddressStr hasPrefix:@"unix:path="]) {
                socketPath = [starterAddressStr substringFromIndex:10]; // Skip "unix:path="
                NSDebugLLog(@"gwcomp", @"Parsed socket path: %@", socketPath);
            } else {
                NSDebugLLog(@"gwcomp", @"Unknown D-Bus address format: %@", starterAddressStr);
                socketPath = starterAddressStr; // Fallback
            }
        }
        
        MBClient *client = [[MBClient alloc] init];
        
        NSDebugLLog(@"gwcomp", @"Connecting to daemon at %@...", socketPath);
        if (![client connectToPath:socketPath]) {
            NSDebugLLog(@"gwcomp", @"Failed to connect to daemon");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Connected! Unique name: %@", client.uniqueName);
        
        // Register the service name
        NSDebugLLog(@"gwcomp", @"Registering service name: %@", serviceName);
        if ([client requestName:serviceName]) {
            NSDebugLLog(@"gwcomp", @"Successfully registered name: %@", serviceName);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to register name: %@", serviceName);
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Service activated successfully! Sleeping for %d seconds...", sleepTime);
        sleep(sleepTime);
        
        NSDebugLLog(@"gwcomp", @"Test service exiting");
        [client disconnect];
        [client release];
    }
    return 0;
}
