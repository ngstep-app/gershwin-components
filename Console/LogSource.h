/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "LogEntry.h"

@protocol LogSourceDelegate;

@interface LogSource : NSObject
{
    id<LogSourceDelegate> _delegate;
    NSString *_name;
    BOOL _active;
    NSThread *_readerThread;
}

- (id)initWithName:(NSString *)name;

- (void)setDelegate:(id<LogSourceDelegate>)delegate;
- (id<LogSourceDelegate>)delegate;

- (NSString *)name;
- (BOOL)isActive;
- (BOOL)isAvailable;  // Check if this log source is available on current system

- (void)start;
- (void)stop;

// Subclasses must override
- (void)readLogs;

@end

@protocol LogSourceDelegate <NSObject>
- (void)logSource:(LogSource *)source didReceiveLogEntry:(LogEntry *)entry;
- (void)logSource:(LogSource *)source didReceiveLogEntries:(NSArray *)entries;
- (void)logSource:(LogSource *)source didEncounterError:(NSError *)error;
@end

// Concrete implementations

@interface SystemdLogSource : LogSource
{
    NSTask *_journalctlTask;
    NSFileHandle *_journalOutput;
}
@end

@interface SyslogLogSource : LogSource
{
    NSString *_logFilePath;
    NSFileHandle *_fileHandle;
    unsigned long long _lastPosition;
    BOOL _watching;
    BOOL _rearmScheduled;
}
- (id)initWithLogFilePath:(NSString *)path;
- (void)handleFileData:(NSNotification *)notification;
@end

@interface KernelLogSource : LogSource
{
    NSTimer *_pollTimer;
    NSString *_lastContent;
}
@end

@interface ApplicationLogSource : LogSource
{
    NSString *_logDirectory;
    NSMutableDictionary *_fileHandles;  // filename -> NSFileHandle
    NSMutableDictionary *_filePositions;  // filename -> NSNumber (position)
    NSMutableDictionary *_handleToFile;  // NSFileHandle -> filename
    NSTimer *_scanTimer;
    unsigned long long _lastDirectoryMTime;
}
- (id)initWithLogDirectory:(NSString *)directory;
- (void)handleFileData:(NSNotification *)notification;
- (void)scanForNewLogFiles;
@end
