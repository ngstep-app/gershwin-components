/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LogSource.h"
#import <sys/stat.h>
#import <unistd.h>
#import <stdarg.h>

// Helper function to call delegate methods on main thread
static void callDelegateOnMainThread(id delegate, SEL selector, id arg1, id arg2)
{
    NSMethodSignature *sig = [delegate methodSignatureForSelector:selector];
    if (!sig) return;
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
    [invocation setSelector:selector];
    [invocation setTarget:delegate];
    [invocation setArgument:&arg1 atIndex:2];
    [invocation setArgument:&arg2 atIndex:3];
    [invocation retainArguments];
    [invocation performSelectorOnMainThread:@selector(invoke)
                                 withObject:nil
                              waitUntilDone:NO];
}

static void callDelegateEntriesOnMainThread(id delegate, LogSource *source, NSArray *entries)
{
    if ([delegate respondsToSelector:@selector(logSource:didReceiveLogEntries:)]) {
        SEL selector = @selector(logSource:didReceiveLogEntries:);
        NSMethodSignature *sig = [delegate methodSignatureForSelector:selector];
        if (!sig) return;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setSelector:selector];
        [invocation setTarget:delegate];
        [invocation setArgument:&source atIndex:2];
        [invocation setArgument:&entries atIndex:3];
        [invocation retainArguments];
        [invocation performSelectorOnMainThread:@selector(invoke)
                                     withObject:nil
                                  waitUntilDone:NO];
    } else {
        for (LogEntry *entry in entries) {
            callDelegateOnMainThread(delegate, @selector(logSource:didReceiveLogEntry:), source, entry);
        }
    }
}

static void ConsoleDebugLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *msg = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    NSString *path = @"/tmp/Console-debug.log";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:nil attributes:nil];
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
}

static NSArray *TailLines(NSString *path, NSUInteger maxLines)
{
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) {
        return @[];
    }

    unsigned long long fileSize = [fh seekToEndOfFile];
    if (fileSize == 0) {
        [fh closeFile];
        return @[];
    }

    NSMutableArray *chunks = [NSMutableArray array];
    unsigned long long offset = fileSize;
    NSUInteger lines = 0;
    const NSUInteger chunkSize = 8192;

    while (offset > 0 && lines <= maxLines) {
        NSUInteger readSize = (offset >= chunkSize) ? chunkSize : (NSUInteger)offset;
        offset -= readSize;
        [fh seekToFileOffset:offset];
        NSData *data = [fh readDataOfLength:readSize];
        [chunks addObject:data];

        const char *bytes = (const char *)[data bytes];
        for (NSUInteger i = 0; i < [data length]; i++) {
            if (bytes[i] == '\n') {
                lines++;
            }
        }
    }

    NSMutableData *all = [NSMutableData data];
    for (NSInteger i = (NSInteger)[chunks count] - 1; i >= 0; i--) {
        [all appendData:[chunks objectAtIndex:i]];
    }

    NSString *content = [[[NSString alloc] initWithData:all encoding:NSUTF8StringEncoding] autorelease];
    [fh closeFile];

    NSArray *allLines = [content componentsSeparatedByString:@"\n"];
    if ([allLines count] <= maxLines) {
        return allLines;
    }

    NSRange range = NSMakeRange([allLines count] - maxLines, maxLines);
    return [allLines subarrayWithRange:range];
}

@implementation LogSource

- (id)initWithName:(NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _active = NO;
        _delegate = nil;
        _readerThread = nil;
    }
    return self;
}

- (void)dealloc
{
    if ([self class] == [LogSource class]) {
        [self stop];
    }
    [_name release];
    [super dealloc];
}

- (void)setDelegate:(id<LogSourceDelegate>)delegate
{
    _delegate = delegate;
}

- (id<LogSourceDelegate>)delegate
{
    return _delegate;
}

- (NSString *)name
{
    return _name;
}

- (BOOL)isActive
{
    return _active;
}

