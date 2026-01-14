/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "LogSource.h"
#import "LogEntry.h"
#import "LogQuery.h"

@interface ConsoleController : NSObject <LogSourceDelegate, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSWindowDelegate>
{
    NSMutableArray *_logSources;
    NSMutableArray *_allLogEntries;
    NSMutableArray *_filteredLogEntries;
    NSMutableArray *_queries;
    LogQuery *_currentQuery;
    NSString *_currentSourceName;
    NSString *_currentSourcePrefix;
    
    NSInteger _maxLogEntries;
    NSTimeInterval _refreshInterval;
    
    NSLock *_logEntriesLock;
    
    // UI References
    IBOutlet NSWindow *_mainWindow;
    IBOutlet NSTableView *_logTableView;
    IBOutlet NSOutlineView *_logListView;
    IBOutlet NSSplitView *_splitView;
    IBOutlet NSTextField *_searchField;
    IBOutlet NSTextView *_detailTextView;
    IBOutlet NSProgressIndicator *_progressIndicator;
    
    BOOL _showingLogList;
}

+ (ConsoleController *)sharedController;

// Log source management
- (void)initializeLogSources;
- (void)startMonitoring;
- (void)stopMonitoring;
- (NSArray *)logSources;

// Log entry management
- (void)addLogEntry:(LogEntry *)entry;
- (void)addLogEntries:(NSArray *)entries;
- (NSArray *)allLogEntries;
- (NSArray *)filteredLogEntries;
- (void)clearLogEntries;

// Query management
- (void)addQuery:(LogQuery *)query;
- (void)removeQuery:(LogQuery *)query;
- (NSArray *)queries;
- (void)setCurrentQuery:(LogQuery *)query;
- (LogQuery *)currentQuery;

// UI Actions
- (IBAction)toggleLogList:(id)sender;
- (IBAction)clearLogs:(id)sender;
- (IBAction)newQuery:(id)sender;
- (IBAction)search:(id)sender;
- (IBAction)copyLogEntry:(id)sender;
- (IBAction)saveLogToFile:(id)sender;

// Configuration
- (void)loadConfiguration;
- (void)saveConfiguration;

// Privileged relaunch
- (void)relaunchWithSudoIfNeeded;

@end
