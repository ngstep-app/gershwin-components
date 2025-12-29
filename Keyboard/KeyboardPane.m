/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "KeyboardPane.h"
#import "KeyboardController.h"

@implementation KeyboardPane

- (id)initWithBundle:(NSBundle *)bundle
{
    self = [super initWithBundle:bundle];
    if (self) {
        controller = [[KeyboardController alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [controller release];
    [super dealloc];
}

- (NSView *)loadMainView
{
    if (_mainView == nil) {
        _mainView = [[controller createMainView] retain];
    }
    return _mainView;
}

- (NSString *)mainNibName
{
    return nil;
}

- (void)mainViewDidLoad
{
    [controller refreshFromSystem];
}

- (void)didSelect
{
    [super didSelect];
    [controller refreshFromSystem];
}

- (BOOL)autoSaveTextFields
{
    return YES;
}

@end