- (BOOL)isAvailable
{
    return YES;  // Subclasses override
}

- (void)start
{
    if (_active) return;
    
    _active = YES;
    _readerThread = [[NSThread alloc] initWithTarget:self
                                             selector:@selector(readLogs)
                                               object:nil];
    [_readerThread start];
}

- (void)stop
{
    if (!_active) return;
    
    _active = NO;
    if (_readerThread) {
        [_readerThread cancel];
        [_readerThread release];
        _readerThread = nil;
    }
}

- (void)readLogs
{
    // Subclasses must override
    NSLog(@"WARNING: LogSource readLogs not implemented in %@", [self class]);
}

@end

// MARK: - SystemdLogSource

@implementation SystemdLogSource

- (void)dealloc
{
    [self stop];
    [super dealloc];
}

- (BOOL)isAvailable
{
    // Check if systemd is present
    struct stat st;
    if (stat("/run/systemd/system", &st) != 0) {
        return NO;
    }
    return ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/journalctl"]);
}

- (void)start
{
    if (_active) return;
    
    _active = YES;
    
    // Launch journalctl in a separate thread
    [NSThread detachNewThreadSelector:@selector(readLogs)
                             toTarget:self
                           withObject:nil];
}

- (void)stop
{
    _active = NO;
    
    if (_journalctlTask && [_journalctlTask isRunning]) {
        [_journalctlTask terminate];
        [_journalctlTask waitUntilExit];
    }
    
    [_journalOutput closeFile];
    [_journalOutput release];
    _journalOutput = nil;
    
    [_journalctlTask release];
    _journalctlTask = nil;
}

- (void)readLogs
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    _journalctlTask = [[NSTask alloc] init];
    [_journalctlTask setLaunchPath:@"/usr/bin/journalctl"];
    [_journalctlTask setArguments:@[@"--follow", @"--all", @"--output=json"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [_journalctlTask setStandardOutput:pipe];
    _journalOutput = [[pipe fileHandleForReading] retain];
    
    [_journalctlTask launch];
    
    while (_active && [_journalctlTask isRunning]) {
        NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
        
        NSData *data = [_journalOutput availableData];
        if ([data length] > 0) {
            // Parse JSON log entry
            NSError *error = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:&error];
            
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)json;
                
                NSString *message = [dict objectForKey:@"MESSAGE"];
                NSString *process = [dict objectForKey:@"_COMM"];
                if (!process) process = [dict objectForKey:@"SYSLOG_IDENTIFIER"];
                
                NSNumber *pidNum = [dict objectForKey:@"_PID"];
                NSInteger pid = pidNum ? [pidNum integerValue] : 0;
                
                NSNumber *priorityNum = [dict objectForKey:@"PRIORITY"];
                LogPriority priority = priorityNum ? [priorityNum intValue] : LogPriorityInfo;
                
                NSString *timestampStr = [dict objectForKey:@"__REALTIME_TIMESTAMP"];
                NSDate *timestamp = [NSDate date];
                if (timestampStr) {
                    NSTimeInterval usec = [timestampStr doubleValue];
                    timestamp = [NSDate dateWithTimeIntervalSince1970:usec / 1000000.0];
                }
                
                if (message && process) {
                    LogEntry *entry = [[LogEntry alloc] initWithTimestamp:timestamp
                                                                   process:process
                                                                       pid:pid
                                                                   message:message
                                                                  priority:priority
                                                                  facility:nil
                                                            detailedReport:nil];
                    [entry setSourceName:@"Journal"];
                    
                    callDelegateOnMainThread(_delegate, @selector(logSource:didReceiveLogEntry:), self, entry);
                    [entry release];
                }
            }
        } else {
            [NSThread sleepForTimeInterval:0.1];
        }
        
        [innerPool drain];
    }
    
    [pool drain];
}

@end

// MARK: - SyslogLogSource

@implementation SyslogLogSource

