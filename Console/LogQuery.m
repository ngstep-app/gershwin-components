/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LogQuery.h"

@implementation LogQuery

- (id)initWithName:(NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _processPattern = nil;
        _processRegex = nil;
        _startDate = nil;
        _endDate = nil;
        _priorityLevels = nil;
        _messagePattern = nil;
        _messageRegex = nil;
        _alertOnMatch = NO;
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_processPattern release];
    [_processRegex release];
    [_startDate release];
    [_endDate release];
    [_priorityLevels release];
    [_messagePattern release];
    [_messageRegex release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    LogQuery *copy = [[LogQuery allocWithZone:zone] initWithName:_name];
    [copy setProcessPattern:_processPattern];
    [copy setStartDate:_startDate];
    [copy setEndDate:_endDate];
    [copy setPriorityLevels:_priorityLevels];
    [copy setMessagePattern:_messagePattern];
    [copy setAlertOnMatch:_alertOnMatch];
    return copy;
}

// Configuration
- (void)setName:(NSString *)name
{
    if (_name != name) {
        [_name release];
        _name = [name copy];
    }
}

- (void)setProcessPattern:(NSString *)pattern
{
    if (_processPattern != pattern) {
        [_processPattern release];
        _processPattern = [pattern copy];
        
        [_processRegex release];
        _processRegex = nil;
        
        if (pattern && [pattern length] > 0) {
            NSError *error = nil;
            _processRegex = [[NSRegularExpression alloc]
                            initWithPattern:pattern
                            options:NSRegularExpressionCaseInsensitive
                            error:&error];
            if (error) {
                NSDebugLLog(@"gwcomp", @"Failed to compile process regex: %@", error);
            }
        }
    }
}

- (void)setStartDate:(NSDate *)date
{
    if (_startDate != date) {
        [_startDate release];
        _startDate = [date retain];
    }
}

- (void)setEndDate:(NSDate *)date
{
    if (_endDate != date) {
        [_endDate release];
        _endDate = [date retain];
    }
}

- (void)setPriorityLevels:(NSArray *)levels
{
    if (_priorityLevels != levels) {
        [_priorityLevels release];
        _priorityLevels = [levels copy];
    }
}

- (void)setMessagePattern:(NSString *)pattern
{
    if (_messagePattern != pattern) {
        [_messagePattern release];
        _messagePattern = [pattern copy];
        
        [_messageRegex release];
        _messageRegex = nil;
        
        if (pattern && [pattern length] > 0) {
            NSError *error = nil;
            _messageRegex = [[NSRegularExpression alloc]
                           initWithPattern:pattern
                           options:NSRegularExpressionCaseInsensitive
                           error:&error];
            if (error) {
                NSDebugLLog(@"gwcomp", @"Failed to compile regex pattern: %@", error);
            }
        }
    }
}

- (void)setAlertOnMatch:(BOOL)alert
{
    _alertOnMatch = alert;
}

// Accessors
- (NSString *)name { return _name; }
- (NSString *)processPattern { return _processPattern; }
- (NSDate *)startDate { return _startDate; }
- (NSDate *)endDate { return _endDate; }
- (NSArray *)priorityLevels { return _priorityLevels; }
- (NSString *)messagePattern { return _messagePattern; }
- (BOOL)alertOnMatch { return _alertOnMatch; }

// Query execution
- (BOOL)matchesLogEntry:(LogEntry *)entry
{
    // Check time range
    if (_startDate && [[entry timestamp] compare:_startDate] == NSOrderedAscending) {
        return NO;
    }
    if (_endDate && [[entry timestamp] compare:_endDate] == NSOrderedDescending) {
        return NO;
    }
    
    // Check priority levels
    if (_priorityLevels && [_priorityLevels count] > 0) {
        BOOL priorityMatch = NO;
        for (NSNumber *level in _priorityLevels) {
            if ([level intValue] == [entry priority]) {
                priorityMatch = YES;
                break;
            }
        }
        if (!priorityMatch) {
            return NO;
        }
    }
    
    // Check process pattern (regex)
    if (_processRegex) {
        NSString *process = [entry process];
        if (!process) {
            return NO;
        }
        NSRange range = NSMakeRange(0, [process length]);
        NSTextCheckingResult *match = [_processRegex firstMatchInString:process
                                                                 options:0
                                                                   range:range];
        if (!match) {
            return NO;
        }
    }
    
    // Check message pattern
    if (_messageRegex) {
        NSString *message = [entry message];
        if (!message) {
            return NO;
        }
        NSRange range = NSMakeRange(0, [message length]);
        NSTextCheckingResult *match = [_messageRegex firstMatchInString:message
                                                                 options:0
                                                                   range:range];
        if (!match) {
            return NO;
        }
    }
    
    return YES;
}

- (NSArray *)filterLogEntries:(NSArray *)entries
{
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:[entries count]];
    
    for (LogEntry *entry in entries) {
        if ([self matchesLogEntry:entry]) {
            [filtered addObject:entry];
        }
    }
    
    return filtered;
}

@end
