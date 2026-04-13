/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBClient.h"
#import "MBMessage.h"

int main(int argc __attribute__((unused)), const char * argv[] __attribute__((unused)))
{
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"Simple MiniBus Test");
        
        MBClient *client = [[MBClient alloc] init];
        
        // Connect to daemon
        if (![client connectToPath:@"/tmp/minibus-socket"]) {
            NSDebugLLog(@"gwcomp", @"Failed to connect - is the daemon running?");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"✓ Connected to MiniBus daemon");
        NSDebugLLog(@"gwcomp", @"✓ Unique name: %@", client.uniqueName);
        
        // Simple ping test
        NSDebugLLog(@"gwcomp", @"Testing basic D-Bus functionality...");
        
        MBMessage *reply = [client callMethod:@"org.freedesktop.DBus"
                                         path:@"/org/freedesktop/DBus"
                                    interface:@"org.freedesktop.DBus" 
                                       member:@"ListNames"
                                    arguments:@[]
                                      timeout:3.0];
        
        if (reply && reply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"✓ D-Bus method call successful!");
            NSDebugLLog(@"gwcomp", @"✓ Available names: %@", reply.arguments);
        } else {
            NSDebugLLog(@"gwcomp", @"✗ D-Bus method call failed");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"✓ All tests passed - MiniBus is working!");
        
        [client disconnect];
    }
    
    return 0;
}