- (id)initWithLogFilePath:(NSString *)path
{
    self = [super initWithName:[path lastPathComponent]];
    if (self) {
        _logFilePath = [path copy];
        _fileHandle = nil;
        _lastPosition = 0;
        _watching = NO;
        _rearmScheduled = NO;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [_logFilePath release];
    [super dealloc];
}

- (BOOL)isAvailable
{
    NSFileManager *fm = [NSFileManager defaultManager];
    return ([fm fileExistsAtPath:_logFilePath] && [fm isReadableFileAtPath:_logFilePath]);
}

- (void)stop
{
    [super stop];
    _watching = NO;
    _rearmScheduled = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleDataAvailableNotification
                                                  object:_fileHandle];
    if (_fileHandle) {
        [_fileHandle closeFile];
        [_fileHandle release];
        _fileHandle = nil;
    }
}

- (void)readLogs
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    // Open the log file
    _fileHandle = [[NSFileHandle fileHandleForReadingAtPath:_logFilePath] retain];
    if (!_fileHandle) {
        NSError *error = [NSError errorWithDomain:@"LogSourceError"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to open log file"}];
        callDelegateOnMainThread(_delegate, @selector(logSource:didEncounterError:), self, error);
        [pool drain];
        return;
    }
    
    // Read initial tail
    NSArray *tailLines = TailLines(_logFilePath, 500);
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[tailLines count]];
    for (NSString *line in tailLines) {
        if ([line length] == 0) continue;
        LogEntry *entry = [self parseLogLine:line];
        if (entry) {
            [entries addObject:entry];
        }
    }
    if ([entries count] > 0) {
        for (LogEntry *entry in entries) {
            [entry setSourceName:_logFilePath];
        }
        callDelegateEntriesOnMainThread(_delegate, self, entries);
        ConsoleDebugLog(@"Syslog initial load (%@): %lu entries", _logFilePath, (unsigned long)[entries count]);
    }
    
    // Seek to end and start watching
    _lastPosition = [_fileHandle seekToEndOfFile];
    _watching = YES;
    ConsoleDebugLog(@"Syslog watch started: %@", _logFilePath);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleFileData:)
                                                 name:NSFileHandleDataAvailableNotification
                                               object:_fileHandle];
    [_fileHandle waitForDataInBackgroundAndNotify];
    
    while (_active) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }

    [pool drain];
}

- (void)handleFileData:(NSNotification *)notification
{
    if (!_active || !_watching) {
        return;
    }

    NSData *data = [_fileHandle readDataToEndOfFile];
    if ([data length] > 0) {
        NSString *content = [[[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding] autorelease];
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[lines count]];
        for (NSString *line in lines) {
            if ([line length] == 0) continue;
            LogEntry *entry = [self parseLogLine:line];
            if (entry) {
                [entries addObject:entry];
            }
        }
        if ([entries count] > 0) {
            for (LogEntry *entry in entries) {
                [entry setSourceName:_logFilePath];
            }
            callDelegateEntriesOnMainThread(_delegate, self, entries);
            ConsoleDebugLog(@"Syslog update (%@): %lu entries", _logFilePath, (unsigned long)[entries count]);
        }
    }

    if (_active && _watching) {
        if ([data length] == 0) {
            if (!_rearmScheduled) {
                _rearmScheduled = YES;
                [self performSelector:@selector(_rearmSyslogWatcher)
                           withObject:nil
                           afterDelay:0.5];
            }
        } else {
            [_fileHandle waitForDataInBackgroundAndNotify];
        }
    }
}

- (void)_rearmSyslogWatcher
{
    if (_active && _watching) {
        _rearmScheduled = NO;
        [_fileHandle waitForDataInBackgroundAndNotify];
    }
}

