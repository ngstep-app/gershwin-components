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
        
        if (argc > 1) {
            socketPath = [NSString stringWithUTF8String:argv[1]];
        }
        if (argc > 2) {
            serviceName = [NSString stringWithUTF8String:argv[2]];
        }
        
        NSDebugLLog(@"gwcomp", @"Testing StartServiceByName for %@", serviceName);
        
        MBClient *client = [[MBClient alloc] init];
        
        if (![client connectToPath:socketPath]) {
            NSDebugLLog(@"gwcomp", @"Failed to connect to daemon");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Connected! Unique name: %@", client.uniqueName);
        
        NSDebugLLog(@"gwcomp", @"Sending StartServiceByName request...");
        MBMessage *reply = [client callMethod:@"org.freedesktop.DBus"
                                         path:@"/org/freedesktop/DBus"
                                    interface:@"org.freedesktop.DBus"
                                       member:@"StartServiceByName"
                                    arguments:@[serviceName, @0]
                                      timeout:30.0];
        
        if (reply && reply.type == MBMessageTypeMethodReturn) {
            if ([reply.arguments count] > 0) {
                NSUInteger result = [[reply.arguments objectAtIndex:0] unsignedIntegerValue];
                switch (result) {
                    case 1:
                        NSDebugLLog(@"gwcomp", @"SUCCESS: Service was already running");
                        break;
                    case 2:
                        NSDebugLLog(@"gwcomp", @"SUCCESS: Service was started");
                        break;
                    default:
                        NSDebugLLog(@"gwcomp", @"SUCCESS: StartServiceByName returned %lu", (unsigned long)result);
                        break;
                }
            } else {
                NSDebugLLog(@"gwcomp", @"SUCCESS: StartServiceByName completed");
            }
        } else if (reply && reply.type == MBMessageTypeError) {
            NSDebugLLog(@"gwcomp", @"ERROR: StartServiceByName failed: %@", reply.errorName);
            if ([reply.arguments count] > 0) {
                NSDebugLLog(@"gwcomp", @"Error message: %@", [reply.arguments objectAtIndex:0]);
            }
            return 1;
        } else {
            NSDebugLLog(@"gwcomp", @"ERROR: No reply or timeout");
            return 1;
        }
        
        [client disconnect];
        [client release];
    }
    return 0;
}
