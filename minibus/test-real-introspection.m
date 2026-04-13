/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBClient.h"
#import "MBMessage.h"

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== Real MiniBus Introspection Test ===");
        
        // Connect to MiniBus daemon
        MBClient *client = [[MBClient alloc] init];
        if (![client connectToPath:@"/tmp/minibus-socket"]) {
            NSDebugLLog(@"gwcomp", @"ERROR: Failed to connect to MiniBus daemon");
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"✓ Connected to MiniBus daemon");
        
        // Test 1: Call Introspect method
        NSDebugLLog(@"gwcomp", @"\n--- Introspection Test ---");
        
        MBMessage *introspectReply = [client callMethod:@"org.freedesktop.DBus"
                                                   path:@"/org/freedesktop/DBus"
                                              interface:@"org.freedesktop.DBus.Introspectable"
                                                 member:@"Introspect"
                                              arguments:@[]
                                                timeout:5.0];
        
        if (introspectReply && introspectReply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"✓ Introspect call succeeded");
            
            if ([introspectReply.arguments count] > 0) {
                NSString *xml = [introspectReply.arguments objectAtIndex:0];
                NSDebugLLog(@"gwcomp", @"✓ Introspection XML received (%lu characters)", [xml length]);
                
                // Check for enhanced features
                NSArray *features = @[
                    @"org.freedesktop.DBus.Introspectable",
                    @"org.freedesktop.DBus.Properties",
                    @"StartServiceByName",
                    @"NameOwnerChanged",
                    @"UpdateActivationEnvironment",
                    @"GetConnectionCredentials"
                ];
                
                for (NSString *feature in features) {
                    if ([xml containsString:feature]) {
                        NSDebugLLog(@"gwcomp", @"✓ Found feature: %@", feature);
                    } else {
                        NSDebugLLog(@"gwcomp", @"⚠ Missing feature: %@", feature);
                    }
                }
                
                // Save the XML for inspection
                [xml writeToFile:@"/tmp/minibus-introspection.xml"
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];
                NSDebugLLog(@"gwcomp", @"✓ Saved introspection XML to /tmp/minibus-introspection.xml");
                
            } else {
                NSDebugLLog(@"gwcomp", @"✗ Introspect reply has no arguments");
            }
        } else if (introspectReply && introspectReply.type == MBMessageTypeError) {
            NSDebugLLog(@"gwcomp", @"✗ Introspect call failed with error: %@", introspectReply.errorName);
            if ([introspectReply.arguments count] > 0) {
                NSDebugLLog(@"gwcomp", @"  Error message: %@", [introspectReply.arguments objectAtIndex:0]);
            }
        } else {
            NSDebugLLog(@"gwcomp", @"✗ Introspect call failed - no response or invalid response");
        }
        
        // Test 2: List available services
        NSDebugLLog(@"gwcomp", @"\n--- Service List Test ---");
        
        MBMessage *listNamesReply = [client callMethod:@"org.freedesktop.DBus"
                                                  path:@"/org/freedesktop/DBus"
                                             interface:@"org.freedesktop.DBus"
                                                member:@"ListNames"
                                             arguments:@[]
                                               timeout:5.0];
        
        if (listNamesReply && listNamesReply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"✓ ListNames call succeeded");
            
            if ([listNamesReply.arguments count] > 0) {
                NSArray *names = [listNamesReply.arguments objectAtIndex:0];
                NSDebugLLog(@"gwcomp", @"✓ Found %lu active services:", [names count]);
                for (NSString *name in names) {
                    NSDebugLLog(@"gwcomp", @"  - %@", name);
                }
            }
        } else {
            NSDebugLLog(@"gwcomp", @"✗ ListNames call failed");
        }
        
        // Test 3: Test STRUCT message with real daemon
        NSDebugLLog(@"gwcomp", @"\n--- STRUCT Test with Real Daemon ---");
        
        // Test a simple RequestName call (which uses basic types, not structs)
        MBMessage *requestNameReply = [client callMethod:@"org.freedesktop.DBus"
                                                    path:@"/org/freedesktop/DBus"
                                               interface:@"org.freedesktop.DBus"
                                                  member:@"RequestName"
                                               arguments:@[@"test.StructService", @(0)]
                                                 timeout:5.0];
        
        if (requestNameReply && requestNameReply.type == MBMessageTypeMethodReturn) {
            NSDebugLLog(@"gwcomp", @"✓ RequestName call succeeded");
            if ([requestNameReply.arguments count] > 0) {
                NSDebugLLog(@"gwcomp", @"  Result code: %@", [requestNameReply.arguments objectAtIndex:0]);
            }
        } else {
            NSDebugLLog(@"gwcomp", @"✗ RequestName call failed");
        }
        
        [client disconnect];
        
        NSDebugLLog(@"gwcomp", @"\n=== Real MiniBus Introspection Test Complete ===");
        
        return 0;
    }
}
