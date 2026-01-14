/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LogEntry.h"

@implementation LogEntry

- (id)initWithTimestamp:(NSDate *)timestamp
                process:(NSString *)process
                message:(NSString *)message
               priority:(LogPriority)priority
{
    return [self initWithTimestamp:timestamp
                           process:process
                               pid:0
                           message:message
                          priority:priority
                          facility:nil
                    detailedReport:nil];
}

- (id)initWithTimestamp:(NSDate *)timestamp
                process:(NSString *)process
                    pid:(NSInteger)pid
                message:(NSString *)message
               priority:(LogPriority)priority
               facility:(NSString *)facility
         detailedReport:(NSString *)detailedReport
{
    self = [super init];
    if (self) {
        _timestamp = [timestamp retain];
        _process = [process copy];
        _pid = pid;
        _message = [message copy];
        _priority = priority;
        _facility = [facility copy];
        _detailedReport = [detailedReport copy];
        _sourceName = nil;
    }
    return self;
}

- (void)dealloc
{
    [_timestamp release];
    [_process release];
    [_message release];
    [_facility release];
    [_detailedReport release];
    [_sourceName release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];  // Immutable
}

// Accessors
- (NSDate *)timestamp { return _timestamp; }
- (NSString *)process { return _process; }
- (NSString *)message { return _message; }
- (NSString *)detailedReport { return _detailedReport; }
- (LogPriority)priority { return _priority; }
- (NSInteger)pid { return _pid; }
- (NSString *)facility { return _facility; }

- (NSString *)sourceName { return _sourceName; }

- (void)setSourceName:(NSString *)sourceName
{
    if (_sourceName != sourceName) {
        [_sourceName release];
        _sourceName = [sourceName copy];
    }
}

- (BOOL)hasDetailedReport
{
    return _detailedReport != nil && [_detailedReport length] > 0;
}

- (NSString *)priorityString
{
    switch (_priority) {
        case LogPriorityEmergency: return @"EMERG";
        case LogPriorityAlert: return @"ALERT";
        case LogPriorityCritical: return @"CRIT";
        case LogPriorityError: return @"ERROR";
        case LogPriorityWarning: return @"WARN";
        case LogPriorityNotice: return @"NOTICE";
        case LogPriorityInfo: return @"INFO";
        case LogPriorityDebug: return @"DEBUG";
        default: return @"UNKNOWN";
    }
}

- (NSString *)formattedString
{
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timeStr = [formatter stringFromDate:_timestamp];
    
    NSString *pidStr = _pid > 0 ? [NSString stringWithFormat:@"[%ld]", (long)_pid] : @"";
    
    return [NSString stringWithFormat:@"%@ %@%@ %@: %@",
            timeStr,
            _process ? _process : @"unknown",
            pidStr,
            [self priorityString],
            _message];
}

- (NSString *)description
{
    return [self formattedString];
}

@end
