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
        NSDebugLLog(@"gwcomp", @"MiniBus Simple Test Client - Testing message format only");
        
        NSString *socketPath = @"/tmp/minibus-socket";
        if (argc > 1) {
            socketPath = [NSString stringWithUTF8String:argv[1]];
        }
        
        MBClient *client = [[MBClient alloc] init];
        
        NSDebugLLog(@"gwcomp", @"Connecting to daemon at %@...", socketPath);
        if (![client connectToPathWithoutHello:socketPath]) {
            NSDebugLLog(@"gwcomp", @"Failed to connect to daemon");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Connected! Testing ListNames method call...");
        
        // Test ListNames without sending Hello first
        MBMessage *listReply = [client callMethod:@"org.freedesktop.DBus"
                                             path:@"/org/freedesktop/DBus"
                                        interface:@"org.freedesktop.DBus"
                                           member:@"ListNames"
                                        arguments:@[]
                                          timeout:5.0];
        
        if (listReply && listReply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"SUCCESS! ListNames returned: %@", listReply.arguments);
        } else if (listReply && listReply.type == MBMessageTypeError) {
            NSDebugLLog(@"gwcomp", @"ERROR from daemon: %@ - %@", listReply.errorName, listReply.arguments);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to get ListNames response");
        }
        
        NSDebugLLog(@"gwcomp", @"Test completed!");
        [client disconnect];
    }
    
    return 0;
}
