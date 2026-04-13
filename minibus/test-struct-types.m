/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

// Test program to verify STRUCT type parsing and serialization
int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== STRUCT Type Test ===");
        
        // Test 1: Create a struct with mixed types (string, uint32, string)
        NSArray *structData = @[@"test-string", @(12345), @"another-string"];
        NSDebugLLog(@"gwcomp", @"Test 1: Creating STRUCT with data: %@", structData);
        
        // Generate signature for this struct
        NSString *signature = [MBMessage signatureForArguments:@[structData]];
        NSDebugLLog(@"gwcomp", @"Generated signature: %@", signature);
        
        // Test 2: Create a message with struct arguments
        MBMessage *message = [MBMessage methodCallWithDestination:@"com.example.StructTest"
                                                             path:@"/com/example/StructTest"
                                                        interface:@"com.example.StructTest"
                                                           member:@"TestMethod"
                                                        arguments:@[structData]];
        
        NSDebugLLog(@"gwcomp", @"Created message with STRUCT argument");
        NSDebugLLog(@"gwcomp", @"Message signature: %@", message.signature);
        
        // Test 3: Serialize the message
        NSData *serialized = [message serialize];
        NSDebugLLog(@"gwcomp", @"Serialized message length: %lu bytes", [serialized length]);
        
        // Test 4: Parse the message back
        MBMessage *parsed = [MBMessage parseFromData:serialized];
        if (parsed) {
            NSDebugLLog(@"gwcomp", @"Successfully parsed message back");
            NSDebugLLog(@"gwcomp", @"Parsed signature: %@", parsed.signature);
            NSDebugLLog(@"gwcomp", @"Parsed arguments: %@", parsed.arguments);
            
            if ([parsed.arguments count] > 0) {
                id parsedStruct = [parsed.arguments objectAtIndex:0];
                if ([parsedStruct isKindOfClass:[NSArray class]]) {
                    NSArray *structArray = (NSArray *)parsedStruct;
                    NSDebugLLog(@"gwcomp", @"Parsed struct has %lu fields:", [structArray count]);
                    for (NSUInteger i = 0; i < [structArray count]; i++) {
                        NSDebugLLog(@"gwcomp", @"  Field %lu: %@ (class: %@)", i, [structArray objectAtIndex:i], 
                              [[structArray objectAtIndex:i] class]);
                    }
                } else {
                    NSDebugLLog(@"gwcomp", @"Parsed argument is not an array: %@ (class: %@)", parsedStruct, [parsedStruct class]);
                }
            }
        } else {
            NSDebugLLog(@"gwcomp", @"ERROR: Failed to parse message back");
        }
        
        // Test 5: Create a more complex struct with nested types
        NSArray *complexStruct = @[@"outer-string", @(999), @[@"inner-string", @(888)]];
        NSDebugLLog(@"gwcomp", @"\nTest 5: Complex nested struct: %@", complexStruct);
        
        NSString *complexSig = [MBMessage signatureForArguments:@[complexStruct]];
        NSDebugLLog(@"gwcomp", @"Complex struct signature: %@", complexSig);
        
        // Test 6: Test struct in variant
        NSDebugLLog(@"gwcomp", @"\nTest 6: Testing struct as variant");
        NSMutableData *variantData = [NSMutableData data];
        [MBMessage serializeVariant:structData toData:variantData];
        NSDebugLLog(@"gwcomp", @"Serialized struct variant: %lu bytes", [variantData length]);
        
        // Dump some bytes for debugging
        const uint8_t *bytes = [variantData bytes];
        NSDebugLLog(@"gwcomp", @"First 64 bytes of variant data:");
        for (NSUInteger i = 0; i < MIN(64, [variantData length]); i += 16) {
            NSMutableString *hexLine = [NSMutableString string];
            NSMutableString *asciiLine = [NSMutableString string];
            for (NSUInteger j = 0; j < 16 && i + j < [variantData length]; j++) {
                [hexLine appendFormat:@"%02x ", bytes[i + j]];
                char c = bytes[i + j];
                [asciiLine appendFormat:@"%c", (c >= 32 && c <= 126) ? c : '.'];
            }
            NSDebugLLog(@"gwcomp", @"%04lx: %-48s %@", i, [hexLine UTF8String], asciiLine);
        }
        
        NSDebugLLog(@"gwcomp", @"\n=== STRUCT Test Complete ===");
    }
    return 0;
}
