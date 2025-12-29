/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>

@interface KeyboardController : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
    NSView *mainView;
    NSTableView *layoutTable;
    NSTableView *variantTable;
    NSScrollView *layoutScroll;
    NSScrollView *variantScroll;
    NSTextField *statusLabel;
    NSTextField *tryTextField;
    NSButton *swapCheckbox;

    NSDictionary *layouts;
    NSDictionary *variantsByLayout;
    NSString *setxkbmapPath;

    NSArray *sortedLayouts;
    NSArray *currentVariants;

    NSString *lastAppliedLayout;
    NSString *lastAppliedVariant;

    BOOL metadataLoaded;
    BOOL isRefreshing;
}

- (NSView *)createMainView;
- (void)refreshFromSystem;
- (IBAction)applySelection:(id)sender;
- (IBAction)swapCheckboxChanged:(id)sender;

@end
