/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// CLMCompletionStep.h
// Create Live Media Assistant - Completion Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@interface CLMCompletionStep : NSObject <GSAssistantStepProtocol>
{
    NSView *_stepView;
}

@end
