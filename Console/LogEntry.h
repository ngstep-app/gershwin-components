/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef enum {
    LogPriorityEmergency = 0,
    LogPriorityAlert = 1,
    LogPriorityCritical = 2,
    LogPriorityError = 3,
    LogPriorityWarning = 4,
    LogPriorityNotice = 5,
    LogPriorityInfo = 6,
    LogPriorityDebug = 7
} LogPriority;

@interface LogEntry : NSObject <NSCopying>
{
    NSDate *_timestamp;
    NSString *_process;
    NSString *_message;
    NSString *_detailedReport;
    LogPriority _priority;
    NSInteger _pid;
    NSString *_facility;
    NSString *_sourceName;
}

- (id)initWithTimestamp:(NSDate *)timestamp
                process:(NSString *)process
                message:(NSString *)message
               priority:(LogPriority)priority;

- (id)initWithTimestamp:(NSDate *)timestamp
                process:(NSString *)process
                    pid:(NSInteger)pid
                message:(NSString *)message
               priority:(LogPriority)priority
               facility:(NSString *)facility
         detailedReport:(NSString *)detailedReport;

// Accessors
- (NSDate *)timestamp;
- (NSString *)process;
- (NSString *)message;
- (NSString *)detailedReport;
- (LogPriority)priority;
- (NSInteger)pid;
- (NSString *)facility;
- (NSString *)sourceName;
- (void)setSourceName:(NSString *)sourceName;

- (BOOL)hasDetailedReport;
- (NSString *)priorityString;
- (NSString *)formattedString;

@end