- (LogEntry *)parseLogLine:(NSString *)line
{
    // Parse standard syslog format: "Mon DD HH:MM:SS hostname process[pid]: message"
    // Simplified parser - can be enhanced
    
    NSScanner *scanner = [NSScanner scannerWithString:line];
    [scanner setCharactersToBeSkipped:nil];
    
    // Skip timestamp (first 16 characters typically)
    if ([line length] < 16) return nil;
    
    NSString *month, *day, *time, *hostname, *message;
    
    [scanner scanUpToString:@" " intoString:&month];
    [scanner scanString:@" " intoString:nil];
    [scanner scanUpToString:@" " intoString:&day];
    [scanner scanString:@" " intoString:nil];
    [scanner scanUpToString:@" " intoString:&time];
    [scanner scanString:@" " intoString:nil];
    [scanner scanUpToString:@" " intoString:&hostname];
    [scanner scanString:@" " intoString:nil];
    
    // Process and PID
    NSString *process = nil;
    NSInteger pid = 0;
    [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"[:"]
                            intoString:&process];
    
    if ([scanner scanString:@"[" intoString:nil]) {
        [scanner scanInteger:&pid];
        [scanner scanString:@"]" intoString:nil];
    }
    
    [scanner scanString:@":" intoString:nil];
    [scanner scanString:@" " intoString:nil];
    
    // Rest is message
    message = [[line substringFromIndex:[scanner scanLocation]] stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSString *msgForPriority = message ? message : line;
    LogPriority inferredPriority = LogPriorityInfo;
    NSString *lower = [msgForPriority lowercaseString];
    if ([lower rangeOfString:@"panic"].location != NSNotFound ||
        [lower rangeOfString:@"fatal"].location != NSNotFound ||
        [lower rangeOfString:@"crit"].location != NSNotFound) {
        inferredPriority = LogPriorityCritical;
    } else if ([lower rangeOfString:@"error"].location != NSNotFound) {
        inferredPriority = LogPriorityError;
    } else if ([lower rangeOfString:@"warn"].location != NSNotFound) {
        inferredPriority = LogPriorityWarning;
    } else if ([lower rangeOfString:@"notice"].location != NSNotFound) {
        inferredPriority = LogPriorityNotice;
    } else if ([lower rangeOfString:@"debug"].location != NSNotFound) {
        inferredPriority = LogPriorityDebug;
    }

    if (!process || !message) {
        LogEntry *fallback = [[LogEntry alloc] initWithTimestamp:[NSDate date]
                                                         process:@"syslog"
                                                             pid:0
                                                         message:line
                                                        priority:inferredPriority
                                                        facility:nil
                                                  detailedReport:nil];
        return [fallback autorelease];
    }
    
    // Build date from components (use current year)
    NSDateComponents *components = [[NSDateComponents alloc] init];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    [components setYear:[[calendar components:NSCalendarUnitYear fromDate:[NSDate date]] year]];
    
    // Month name to number
    NSArray *monthNames = @[@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun",
                           @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec"];
    NSInteger monthNum = [monthNames indexOfObject:month];
    if (monthNum != NSNotFound) {
        [components setMonth:monthNum + 1];
    }
    
    [components setDay:[day integerValue]];
    
    // Parse time
    NSArray *timeParts = [time componentsSeparatedByString:@":"];
    if ([timeParts count] == 3) {
        [components setHour:[[timeParts objectAtIndex:0] integerValue]];
        [components setMinute:[[timeParts objectAtIndex:1] integerValue]];
        [components setSecond:[[timeParts objectAtIndex:2] integerValue]];
    }
    
    NSDate *timestamp = [calendar dateFromComponents:components];
    [components release];
    
    LogEntry *entry = [[LogEntry alloc] initWithTimestamp:timestamp
                                                   process:process
                                                       pid:pid
                                                   message:message
                                                  priority:inferredPriority
                                                  facility:nil
                                            detailedReport:nil];
    return [entry autorelease];
}

@end

// MARK: - KernelLogSource

@implementation KernelLogSource

- (void)dealloc
{
    [self stop];
    [_lastContent release];
    [super dealloc];
}

- (void)stop
{
    [super stop];
    
    if (_pollTimer) {
        [_pollTimer invalidate];
        _pollTimer = nil;
    }
}

- (void)readLogs
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    // Initial read
    [self pollKernelLog:nil];
    
    // Schedule timer on this thread's run loop
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                  target:self
                                                selector:@selector(pollKernelLog:)
                                                userInfo:nil
                                                 repeats:YES];
    
    while (_active) {
        [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }
    
    [pool drain];
}

