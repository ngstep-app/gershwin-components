/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

int main(int argc, const char * argv[]) {
    (void)argc; (void)argv; // Suppress unused parameter warnings
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"Testing array parsing with MBMessage");
        
        // Create a message with an array argument
        NSArray *testArray = @[@"first", @"second", @"third"];
        MBMessage *message = [MBMessage methodCallWithDestination:@"org.test.Service"
                                                             path:@"/org/test/Object"
                                                        interface:@"org.test.Interface"
                                                           member:@"TestMethod"
                                                        arguments:@[testArray]];
        
        NSDebugLLog(@"gwcomp", @"Created message: %@", message);
        NSDebugLLog(@"gwcomp", @"Message signature: %@", [message signature]);
        
        // Serialize the message
        NSData *data = [message serialize];
        NSDebugLLog(@"gwcomp", @"Serialized message to %lu bytes", (unsigned long)[data length]);
        
        // Try to parse it back
        NSDebugLLog(@"gwcomp", @"Attempting to parse message from data...");
        MBMessage *parsedMessage = [MBMessage messageFromData:data offset:0];
        
        if (parsedMessage) {
            NSDebugLLog(@"gwcomp", @"Successfully parsed message: %@", parsedMessage);
            NSDebugLLog(@"gwcomp", @"Parsed arguments: %@", parsedMessage.arguments);
            
            if ([parsedMessage.arguments count] > 0) {
                id firstArg = parsedMessage.arguments[0];
                if ([firstArg isKindOfClass:[NSArray class]]) {
                    NSArray *parsedArray = (NSArray *)firstArg;
                    NSDebugLLog(@"gwcomp", @"Parsed array has %lu elements:", (unsigned long)[parsedArray count]);
                    for (NSUInteger i = 0; i < [parsedArray count]; i++) {
                        NSDebugLLog(@"gwcomp", @"  [%lu]: %@", i, parsedArray[i]);
                    }
                } else {
                    NSDebugLLog(@"gwcomp", @"First argument is not an array: %@", firstArg);
                }
            } else {
                NSDebugLLog(@"gwcomp", @"No arguments parsed");
            }
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to parse message from data");
        }
    }
    return 0;
}
