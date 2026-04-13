/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

// Debug the STRUCT serialization in detail
int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== STRUCT Serialization Detail Debug ===");
        
        // Create a simple struct
        NSArray *structData = @[@"test", @(123), @"end"];
        NSDebugLLog(@"gwcomp", @"Input struct: %@", structData);
        
        // Test signature generation first
        NSString *signature = [MBMessage signatureForArguments:@[structData]];
        NSDebugLLog(@"gwcomp", @"Generated signature: '%@'", signature);
        NSDebugLLog(@"gwcomp", @"Signature contains '(': %@", [signature containsString:@"("] ? @"YES" : @"NO");
        
        // Create a message manually to control the signature
        MBMessage *message = [[MBMessage alloc] init];
        message.type = 1; // METHOD_CALL
        message.destination = @"test.dest";
        message.path = @"/test";
        message.interface = @"test.interface";
        message.member = @"TestMethod";
        message.arguments = @[structData];
        message.signature = @"(sus)"; // Force the signature
        
        NSDebugLLog(@"gwcomp", @"Message signature: '%@'", message.signature);
        NSDebugLLog(@"gwcomp", @"Message signature contains '(': %@", [message.signature containsString:@"("] ? @"YES" : @"NO");
        
        // Let's test what happens during serialization
        NSDebugLLog(@"gwcomp", @"About to serialize body...");
        
        // Check argument type
        id arg = [message.arguments objectAtIndex:0];
        NSDebugLLog(@"gwcomp", @"Argument class: %@", [arg class]);
        NSDebugLLog(@"gwcomp", @"Is NSArray: %@", [arg isKindOfClass:[NSArray class]] ? @"YES" : @"NO");
        
        [message release];
        NSDebugLLog(@"gwcomp", @"\n=== Debug Complete ===");
    }
    return 0;
}
