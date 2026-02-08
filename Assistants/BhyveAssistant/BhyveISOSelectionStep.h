/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// BhyveISOSelectionStep.h
// Bhyve Assistant - ISO Selection Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@class BhyveController;

@interface BhyveISOSelectionStep : NSObject <GSAssistantStepProtocol>
{
    NSView *_stepView;
    NSTextField *_selectedFileLabel;
    NSTextField *_fileSizeLabel;
    NSButton *_browseButton;
    BhyveController *_controller;
}

@property (nonatomic, weak) BhyveController *controller;

@end
