/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// BhyveRunningStep.h
// Bhyve Assistant - VM Running Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@class BhyveController;

@interface BhyveRunningStep : NSObject <GSAssistantStepProtocol>
{
    NSView *_stepView;
    NSTextField *_statusLabel;
    NSTextField *_vmInfoLabel;
    NSButton *_logButton;
    BhyveController *_controller;
}

@property (nonatomic, assign) BhyveController *controller;

- (void)updateStatus:(NSString *)status;

@end
