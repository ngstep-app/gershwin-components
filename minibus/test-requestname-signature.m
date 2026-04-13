/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBClient.h"
#import "MBMessage.h"

int main() {
    NSDebugLLog(@"gwcomp", @"Testing RequestName signature fix...");
    
    MBClient *client = [[MBClient alloc] init];
    if (![client connectToPath:@"/tmp/minibus-socket"]) {
        NSDebugLLog(@"gwcomp", @"Failed to connect to MiniBus");
        return 1;
    }
    
    // Test RequestName call 
    NSDebugLLog(@"gwcomp", @"Calling RequestName for com.test.SignatureTest...");
    
    MBMessage *reply = [client callMethod:@"org.freedesktop.DBus"
                                     path:@"/org/freedesktop/DBus"
                                interface:@"org.freedesktop.DBus"
                                   member:@"RequestName"
                                arguments:@[@"com.test.SignatureTest", @0]
                                  timeout:5.0];
    if (reply) {
        NSDebugLLog(@"gwcomp", @"Got reply:");
        NSDebugLLog(@"gwcomp", @"  Type: %lu", (unsigned long)reply.type);
        NSDebugLLog(@"gwcomp", @"  Signature: '%@'", reply.signature);
        NSDebugLLog(@"gwcomp", @"  Arguments: %@", reply.arguments);
        
        if ([reply.signature isEqualToString:@"u"]) {
            NSDebugLLog(@"gwcomp", @"SUCCESS: RequestName returns correct signature 'u' (uint32)");
        } else {
            NSDebugLLog(@"gwcomp", @"FAILED: RequestName returns incorrect signature '%@' (expected 'u')", reply.signature);
        }
    } else {
        NSDebugLLog(@"gwcomp", @"No reply received");
    }
    
    [client disconnect];
    return 0;
}
