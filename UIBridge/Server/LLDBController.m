/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LLDBController.h"

@implementation LLDBController

+ (NSString *)runCommand:(NSString *)command forPID:(int)pid {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/lldb"];
    
    // lldb -p <pid> --batch -o <command> -o quit
    NSArray *args = @[
        @"-p", [NSString stringWithFormat:@"%d", pid],
        @"--batch",
        @"-o", command,
        @"-o", @"quit"
    ];
    
    [task setArguments:args];
    
    NSPipe *outPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:outPipe]; // Merge stderr
    
    @try {
        [task launch];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"Failed to launch lldb: %@", e];
    }
    
    NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return output;
}

@end
