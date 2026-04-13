/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

static NSUInteger alignTo(NSUInteger value, NSUInteger alignment) {
    return ((value + alignment - 1) / alignment) * alignment;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Create Hello reply exactly as MBDaemon does
        MBMessage *reply = [MBMessage methodReturnWithReplySerial:1
                                                        arguments:@[@":1.0"]];
        reply.destination = @":1.0";  // Reply is addressed to the client
        
        NSData *headerFields = [reply serializeHeaderFields];
        NSData *body = [reply serializeBody];
        
        NSDebugLLog(@"gwcomp", @"Header fields length: %lu bytes", (unsigned long)[headerFields length]);
        NSDebugLLog(@"gwcomp", @"Body length: %lu bytes", (unsigned long)[body length]);
        
        // Calculate alignment
        NSUInteger fixedHeaderLen = 16;
        NSUInteger currentLength = fixedHeaderLen + [headerFields length];
        NSUInteger alignedLength = alignTo(currentLength, 8);
        NSUInteger padding = alignedLength - currentLength;
        
        NSDebugLLog(@"gwcomp", @"Current length after header fields: %lu", currentLength);
        NSDebugLLog(@"gwcomp", @"Aligned length: %lu", alignedLength);
        NSDebugLLog(@"gwcomp", @"Padding needed: %lu bytes", padding);
        
        NSData *fullMessage = [reply serialize];
        NSDebugLLog(@"gwcomp", @"Full message length: %lu bytes", (unsigned long)[fullMessage length]);
        
        // Print the header fields raw bytes
        printf("Header fields raw (%lu bytes):\n", (unsigned long)[headerFields length]);
        const uint8_t *bytes = [headerFields bytes];
        for (NSUInteger i = 0; i < [headerFields length]; i += 16) {
            for (NSUInteger j = 0; j < 16 && i + j < [headerFields length]; j++) {
                printf("%02x ", bytes[i + j]);
            }
            printf("\n");
        }
        
        return 0;
    }
}
