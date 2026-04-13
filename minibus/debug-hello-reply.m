/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBClient.h"
#import "MBMessage.h"
#import "MBTransport.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"Debug Hello Reply Processing");
        
        // Connect to daemon manually to debug
        int socket = [MBTransport connectToUnixSocket:@"/tmp/minibus-socket"];
        if (socket < 0) {
            NSDebugLLog(@"gwcomp", @"Failed to connect");
            return 1;
        }
        
        // Do authentication
        NSMutableData *authData = [NSMutableData data];
        uint8_t nullByte = 0;
        [authData appendBytes:&nullByte length:1];
        NSString *authCommand = @"AUTH EXTERNAL 31303031\r\n";
        [authData appendData:[authCommand dataUsingEncoding:NSUTF8StringEncoding]];
        
        [MBTransport sendData:authData onSocket:socket];
        usleep(100000);
        NSData *authResponse = [MBTransport receiveDataFromSocket:socket];
        NSDebugLLog(@"gwcomp", @"Auth response: %@", [[NSString alloc] initWithData:authResponse encoding:NSUTF8StringEncoding]);
        
        // Send NEGOTIATE_UNIX_FD
        NSString *negotiateCommand = @"NEGOTIATE_UNIX_FD\r\n";
        [MBTransport sendData:[negotiateCommand dataUsingEncoding:NSUTF8StringEncoding] onSocket:socket];
        usleep(100000);
        NSData *fdResponse = [MBTransport receiveDataFromSocket:socket];
        NSDebugLLog(@"gwcomp", @"FD response: %@", [[NSString alloc] initWithData:fdResponse encoding:NSUTF8StringEncoding]);
        
        // Send BEGIN
        NSString *beginCommand = @"BEGIN\r\n";
        [MBTransport sendData:[beginCommand dataUsingEncoding:NSUTF8StringEncoding] onSocket:socket];
        NSDebugLLog(@"gwcomp", @"BEGIN sent");
        
        // Send Hello
        MBMessage *helloMessage = [MBMessage methodCallWithDestination:@"org.freedesktop.DBus"
                                                                   path:@"/org/freedesktop/DBus"
                                                              interface:@"org.freedesktop.DBus"
                                                                 member:@"Hello"
                                                              arguments:@[]];
        helloMessage.serial = 1;
        NSData *helloData = [helloMessage serialize];
        NSDebugLLog(@"gwcomp", @"Sending Hello message (%lu bytes)", (unsigned long)[helloData length]);
        [MBTransport sendData:helloData onSocket:socket];
        
        // Wait for reply and debug it
        usleep(100000);
        NSData *replyData = [MBTransport receiveDataFromSocket:socket];
        NSDebugLLog(@"gwcomp", @"Received reply: %lu bytes", (unsigned long)[replyData length]);
        
        if (replyData && [replyData length] > 0) {
            // Try to parse as message
            NSUInteger offset = 0;
            MBMessage *reply = [MBMessage messageFromData:replyData offset:&offset];
            if (reply) {
                NSDebugLLog(@"gwcomp", @"Parsed reply message: type=%u, replySerial=%lu", reply.type, (unsigned long)reply.replySerial);
                NSDebugLLog(@"gwcomp", @"Reply signature: %@", reply.signature);
                NSDebugLLog(@"gwcomp", @"Reply arguments: %@", reply.arguments);
                NSDebugLLog(@"gwcomp", @"Reply arguments count: %lu", (unsigned long)[reply.arguments count]);
                if ([reply.arguments count] > 0) {
                    NSDebugLLog(@"gwcomp", @"Unique name from reply: %@", reply.arguments[0]);
                    NSDebugLLog(@"gwcomp", @"Argument class: %@", [reply.arguments[0] class]);
                }
            } else {
                NSDebugLLog(@"gwcomp", @"Failed to parse reply message");
                // Dump hex
                const uint8_t *bytes = [replyData bytes];
                NSMutableString *hexString = [NSMutableString string];
                for (NSUInteger i = 0; i < [replyData length]; i++) {
                    [hexString appendFormat:@"%02x ", bytes[i]];
                }
                NSDebugLLog(@"gwcomp", @"Reply hex: %@", hexString);
            }
        }
        
        [MBTransport closeSocket:socket];
        return 0;
    }
}
