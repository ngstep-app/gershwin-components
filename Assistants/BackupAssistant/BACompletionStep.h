/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// BACompletionStep.h
// Backup Assistant - Completion Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@class BAController;

@interface BACompletionStep : GSCompletionStep
{
    BAController *_controller;
}

@property (nonatomic, weak) BAController *controller;

- (id)initWithController:(BAController *)controller;

@end
