/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

// Debug the STRUCT serialization to see what's happening
int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== STRUCT Serialization Debug ===");
        
        // Create a simple struct
        NSArray *structData = @[@"test", @(123), @"end"];
        NSDebugLLog(@"gwcomp", @"Input struct: %@", structData);
        
        // Create a message
        MBMessage *message = [MBMessage methodCallWithDestination:@"test.dest"
                                                             path:@"/test"
                                                        interface:@"test.interface"
                                                           member:@"TestMethod"
                                                        arguments:@[structData]];
        
        NSDebugLLog(@"gwcomp", @"Message signature: %@", message.signature);
        
        // Get the body data
        NSData *bodyData = [message serializeBody];
        NSDebugLLog(@"gwcomp", @"Body data length: %lu bytes", [bodyData length]);
        
        // Dump the body data
        const uint8_t *bytes = [bodyData bytes];
        NSDebugLLog(@"gwcomp", @"Body data bytes:");
        for (NSUInteger i = 0; i < [bodyData length]; i += 16) {
            NSMutableString *hexLine = [NSMutableString string];
            NSMutableString *asciiLine = [NSMutableString string];
            for (NSUInteger j = 0; j < 16 && i + j < [bodyData length]; j++) {
                [hexLine appendFormat:@"%02x ", bytes[i + j]];
                char c = bytes[i + j];
                [asciiLine appendFormat:@"%c", (c >= 32 && c <= 126) ? c : '.'];
            }
            NSDebugLLog(@"gwcomp", @"%04lx: %-48s %@", i, [hexLine UTF8String], asciiLine);
        }
        
        // Now let's manually parse this according to D-Bus spec
        NSDebugLLog(@"gwcomp", @"\n=== Manual Parse ===");
        NSUInteger pos = 0;
        
        // STRUCT should be 8-byte aligned first
        pos = ((pos + 7) / 8) * 8;
        NSDebugLLog(@"gwcomp", @"Aligned pos: %lu", pos);
        
        // Field 1: string
        pos = ((pos + 3) / 4) * 4; // 4-byte align for string
        NSDebugLLog(@"gwcomp", @"String pos: %lu", pos);
        if (pos + 4 <= [bodyData length]) {
            uint32_t strLen = *(uint32_t *)(bytes + pos);
            NSDebugLLog(@"gwcomp", @"String length: %u", strLen);
            pos += 4;
            
            if (pos + strLen + 1 <= [bodyData length]) {
                NSString *str = [[NSString alloc] initWithBytes:(bytes + pos)
                                                         length:strLen
                                                       encoding:NSUTF8StringEncoding];
                NSDebugLLog(@"gwcomp", @"String value: '%@'", str);
                pos += strLen + 1;
                [str release];
            }
        }
        
        // Field 2: uint32
        pos = ((pos + 3) / 4) * 4; // 4-byte align for uint32
        NSDebugLLog(@"gwcomp", @"uint32 pos: %lu", pos);
        if (pos + 4 <= [bodyData length]) {
            uint32_t value = *(uint32_t *)(bytes + pos);
            NSDebugLLog(@"gwcomp", @"uint32 value: %u", value);
            pos += 4;
        }
        
        // Field 3: string
        pos = ((pos + 3) / 4) * 4; // 4-byte align for string
        NSDebugLLog(@"gwcomp", @"String2 pos: %lu", pos);
        if (pos + 4 <= [bodyData length]) {
            uint32_t strLen = *(uint32_t *)(bytes + pos);
            NSDebugLLog(@"gwcomp", @"String2 length: %u", strLen);
            pos += 4;
            
            if (pos + strLen + 1 <= [bodyData length]) {
                NSString *str = [[NSString alloc] initWithBytes:(bytes + pos)
                                                         length:strLen
                                                       encoding:NSUTF8StringEncoding];
                NSDebugLLog(@"gwcomp", @"String2 value: '%@'", str);
                pos += strLen + 1;
                [str release];
            }
        }
        
        NSDebugLLog(@"gwcomp", @"Final pos: %lu", pos);
        NSDebugLLog(@"gwcomp", @"\n=== Debug Complete ===");
    }
    return 0;
}
