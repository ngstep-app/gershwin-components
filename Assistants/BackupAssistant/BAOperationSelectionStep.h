/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// BAOperationSelectionStep.h
// Backup Assistant - Operation Selection Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@class BAController;

@interface BAOperationSelectionStep : GSAssistantStep
{
    BAController *_controller;
    NSView *_containerView;
    NSMatrix *_operationMatrix;
    NSTextField *_diskInfoLabel;
    NSTextField *_warningLabel;
}

@property (nonatomic, weak) BAController *controller;

- (id)initWithController:(BAController *)controller;
- (void)updateOperationOptions;

@end
