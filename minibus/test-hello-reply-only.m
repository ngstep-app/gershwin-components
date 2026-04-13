/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Create Hello reply exactly as MBDaemon does
        MBMessage *reply = [MBMessage methodReturnWithReplySerial:1
                                                        arguments:@[@":1.0"]];
        reply.destination = @":1.0";  // Reply is addressed to the client
        // Note: Real dbus-daemon Hello replies do NOT include sender field
        
        NSDebugLLog(@"gwcomp", @"Hello Reply Properties:");
        NSDebugLLog(@"gwcomp", @"  Type: %d", reply.type);
        NSDebugLLog(@"gwcomp", @"  Reply Serial: %ld", reply.replySerial);
        NSDebugLLog(@"gwcomp", @"  Destination: %@", reply.destination);
        NSDebugLLog(@"gwcomp", @"  Signature: %@", reply.signature);
        NSDebugLLog(@"gwcomp", @"  Arguments: %@", reply.arguments);
        
        NSData *data = [reply serialize];
        
        printf("Hello Reply Only (%lu bytes):\n", (unsigned long)[data length]);
        const uint8_t *bytes = [data bytes];
        for (NSUInteger i = 0; i < [data length]; i += 16) {
            for (NSUInteger j = 0; j < 16 && i + j < [data length]; j++) {
                printf("%02x ", bytes[i + j]);
            }
            printf("\n");
        }
        
        return 0;
    }
}
