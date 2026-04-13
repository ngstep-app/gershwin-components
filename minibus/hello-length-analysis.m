/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "MBMessage.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== Hello Reply Length Analysis ===");
        
        // Create Hello reply exactly as MBDaemon does
        MBMessage *reply = [MBMessage methodReturnWithReplySerial:1
                                                        arguments:@[@":1.0"]];
        reply.destination = @":1.0";
        reply.sender = @"org.freedesktop.DBus";
        
        NSDebugLLog(@"gwcomp", @"Hello Reply Properties:");
        NSDebugLLog(@"gwcomp", @"  Type: %d", reply.type);
        NSDebugLLog(@"gwcomp", @"  Reply Serial: %ld", reply.replySerial);
        NSDebugLLog(@"gwcomp", @"  Destination: %@", reply.destination);
        NSDebugLLog(@"gwcomp", @"  Sender: %@", reply.sender);
        NSDebugLLog(@"gwcomp", @"  Signature: %@", reply.signature);
        NSDebugLLog(@"gwcomp", @"  Arguments: %@", reply.arguments);
        
        // Get individual components
        NSData *headerFields = [reply serializeHeaderFields];
        NSData *body = [reply serializeBody];
        NSData *fullMessage = [reply serialize];
        
        NSDebugLLog(@"gwcomp", @"Component sizes:");
        NSDebugLLog(@"gwcomp", @"  Fixed header: 16 bytes");
        NSDebugLLog(@"gwcomp", @"  Header fields: %lu bytes", (unsigned long)[headerFields length]);
        NSDebugLLog(@"gwcomp", @"  Body: %lu bytes", (unsigned long)[body length]);
        NSDebugLLog(@"gwcomp", @"  Full message: %lu bytes", (unsigned long)[fullMessage length]);
        
        // Calculate expected vs actual
        NSUInteger expectedTotal = 16 + [headerFields length] + [body length];
        NSUInteger padding = [fullMessage length] - expectedTotal;
        NSDebugLLog(@"gwcomp", @"  Expected total: %lu bytes", expectedTotal);
        NSDebugLLog(@"gwcomp", @"  Actual total: %lu bytes", (unsigned long)[fullMessage length]);
        NSDebugLLog(@"gwcomp", @"  Padding added: %lu bytes", padding);
        
        // Print header fields breakdown
        printf("\\nHeader fields breakdown (%lu bytes):\\n", (unsigned long)[headerFields length]);
        const uint8_t *bytes = [headerFields bytes];
        
        NSUInteger pos = 0;
        while (pos < [headerFields length]) {
            if (pos + 4 > [headerFields length]) break;
            
            uint8_t fieldCode = bytes[pos];
            uint8_t sigLen = bytes[pos + 1];
            uint8_t signature = bytes[pos + 2];
            
            printf("  Field %d (sig=%c): ", fieldCode, signature);
            
            pos += 4; // Skip field code, sig len, signature, null
            
            if (signature == 's') {
                // String field
                if (pos + 4 <= [headerFields length]) {
                    uint32_t strLen = *(uint32_t *)(bytes + pos);
                    pos += 4;
                    if (pos + strLen + 1 <= [headerFields length]) {
                        NSString *str = [[NSString alloc] initWithBytes:bytes + pos
                                                                 length:strLen
                                                               encoding:NSUTF8StringEncoding];
                        printf("'%s' (%u bytes + null)\\n", [str UTF8String], strLen);
                        pos += strLen + 1;
                    }
                }
            } else if (signature == 'u') {
                // uint32 field
                if (pos + 4 <= [headerFields length]) {
                    uint32_t value = *(uint32_t *)(bytes + pos);
                    printf("%u\\n", value);
                    pos += 4;
                }
            } else if (signature == 'g') {
                // Signature field
                if (pos < [headerFields length]) {
                    uint8_t sigStrLen = bytes[pos++];
                    if (pos + sigStrLen + 1 <= [headerFields length]) {
                        NSString *sigStr = [[NSString alloc] initWithBytes:bytes + pos
                                                                   length:sigStrLen
                                                                 encoding:NSUTF8StringEncoding];
                        printf("'%s' (sig len=%u)\\n", [sigStr UTF8String], sigStrLen);
                        pos += sigStrLen + 1;
                    }
                }
            }
            
            // Align to 8-byte boundary for next field
            while (pos % 8 != 0 && pos < [headerFields length]) {
                printf("    padding byte at pos %lu: 0x%02x\\n", pos, bytes[pos]);
                pos++;
            }
        }
        
        // Print full message hex dump
        printf("\\nFull message hex dump (%lu bytes):\\n", (unsigned long)[fullMessage length]);
        const uint8_t *fullBytes = [fullMessage bytes];
        for (NSUInteger i = 0; i < [fullMessage length]; i += 16) {
            printf("%04lx: ", i);
            for (NSUInteger j = 0; j < 16 && i + j < [fullMessage length]; j++) {
                printf("%02x ", fullBytes[i + j]);
            }
            printf("\\n");
        }
        
        return 0;
    }
}