- (void)pollKernelLog:(NSTimer *)timer
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    // Run dmesg command
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/dmesg"];
    [task setArguments:@[]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    [task launch];
    [task waitUntilExit];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *content = [[[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding] autorelease];
    
    [task release];
    
    // Only report new lines; on first run, emit tail
    NSString *newContent = nil;
    if (_lastContent && [content hasPrefix:_lastContent]) {
        newContent = [content substringFromIndex:[_lastContent length]];
    } else if (!_lastContent) {
        NSArray *tail = [content componentsSeparatedByString:@"\n"];
        if ([tail count] > 200) {
            NSRange range = NSMakeRange([tail count] - 200, 200);
            tail = [tail subarrayWithRange:range];
        }
        newContent = [tail componentsJoinedByString:@"\n"];
    } else {
        newContent = content;
    }

    NSArray *lines = [newContent componentsSeparatedByString:@"\n"];
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[lines count]];
    for (NSString *line in lines) {
        if ([line length] == 0) continue;
        
        LogEntry *entry = [[LogEntry alloc] initWithTimestamp:[NSDate date]
                                                       process:@"kernel"
                                                           pid:0
                                                       message:line
                                                      priority:LogPriorityInfo
                                                      facility:@"kernel"
                                                detailedReport:nil];
        [entries addObject:entry];
        [entry release];
    }
    if ([entries count] > 0) {
        for (LogEntry *entry in entries) {
            [entry setSourceName:@"Kernel"];
        }
        callDelegateEntriesOnMainThread(_delegate, self, entries);
        ConsoleDebugLog(@"Kernel update: %lu entries", (unsigned long)[entries count]);
    }
    
    [_lastContent release];
    _lastContent = [content copy];
    
    [pool drain];
}

@end

// MARK: - ApplicationLogSource

@implementation ApplicationLogSource

- (id)initWithLogDirectory:(NSString *)directory
{
    self = [super initWithName:@"Applications"];
    if (self) {
        _logDirectory = [directory copy];
        _fileHandles = [[NSMutableDictionary alloc] init];
        _filePositions = [[NSMutableDictionary alloc] init];
        _handleToFile = [[NSMutableDictionary alloc] init];
        _scanTimer = nil;
        _rearmHandles = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [_logDirectory release];
    [_fileHandles release];
    [_filePositions release];
    [_handleToFile release];
    [_rearmHandles release];
    [super dealloc];
}

- (BOOL)isAvailable
{
    NSFileManager *fm = [NSFileManager defaultManager];
    return ([fm fileExistsAtPath:_logDirectory] && [fm isReadableFileAtPath:_logDirectory]);
}

- (void)stop
{
    [super stop];
    if (_scanTimer) {
        [_scanTimer invalidate];
        _scanTimer = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleDataAvailableNotification
                                                  object:nil];
    
    // Close all file handles
    for (NSFileHandle *handle in [_fileHandles allValues]) {
        [handle closeFile];
    }
    [_fileHandles removeAllObjects];
    [_filePositions removeAllObjects];
    [_handleToFile removeAllObjects];
    [_rearmHandles removeAllObjects];
}

- (void)readLogs
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [self scanForNewLogFiles];
    
    ConsoleDebugLog(@"App log watch started: %@", _logDirectory);
    _scanTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                  target:self
                                                selector:@selector(scanForNewLogFiles)
                                                userInfo:nil
                                                 repeats:YES];
    
    while (_active) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }

    [pool drain];
}

