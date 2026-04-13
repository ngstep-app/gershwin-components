/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MBMessage.h"

int main() {
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"Testing StartServiceByName argument parsing...");
        
        // Create a test StartServiceByName message similar to what GLib would send
        MBMessage *message = [[MBMessage alloc] init];
        message.type = MBMessageTypeMethodCall;
        message.path = @"/org/freedesktop/DBus";
        message.interface = @"org.freedesktop.DBus";
        message.member = @"StartServiceByName";
        message.destination = @"org.freedesktop.DBus";
        message.signature = @"su";
        message.serial = 123;
        
        // Test arguments: service name + flags
        message.arguments = @[@"org.gtk.vfs.Daemon", @0];
        
        // Serialize the message
        NSData *serialized = [message serialize];
        NSDebugLLog(@"gwcomp", @"Serialized StartServiceByName message: %lu bytes", [serialized length]);
        
        // Parse it back
        NSUInteger offset = 0;
        MBMessage *parsed = [MBMessage messageFromData:serialized offset:&offset];
        
        if (parsed) {
            NSDebugLLog(@"gwcomp", @"Parsed message successfully:");
            NSDebugLLog(@"gwcomp", @"  Member: %@", parsed.member);
            NSDebugLLog(@"gwcomp", @"  Signature: %@", parsed.signature);
            NSDebugLLog(@"gwcomp", @"  Arguments count: %lu", [parsed.arguments count]);
            for (NSUInteger i = 0; i < [parsed.arguments count]; i++) {
                NSDebugLLog(@"gwcomp", @"    Arg[%lu]: %@ (type: %@)", i, parsed.arguments[i], [parsed.arguments[i] class]);
            }
            
            // Test the condition that fails
            if ([parsed.arguments count] < 2) {
                NSDebugLLog(@"gwcomp", @"ERROR: Would fail argument count check!");
            } else {
                NSDebugLLog(@"gwcomp", @"SUCCESS: Arguments look correct");
                NSString *serviceName = parsed.arguments[0];
                NSUInteger flags = [parsed.arguments[1] unsignedIntegerValue];
                NSDebugLLog(@"gwcomp", @"  Service: %@, Flags: %lu", serviceName, flags);
            }
        } else {
            NSDebugLLog(@"gwcomp", @"FAILED to parse message back!");
        }
        
        [message release];
        return 0;
    }
}
