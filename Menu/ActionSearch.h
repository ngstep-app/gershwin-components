/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>

@class AppMenuWidget;

/**
 * ActionSearchResult - Represents a searchable menu item
 */
@interface ActionSearchResult : NSObject

@property (nonatomic, strong) NSString *title;           // Menu item title
@property (nonatomic, strong) NSString *path;            // Full path like "File ▸ Open"
@property (nonatomic, strong) NSString *keyEquivalent;   // Keyboard shortcut string
@property (nonatomic, assign) NSUInteger modifierMask;   // Modifier keys
@property (nonatomic, strong) NSMenuItem *menuItem;      // Reference to actual menu item
@property (nonatomic, assign) NSInteger menuIndex;       // Index in parent menu

- (id)initWithMenuItem:(NSMenuItem *)item path:(NSString *)path;

@end


/**
 * ActionSearchWindow - Popup window styled like a dropdown menu
 */
@interface ActionSearchWindow : NSWindow

- (id)initWithContentRect:(NSRect)contentRect;

@end


/**
 * ActionSearchResultView - A single result row in the search results
 */
@interface ActionSearchResultView : NSView

@property (nonatomic, strong) ActionSearchResult *result;
@property (nonatomic, assign) BOOL isHighlighted;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;

- (id)initWithFrame:(NSRect)frameRect result:(ActionSearchResult *)result;

@end


/**
 * ActionSearchController - Manages the search popup window and results
 */
@interface ActionSearchController : NSObject <NSTextFieldDelegate>

@property (nonatomic, strong) ActionSearchWindow *searchWindow;
@property (nonatomic, strong) NSTextField *searchField;
@property (nonatomic, strong) NSScrollView *resultsScrollView;
@property (nonatomic, strong) NSView *resultsContainer;
@property (nonatomic, strong) NSMutableArray *allMenuItems;
@property (nonatomic, strong) NSMutableArray *filteredResults;
@property (nonatomic, strong) NSMutableArray *resultViews;
@property (nonatomic, weak) AppMenuWidget *appMenuWidget;
@property (nonatomic, assign) NSInteger selectedIndex;

+ (instancetype)sharedController;

/**
 * Set the app menu widget reference to access current menus
 */
- (void)setAppMenuWidget:(AppMenuWidget *)widget;

/**
 * Show the search popup at the given screen location
 */
- (void)showSearchPopupAtPoint:(NSPoint)point;

/**
 * Hide the search popup
 */
- (void)hideSearchPopup;

/**
 * Toggle the search popup
 */
- (void)toggleSearchPopupAtPoint:(NSPoint)point;

/**
 * Collect all menu items from the current application menu
 */
- (void)collectMenuItems;

/**
 * Execute the selected action
 */
- (void)executeActionForResult:(ActionSearchResult *)result;

@end


/**
 * ActionSearchMenuView - Menu bar item that triggers the search popup
 */
@interface ActionSearchMenuView : NSView

@property (nonatomic, weak) AppMenuWidget *appMenuWidget;

- (id)initWithFrame:(NSRect)frameRect;
- (void)setAppMenuWidget:(AppMenuWidget *)widget;

@end
