/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBClient.h"
#import "MBMessage.h"

int main() {
    NSDebugLLog(@"gwcomp", @"Testing StartServiceByName signature fix...");
    
    MBClient *client = [[MBClient alloc] init];
    if (![client connectToPath:@"/tmp/minibus-socket"]) {
        NSDebugLLog(@"gwcomp", @"Failed to connect to MiniBus");
        return 1;
    }
    
    // Test StartServiceByName call for org.freedesktop.DBus (should return DBUS_START_REPLY_ALREADY_RUNNING = 1)
    NSDebugLLog(@"gwcomp", @"Calling StartServiceByName for org.freedesktop.DBus...");
    
    MBMessage *reply = [client callMethod:@"org.freedesktop.DBus"
                                     path:@"/org/freedesktop/DBus"
                                interface:@"org.freedesktop.DBus"
                                   member:@"StartServiceByName"
                                arguments:@[@"org.freedesktop.DBus", @0]
                                  timeout:5.0];
    if (reply) {
        NSDebugLLog(@"gwcomp", @"Got reply:");
        NSDebugLLog(@"gwcomp", @"  Type: %lu", (unsigned long)reply.type);
        NSDebugLLog(@"gwcomp", @"  Signature: '%@'", reply.signature);
        NSDebugLLog(@"gwcomp", @"  Arguments: %@", reply.arguments);
        
        if ([reply.signature isEqualToString:@"u"]) {
            NSDebugLLog(@"gwcomp", @"SUCCESS: StartServiceByName returns correct signature 'u' (uint32)");
        } else {
            NSDebugLLog(@"gwcomp", @"FAILED: StartServiceByName returns incorrect signature '%@' (expected 'u')", reply.signature);
        }
    } else {
        NSDebugLLog(@"gwcomp", @"No reply received");
    }
    
    [client disconnect];
    return 0;
}
