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
        
        NSDebugLLog(@"gwcomp", @"Testing auto-activation by sending message to %@", serviceName);
        
        MBClient *client = [[MBClient alloc] init];
        
        if (![client connectToPath:socketPath]) {
            NSDebugLLog(@"gwcomp", @"Failed to connect to daemon");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Connected! Unique name: %@", client.uniqueName);
        
        // Send a method call to the service - this should trigger auto-activation
        NSDebugLLog(@"gwcomp", @"Sending method call to trigger auto-activation...");
        MBMessage *reply = [client callMethod:serviceName
                                         path:@"/com/example/TestService" 
                                    interface:@"com.example.TestService"
                                       member:@"TestMethod"
                                    arguments:@[@"Hello"]
                                      timeout:15.0];
        
        if (reply && reply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"SUCCESS: Received method return from auto-activated service");
            if ([reply.arguments count] > 0) {
                NSDebugLLog(@"gwcomp", @"Reply: %@", [reply.arguments objectAtIndex:0]);
            }
        } else if (reply && reply.type == MBMessageTypeError) {
            NSDebugLLog(@"gwcomp", @"ERROR: Method call failed: %@", reply.errorName);
            if ([reply.arguments count] > 0) {
                NSDebugLLog(@"gwcomp", @"Error message: %@", [reply.arguments objectAtIndex:0]);
            }
        } else {
            NSDebugLLog(@"gwcomp", @"ERROR: No reply or timeout");
            return 1;
        }
        
        [client disconnect];
        [client release];
    }
    return 0;
}
