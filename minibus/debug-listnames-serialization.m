/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

int main(void) {
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== TESTING LISTNAMES SERIALIZATION ===");
        
        // Create the same array that would be sent in ListNames
        NSArray *names = @[@"org.freedesktop.DBus", @"org.xfce.Panel", @":1.1"];
        
        // Create a ListNames reply message
        MBMessage *reply = [MBMessage methodReturnWithReplySerial:19 arguments:@[names]];
        reply.sender = @"org.freedesktop.DBus";
        reply.destination = @":1.1";
        
        NSDebugLLog(@"gwcomp", @"Reply signature: %@", reply.signature);
        NSDebugLLog(@"gwcomp", @"Reply arguments: %@", reply.arguments);
        
        // Serialize it
        NSData *serialized = [reply serialize];
        NSDebugLLog(@"gwcomp", @"Serialized to %lu bytes", (unsigned long)[serialized length]);
        
        // Print hex dump
        const uint8_t *bytes = [serialized bytes];
        for (NSUInteger i = 0; i < [serialized length]; i += 16) {
            printf("%04lx: ", (unsigned long)i);
            for (NSUInteger j = 0; j < 16 && i + j < [serialized length]; j++) {
                printf("%02x ", bytes[i + j]);
            }
            printf("\\n");
        }
        
        // Try to parse it back
        NSDebugLLog(@"gwcomp", @"\\n=== TESTING PARSING ===");
        NSUInteger offset = 0;
        MBMessage *parsed = [MBMessage messageFromData:serialized offset:&offset];
        
        if (parsed) {
            NSDebugLLog(@"gwcomp", @"Successfully parsed back!");
            NSDebugLLog(@"gwcomp", @"Parsed signature: %@", parsed.signature);
            NSDebugLLog(@"gwcomp", @"Parsed arguments: %@", parsed.arguments);
        } else {
            NSDebugLLog(@"gwcomp", @"FAILED to parse back!");
        }
    }
    return 0;
}
