/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// BADiskSelectionStep.h
// Backup Assistant - Disk Selection Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@class BAController;

@interface BADiskSelectionStep : GSAssistantStep
{
    __weak BAController *_controller;
    NSTableView *_diskTableView;
    NSArrayController *_diskArrayController;
    NSMutableArray *_availableDisks;
    NSTimer *_refreshTimer;
    NSTextField *_statusLabel;
    NSTextField *_selectedDiskInfo;
    NSMutableDictionary *_diskSpaceCache;  // Cache for disk space calculations
}

@property (nonatomic, weak) BAController *controller;

- (id)initWithController:(BAController *)controller;
- (void)refreshDiskList;
- (void)analyzeDisk:(NSString *)diskDevice;
- (void)performDiskAnalysis:(NSString *)diskDevice;
- (void)updateAnalysisResult:(NSDictionary *)resultInfo;
- (void)calculateDiskSpaceAsync:(NSString *)diskDevice;
- (void)updateDiskSpaceCache:(NSDictionary *)info;

@end
