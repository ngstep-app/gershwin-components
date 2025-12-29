/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// DRIIntroStep.h
// Debian Runtime Installer - Introduction Step
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

@interface DRIIntroStep : NSObject <GSAssistantStepProtocol>
{
    NSView *_contentView;
}
@end
