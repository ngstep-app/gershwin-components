/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

// Debug the STRUCT parsing in detail
int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== STRUCT Parsing Debug ===");
        
        // Create a simple struct and serialize it
        NSArray *structData = @[@"test", @(123), @"end"];
        NSDebugLLog(@"gwcomp", @"Input struct: %@", structData);
        
        MBMessage *message = [MBMessage methodCallWithDestination:@"test.dest"
                                                             path:@"/test"
                                                        interface:@"test.interface"
                                                           member:@"TestMethod"
                                                        arguments:@[structData]];
        
        NSDebugLLog(@"gwcomp", @"Message signature: '%@'", message.signature);
        
        // Serialize it
        NSData *serialized = [message serialize];
        NSDebugLLog(@"gwcomp", @"Serialized length: %lu bytes", [serialized length]);
        
        // Now let's manually debug the parsing
        MBMessage *parsed = [MBMessage parseFromData:serialized];
        if (parsed) {
            NSDebugLLog(@"gwcomp", @"Parsed successfully");
            NSDebugLLog(@"gwcomp", @"Parsed signature: '%@'", parsed.signature);
            NSDebugLLog(@"gwcomp", @"Parsed arguments count: %lu", [parsed.arguments count]);
            
            if ([parsed.arguments count] > 0) {
                id arg = [parsed.arguments objectAtIndex:0];
                NSDebugLLog(@"gwcomp", @"First argument class: %@", [arg class]);
                if ([arg isKindOfClass:[NSArray class]]) {
                    NSArray *arr = (NSArray *)arg;
                    NSDebugLLog(@"gwcomp", @"Parsed struct fields: %lu", [arr count]);
                    for (NSUInteger i = 0; i < [arr count]; i++) {
                        id field = [arr objectAtIndex:i];
                        NSDebugLLog(@"gwcomp", @"  Field %lu: %@ (class: %@)", i, field, [field class]);
                    }
                }
            }
        } else {
            NSDebugLLog(@"gwcomp", @"ERROR: Parsing failed");
        }
        
        NSDebugLLog(@"gwcomp", @"\n=== Manual struct body parsing ===");
        
        // Let's manually parse just the body to see what happens
        NSData *bodyData = [message serializeBody];
        NSDebugLLog(@"gwcomp", @"Body data: %lu bytes", [bodyData length]);
        
        const uint8_t *bytes = [bodyData bytes];
        NSDebugLLog(@"gwcomp", @"Body bytes:");
        for (NSUInteger i = 0; i < [bodyData length]; i += 8) {
            NSMutableString *hexLine = [NSMutableString string];
            for (NSUInteger j = 0; j < 8 && i + j < [bodyData length]; j++) {
                [hexLine appendFormat:@"%02x ", bytes[i + j]];
            }
            NSDebugLLog(@"gwcomp", @"%04lx: %@", i, hexLine);
        }
        
        // Parse arguments manually 
        NSString *signature = @"(sus)";
        NSArray *parsedArgs = [MBMessage parseArgumentsFromBodyData:bodyData signature:signature endianness:'l'];
        NSDebugLLog(@"gwcomp", @"Manual parse result: %@", parsedArgs);
        if ([parsedArgs count] > 0) {
            id arg = [parsedArgs objectAtIndex:0];
            if ([arg isKindOfClass:[NSArray class]]) {
                NSArray *arr = (NSArray *)arg;
                NSDebugLLog(@"gwcomp", @"Manual parsed struct fields: %lu", [arr count]);
                for (NSUInteger i = 0; i < [arr count]; i++) {
                    id field = [arr objectAtIndex:i];
                    NSDebugLLog(@"gwcomp", @"  Manual field %lu: %@ (class: %@)", i, field, [field class]);
                }
            }
        }
        
        NSDebugLLog(@"gwcomp", @"\n=== Debug Complete ===");
    }
    return 0;
}
