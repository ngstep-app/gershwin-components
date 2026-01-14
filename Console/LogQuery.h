/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "LogEntry.h"

@interface LogQuery : NSObject <NSCopying>
{
    NSString *_name;
    NSString *_processPattern;
    NSRegularExpression *_processRegex;
    NSDate *_startDate;
    NSDate *_endDate;
    NSArray *_priorityLevels;  // Array of NSNumber (LogPriority)
    NSString *_messagePattern;
    NSRegularExpression *_messageRegex;
    BOOL _alertOnMatch;
}

- (id)initWithName:(NSString *)name;

// Configuration
- (void)setName:(NSString *)name;
- (void)setProcessPattern:(NSString *)pattern;
- (void)setStartDate:(NSDate *)date;
- (void)setEndDate:(NSDate *)date;
- (void)setPriorityLevels:(NSArray *)levels;
- (void)setMessagePattern:(NSString *)pattern;
- (void)setAlertOnMatch:(BOOL)alert;

// Accessors
- (NSString *)name;
- (NSString *)processPattern;
- (NSDate *)startDate;
- (NSDate *)endDate;
- (NSArray *)priorityLevels;
- (NSString *)messagePattern;
- (BOOL)alertOnMatch;

// Query execution
- (BOOL)matchesLogEntry:(LogEntry *)entry;
- (NSArray *)filterLogEntries:(NSArray *)entries;

@end
