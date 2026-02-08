/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// CLMImageSelectionStep.h
// Create Live Media Assistant - Image Selection Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@class CLMController;

@interface CLMImageSelectionStep : NSObject <GSAssistantStepProtocol>
{
    NSView *_stepView;
    __weak CLMController *_controller;
    NSPopUpButton *_repositoryPopUp;
    NSTableView *_releaseTableView;
    NSArrayController *_releaseArrayController;
    NSButton *_prereleaseCheckbox;
    NSTextField *_dateLabel;
    NSTextField *_urlLabel;
    NSTextField *_sizeLabel;
    NSProgressIndicator *_loadingIndicator;
    NSTextField *_loadingLabel;
    NSMutableArray *_availableReleases;
    BOOL _isLoading;
}

@property (nonatomic, weak) CLMController *controller;

@end