- (void)scanForNewLogFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:_logDirectory error:nil];

    for (NSString *filename in files) {
        if (![[filename pathExtension] isEqualToString:@"log"]) continue;

        NSString *fullPath = [_logDirectory stringByAppendingPathComponent:filename];
        if (![fm isReadableFileAtPath:fullPath]) continue;

        NSFileHandle *handle = [_fileHandles objectForKey:filename];
        if (!handle) {
            handle = [NSFileHandle fileHandleForReadingAtPath:fullPath];
            if (handle) {
                [_fileHandles setObject:handle forKey:filename];
                [_handleToFile setObject:filename forKey:[NSValue valueWithNonretainedObject:handle]];

                // Emit initial tail
                NSArray *tailLines = TailLines(fullPath, 200);
                NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[tailLines count]];
                for (NSString *line in tailLines) {
                    if ([line length] == 0) continue;
                    LogEntry *entry = [[LogEntry alloc] initWithTimestamp:[NSDate date]
                                                                   process:[filename stringByDeletingPathExtension]
                                                                   message:line
                                                                  priority:LogPriorityInfo];
                    [entries addObject:entry];
                    [entry release];
                }
                if ([entries count] > 0) {
                    NSString *sourceName = [NSString stringWithFormat:@"%@/%@", _logDirectory, filename];
                    for (LogEntry *entry in entries) {
                        [entry setSourceName:sourceName];
                    }
                    callDelegateEntriesOnMainThread(_delegate, self, entries);
                    ConsoleDebugLog(@"App log initial load (%@/%@): %lu entries", _logDirectory, filename, (unsigned long)[entries count]);
                }

                unsigned long long endPos = [handle seekToEndOfFile];
                [_filePositions setObject:[NSNumber numberWithUnsignedLongLong:endPos]
                                   forKey:filename];

                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(handleFileData:)
                                                             name:NSFileHandleDataAvailableNotification
                                                           object:handle];
                [handle waitForDataInBackgroundAndNotify];
            }
        }
    }
}

- (void)handleFileData:(NSNotification *)notification
{
    NSFileHandle *handle = [notification object];
    if (!handle || !_active) {
        return;
    }

    NSString *filename = [_handleToFile objectForKey:[NSValue valueWithNonretainedObject:handle]];
    if (!filename) {
        return;
    }

    NSData *data = [handle readDataToEndOfFile];
    if ([data length] > 0) {
        NSString *content = [[[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding] autorelease];
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[lines count]];
        for (NSString *line in lines) {
            if ([line length] == 0) continue;
            LogEntry *entry = [[LogEntry alloc] initWithTimestamp:[NSDate date]
                                                           process:[filename stringByDeletingPathExtension]
                                                           message:line
                                                          priority:LogPriorityInfo];
            [entries addObject:entry];
            [entry release];
        }
        if ([entries count] > 0) {
            NSString *sourceName = [NSString stringWithFormat:@"%@/%@", _logDirectory, filename];
            for (LogEntry *entry in entries) {
                [entry setSourceName:sourceName];
            }
            callDelegateEntriesOnMainThread(_delegate, self, entries);
            ConsoleDebugLog(@"App log update (%@/%@): %lu entries", _logDirectory, filename, (unsigned long)[entries count]);
        }
    }

    if (_active) {
        if ([data length] == 0) {
            NSValue *key = [NSValue valueWithNonretainedObject:handle];
            if (![_rearmHandles containsObject:key]) {
                [_rearmHandles addObject:key];
                [self performSelector:@selector(_rearmAppWatcher:)
                           withObject:handle
                           afterDelay:0.5];
            }
        } else {
            [handle waitForDataInBackgroundAndNotify];
        }
    }
}

- (void)_rearmAppWatcher:(NSFileHandle *)handle
{
    if (_active && handle) {
        NSValue *key = [NSValue valueWithNonretainedObject:handle];
        [_rearmHandles removeObject:key];
        [handle waitForDataInBackgroundAndNotify];
    }
}

@end
