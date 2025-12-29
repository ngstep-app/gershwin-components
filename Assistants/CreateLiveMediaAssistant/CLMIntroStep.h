/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// CLMIntroStep.h
// Create Live Media Assistant - Introduction Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@interface CLMIntroStep : NSObject <GSAssistantStepProtocol>
{
    NSView *_stepView;
}

@end
