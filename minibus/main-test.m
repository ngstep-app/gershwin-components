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
        NSDebugLLog(@"gwcomp", @"MiniBus Test Client");
        
        NSString *socketPath = @"/tmp/minibus-socket";
        if (argc > 1) {
            socketPath = [NSString stringWithUTF8String:argv[1]];
        }
        
        MBClient *client = [[MBClient alloc] init];
        
        NSDebugLLog(@"gwcomp", @"Connecting to daemon at %@...", socketPath);
        if (![client connectToPath:socketPath]) {
            NSDebugLLog(@"gwcomp", @"Failed to connect to daemon");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Connected! Unique name: %@", client.uniqueName);
        
        // Test 1: Request a name
        NSDebugLLog(@"gwcomp", @"Testing name registration...");
        NSString *testName = @"com.example.TestService";
        if ([client requestName:testName]) {
            NSDebugLLog(@"gwcomp", @"Successfully registered name: %@", testName);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to register name: %@", testName);
        }
        
        // Test 2: List names
        NSDebugLLog(@"gwcomp", @"Testing ListNames...");
        MBMessage *listReply = [client callMethod:@"org.freedesktop.DBus"
                                             path:@"/org/freedesktop/DBus"
                                        interface:@"org.freedesktop.DBus"
                                           member:@"ListNames"
                                        arguments:@[]
                                          timeout:5.0];
        
        if (listReply && listReply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"Available names: %@", listReply.arguments);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to list names");
        }
        
        // Test 3: Get name owner
        NSDebugLLog(@"gwcomp", @"Testing GetNameOwner...");
        MBMessage *ownerReply = [client callMethod:@"org.freedesktop.DBus"
                                              path:@"/org/freedesktop/DBus"
                                         interface:@"org.freedesktop.DBus"
                                            member:@"GetNameOwner"
                                         arguments:@[testName]
                                           timeout:5.0];
        
        if (ownerReply && ownerReply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"Owner of %@: %@", testName, ownerReply.arguments);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to get name owner or name not found");
        }
        
        // Test 4: Send a signal
        NSDebugLLog(@"gwcomp", @"Testing signal emission...");
        if ([client emitSignal:@"/com/example/Test"
                     interface:@"com.example.Test"
                        member:@"TestSignal"
                     arguments:@[@"Hello from test client!", @42]]) {
            NSDebugLLog(@"gwcomp", @"Signal sent successfully");
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to send signal");
        }
        
        // Test 5: Release name
        NSDebugLLog(@"gwcomp", @"Testing name release...");
        if ([client releaseName:testName]) {
            NSDebugLLog(@"gwcomp", @"Successfully released name: %@", testName);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to release name: %@", testName);
        }
        
        NSDebugLLog(@"gwcomp", @"Test completed successfully!");
        [client disconnect];
    }
    
    return 0;
}
