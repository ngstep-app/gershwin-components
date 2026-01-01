/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "ActionSearch.h"
#import "AppMenuWidget.h"
#import <GNUstepGUI/GSTheme.h>
#import <pthread.h>

// Singleton instance
static ActionSearchController *_sharedController = nil;
static pthread_mutex_t _singletonMutex = PTHREAD_MUTEX_INITIALIZER;

static const CGFloat kSearchWindowWidth = 300;
static const CGFloat kSearchFieldHeight = 24;
static const CGFloat kResultRowHeight = 22;
static const CGFloat kMaxResultsShown = 12;
static const CGFloat kWindowPadding = 8;

#pragma mark - ActionSearchResult

@implementation ActionSearchResult

- (id)initWithMenuItem:(NSMenuItem *)item path:(NSString *)path
{
    self = [super init];
    if (self) {
        self.menuItem = item;
        self.title = [item title];
        self.path = path;
        self.keyEquivalent = [item keyEquivalent];
        self.modifierMask = [item keyEquivalentModifierMask];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"ActionSearchResult: %@ (%@)", self.title, self.path];
}

@end


#pragma mark - ActionSearchWindow

@implementation ActionSearchWindow

- (id)initWithContentRect:(NSRect)contentRect
{
    // Use borderless window but with different approach for keyboard
    self = [super initWithContentRect:contentRect
                            styleMask:NSBorderlessWindowMask | NSNonactivatingPanelMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        [self setLevel:NSFloatingWindowLevel];
        [self setHasShadow:YES];
        [self setOpaque:YES];
        [self setBackgroundColor:[[GSTheme theme] menuBackgroundColor]];
        [self setMovableByWindowBackground:NO];
        [self setReleasedWhenClosed:NO];
        // Key settings for keyboard input with borderless window
        [self setAcceptsMouseMovedEvents:YES];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow
{
    // Critical: borderless windows must explicitly return YES to receive keyboard events
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    NSLog(@"ActionSearchWindow: keyDown received: %@", [event characters]);
    [super keyDown:event];
}

- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSKeyDown) {
        NSLog(@"ActionSearchWindow: sendEvent KeyDown: %@", [event characters]);
    }
    [super sendEvent:event];
}

@end


#pragma mark - ActionSearchContentView

@interface ActionSearchContentView : NSView
@end

@implementation ActionSearchContentView

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    
    // Draw menu-like background with rounded corners
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4];
    
    // Fill with menu background color
    [[[GSTheme theme] menuBackgroundColor] set];
    [path fill];
    
    // Draw subtle border
    [[NSColor lightGrayColor] set];
    [path stroke];
}

- (BOOL)isFlipped
{
    return NO;
}

@end


#pragma mark - ActionSearchResultView

@implementation ActionSearchResultView

- (id)initWithFrame:(NSRect)frameRect result:(ActionSearchResult *)result
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.result = result;
        self.isHighlighted = NO;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.isHighlighted) {
        [[NSColor selectedMenuItemColor] set];
        NSRectFill(self.bounds);
    }
    
    // Draw the path text
    NSDictionary *attrs;
    if (self.isHighlighted) {
        attrs = @{
            NSFontAttributeName: [NSFont menuFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor selectedMenuItemTextColor]
        };
    } else {
        attrs = @{
            NSFontAttributeName: [NSFont menuFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor textColor]
        };
    }
    
    NSString *displayText = [self.result path];
    NSRect textRect = NSInsetRect(self.bounds, 8, 2);
    
    // If there's a shortcut, show it on the right
    if ([[self.result keyEquivalent] length] > 0) {
        NSString *shortcut = [self shortcutString];
        NSDictionary *shortcutAttrs;
        if (self.isHighlighted) {
            shortcutAttrs = @{
                NSFontAttributeName: [NSFont menuFontOfSize:11],
                NSForegroundColorAttributeName: [[NSColor selectedMenuItemTextColor] colorWithAlphaComponent:0.8]
            };
        } else {
            shortcutAttrs = @{
                NSFontAttributeName: [NSFont menuFontOfSize:11],
                NSForegroundColorAttributeName: [NSColor darkGrayColor]
            };
        }
        
        NSSize shortcutSize = [shortcut sizeWithAttributes:shortcutAttrs];
        NSRect shortcutRect = NSMakeRect(NSMaxX(textRect) - shortcutSize.width, 
                                         textRect.origin.y + (textRect.size.height - shortcutSize.height) / 2,
                                         shortcutSize.width, shortcutSize.height);
        [shortcut drawInRect:shortcutRect withAttributes:shortcutAttrs];
        
        // Adjust text rect to not overlap with shortcut
        textRect.size.width -= shortcutSize.width + 10;
    }
    
    [displayText drawInRect:textRect withAttributes:attrs];
}

- (NSString *)shortcutString
{
    NSMutableString *shortcut = [NSMutableString string];
    NSUInteger mask = [self.result modifierMask];
    
    if (mask & NSCommandKeyMask) {
        [shortcut appendString:@"⌘"];
    }
    if (mask & NSShiftKeyMask) {
        [shortcut appendString:@"⇧"];
    }
    if (mask & NSAlternateKeyMask) {
        [shortcut appendString:@"⌥"];
    }
    if (mask & NSControlKeyMask) {
        [shortcut appendString:@"⌃"];
    }
    
    NSString *key = [[self.result keyEquivalent] uppercaseString];
    [shortcut appendString:key];
    
    return shortcut;
}

- (void)mouseDown:(NSEvent *)event
{
    (void)event;
    if (self.target && self.action) {
        [self.target performSelector:self.action withObject:self];
    }
}

// Use mouseMoved for hover effects since NSTrackingArea is not available in GNUstep
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}

@end


#pragma mark - ActionSearchController

@implementation ActionSearchController

+ (instancetype)sharedController
{
    pthread_mutex_lock(&_singletonMutex);
    if (_sharedController == nil) {
        _sharedController = [[ActionSearchController alloc] init];
    }
    pthread_mutex_unlock(&_singletonMutex);
    return _sharedController;
}

- (id)init
{
    self = [super init];
    if (self) {
        self.allMenuItems = [NSMutableArray array];
        self.filteredResults = [NSMutableArray array];
        self.resultViews = [NSMutableArray array];
        self.selectedIndex = -1;
        
        [self createSearchWindow];
    }
    return self;
}

- (void)createSearchWindow
{
    // Create window with sufficient content height
    CGFloat contentHeight = kSearchFieldHeight + kWindowPadding * 2;
    NSRect contentRect = NSMakeRect(0, 0, kSearchWindowWidth, contentHeight);
    
    self.searchWindow = [[ActionSearchWindow alloc] initWithContentRect:contentRect];
    
    // Use the system-created content view and add a background view to it
    NSView *contentView = [self.searchWindow contentView];
    [contentView setAutoresizesSubviews:YES];
    
    NSLog(@"ActionSearchController: Window content view frame: %.0f,%.0f %.0fx%.0f",
          contentView.frame.origin.x, contentView.frame.origin.y, 
          contentView.frame.size.width, contentView.frame.size.height);
    
    // Add a background view that draws menu-like appearance
    ActionSearchContentView *bgView = [[ActionSearchContentView alloc] initWithFrame:contentView.bounds];
    [bgView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [contentView addSubview:bgView];
    
    // Create search field at the top of content area
    CGFloat fieldY = contentView.frame.size.height - kSearchFieldHeight - kWindowPadding;
    self.searchField = [[NSTextField alloc] initWithFrame:
        NSMakeRect(kWindowPadding, fieldY, kSearchWindowWidth - kWindowPadding * 2, kSearchFieldHeight)];
    [self.searchField setDelegate:self];
    [self.searchField setBordered:YES];
    [self.searchField setBezeled:YES];
    [self.searchField setBezelStyle:NSTextFieldRoundedBezel];
    [self.searchField setEditable:YES];
    [self.searchField setSelectable:YES];
    [self.searchField setEnabled:YES];
    [self.searchField setFont:[NSFont systemFontOfSize:13]];
    [self.searchField setRefusesFirstResponder:NO];
    [[self.searchField cell] setSendsActionOnEndEditing:NO];
    [[self.searchField cell] setScrollable:YES];
    
    // Placeholder text
    NSAttributedString *placeholder = [[NSAttributedString alloc] 
        initWithString:@"Search menus..."
        attributes:@{
            NSForegroundColorAttributeName: [NSColor grayColor],
            NSFontAttributeName: [NSFont systemFontOfSize:13]
        }];
    [[self.searchField cell] setPlaceholderAttributedString:placeholder];
    
    [contentView addSubview:self.searchField];
    
    // Create scroll view for results (initially hidden)
    self.resultsScrollView = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(kWindowPadding, kWindowPadding, 
                   kSearchWindowWidth - kWindowPadding * 2, 0)];
    [self.resultsScrollView setHasVerticalScroller:YES];
    [self.resultsScrollView setHasHorizontalScroller:NO];
    [self.resultsScrollView setBorderType:NSNoBorder];
    [self.resultsScrollView setAutohidesScrollers:YES];
    [self.resultsScrollView setDrawsBackground:NO];
    
    self.resultsContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 
        kSearchWindowWidth - kWindowPadding * 2, 0)];
    [self.resultsScrollView setDocumentView:self.resultsContainer];
    
    [contentView addSubview:self.resultsScrollView];
    
    NSLog(@"ActionSearchController: Created search window");
}

- (void)setAppMenuWidget:(AppMenuWidget *)widget
{
    _appMenuWidget = widget;
}

- (void)showSearchPopupAtPoint:(NSPoint)point
{
    // Collect menu items first
    [self collectMenuItems];
    
    // Reset state
    [self.searchField setStringValue:@""];
    [self.filteredResults removeAllObjects];
    self.selectedIndex = -1;
    [self updateResultsDisplay];
    
    // Position window below the click point
    CGFloat windowHeight = kSearchFieldHeight + kWindowPadding * 2;
    NSRect windowFrame = NSMakeRect(point.x - kSearchWindowWidth / 2, 
                                    point.y - windowHeight,
                                    kSearchWindowWidth, 
                                    windowHeight);
    
    // Make sure window stays on screen
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    if (NSMaxX(windowFrame) > NSMaxX(screenFrame)) {
        windowFrame.origin.x = NSMaxX(screenFrame) - kSearchWindowWidth - 10;
    }
    if (windowFrame.origin.x < screenFrame.origin.x) {
        windowFrame.origin.x = screenFrame.origin.x + 10;
    }
    
    [self.searchWindow setFrame:windowFrame display:YES];
    [self.searchWindow orderFront:nil];
    
    // Force the window to become key and focus the search field
    [NSApp activateIgnoringOtherApps:YES];
    [self.searchWindow makeKeyAndOrderFront:nil];
    
    // Use a slight delay to ensure the window is ready for first responder
    [self performSelector:@selector(focusSearchField) withObject:nil afterDelay:0.05];
    
    NSLog(@"ActionSearchController: Showing search popup at %.0f, %.0f", point.x, point.y);
}

- (void)hideSearchPopup
{
    [self.searchWindow orderOut:nil];
    NSLog(@"ActionSearchController: Hiding search popup");
}

- (void)focusSearchField
{
    NSLog(@"ActionSearchController: focusSearchField called");
    
    // Debug: Check the text field's state
    NSLog(@"ActionSearchController: searchField isEditable: %@", [self.searchField isEditable] ? @"YES" : @"NO");
    NSLog(@"ActionSearchController: searchField isSelectable: %@", [self.searchField isSelectable] ? @"YES" : @"NO");
    NSLog(@"ActionSearchController: searchField isEnabled: %@", [self.searchField isEnabled] ? @"YES" : @"NO");
    NSLog(@"ActionSearchController: searchField superview: %@", [self.searchField superview]);
    NSLog(@"ActionSearchController: searchField window: %@", [self.searchField window]);
    NSLog(@"ActionSearchController: searchWindow: %@", self.searchWindow);
    
    // Ensure window is key
    [self.searchWindow makeKeyWindow];
    NSLog(@"ActionSearchController: Window is key: %@", [self.searchWindow isKeyWindow] ? @"YES" : @"NO");
    
    // Check if field is in window
    if ([self.searchField window] != self.searchWindow) {
        NSLog(@"ActionSearchController: ERROR - searchField is not in searchWindow!");
    }
    
    // Try making the text field first responder
    BOOL success = [self.searchWindow makeFirstResponder:self.searchField];
    NSLog(@"ActionSearchController: makeFirstResponder result: %@", success ? @"YES" : @"NO");
    
    if (!success) {
        // Try clicking on the text field programmatically
        NSLog(@"ActionSearchController: Trying selectText approach");
        [self.searchField selectText:self];
        
        // Try using the field editor directly
        NSText *fieldEditor = [self.searchWindow fieldEditor:YES forObject:self.searchField];
        if (fieldEditor) {
            NSLog(@"ActionSearchController: Got field editor: %@, trying to focus it", fieldEditor);
            success = [self.searchWindow makeFirstResponder:fieldEditor];
            NSLog(@"ActionSearchController: makeFirstResponder on fieldEditor result: %@", success ? @"YES" : @"NO");
        } else {
            NSLog(@"ActionSearchController: Could not get field editor");
        }
    }
}

- (void)toggleSearchPopupAtPoint:(NSPoint)point
{
    if ([self.searchWindow isVisible]) {
        [self hideSearchPopup];
    } else {
        [self showSearchPopupAtPoint:point];
    }
}

#pragma mark - Menu Item Collection

- (void)collectMenuItems
{
    [self.allMenuItems removeAllObjects];
    
    if (!self.appMenuWidget) {
        NSLog(@"ActionSearchController: No appMenuWidget set, cannot collect menu items");
        return;
    }
    
    NSMenu *currentMenu = [self.appMenuWidget currentMenu];
    if (!currentMenu) {
        NSLog(@"ActionSearchController: No current menu available");
        return;
    }
    
    NSLog(@"ActionSearchController: Collecting menu items from menu: %@", [currentMenu title]);
    
    // Recursively collect all menu items
    [self collectItemsFromMenu:currentMenu withPath:@""];
    
    NSLog(@"ActionSearchController: Collected %lu menu items", (unsigned long)[self.allMenuItems count]);
}

- (void)collectItemsFromMenu:(NSMenu *)menu withPath:(NSString *)path
{
    if (!menu) return;
    
    NSArray *items = [menu itemArray];
    for (NSMenuItem *item in items) {
        // Skip separator items
        if ([item isSeparatorItem]) {
            continue;
        }
        
        // Build the path for this item
        NSString *itemPath;
        NSString *itemTitle = [item title];
        
        if ([path length] > 0) {
            itemPath = [NSString stringWithFormat:@"%@ ▸ %@", path, itemTitle];
        } else {
            itemPath = itemTitle;
        }
        
        // If it has a submenu, recurse into it
        if ([item hasSubmenu]) {
            [self collectItemsFromMenu:[item submenu] withPath:itemPath];
        } else if ([item isEnabled] && [item action] != nil) {
            // Only add items that are enabled and have an action
            ActionSearchResult *result = [[ActionSearchResult alloc] initWithMenuItem:item path:itemPath];
            [self.allMenuItems addObject:result];
        }
    }
}

#pragma mark - Search

- (void)searchWithString:(NSString *)searchString
{
    [self.filteredResults removeAllObjects];
    
    if ([searchString length] == 0) {
        [self updateResultsDisplay];
        return;
    }
    
    NSString *lowercaseSearch = [searchString lowercaseString];
    
    for (ActionSearchResult *result in self.allMenuItems) {
        NSString *lowercaseTitle = [[result title] lowercaseString];
        NSString *lowercasePath = [[result path] lowercaseString];
        
        if ([lowercaseTitle rangeOfString:lowercaseSearch].location != NSNotFound ||
            [lowercasePath rangeOfString:lowercaseSearch].location != NSNotFound) {
            [self.filteredResults addObject:result];
        }
    }
    
    NSLog(@"ActionSearchController: Search '%@' found %lu results", 
          searchString, (unsigned long)[self.filteredResults count]);
    
    self.selectedIndex = ([self.filteredResults count] > 0) ? 0 : -1;
    [self updateResultsDisplay];
}

- (void)updateResultsDisplay
{
    // Remove old result views
    for (ActionSearchResultView *view in self.resultViews) {
        [view removeFromSuperview];
    }
    [self.resultViews removeAllObjects];
    
    NSUInteger count = MIN([self.filteredResults count], (NSUInteger)kMaxResultsShown);
    CGFloat resultsHeight = count * kResultRowHeight;
    
    // Resize the results container
    NSRect containerFrame = NSMakeRect(0, 0, 
                                       kSearchWindowWidth - kWindowPadding * 2, 
                                       [self.filteredResults count] * kResultRowHeight);
    [self.resultsContainer setFrame:containerFrame];
    
    // Add result views (from top to bottom in the flipped coordinate system)
    for (NSUInteger i = 0; i < [self.filteredResults count]; i++) {
        ActionSearchResult *result = [self.filteredResults objectAtIndex:i];
        
        // Position from top of container
        CGFloat y = containerFrame.size.height - (i + 1) * kResultRowHeight;
        NSRect rowFrame = NSMakeRect(0, y, containerFrame.size.width, kResultRowHeight);
        
        ActionSearchResultView *resultView = [[ActionSearchResultView alloc] 
            initWithFrame:rowFrame result:result];
        resultView.target = self;
        resultView.action = @selector(resultClicked:);
        resultView.isHighlighted = (i == (NSUInteger)self.selectedIndex);
        
        [self.resultsContainer addSubview:resultView];
        [self.resultViews addObject:resultView];
    }
    
    // Resize window to fit results - use setContentSize instead of setFrame
    CGFloat contentHeight = kSearchFieldHeight + kWindowPadding * 2;
    if (count > 0) {
        contentHeight += resultsHeight + kWindowPadding;
    }
    
    // Get current position and resize from top
    NSRect windowFrame = [self.searchWindow frame];
    NSRect oldContentRect = [[self.searchWindow contentView] frame];
    CGFloat heightDiff = contentHeight - oldContentRect.size.height;
    windowFrame.origin.y -= heightDiff;
    windowFrame.size.height += heightDiff;
    [self.searchWindow setFrame:windowFrame display:YES];
    
    // Get the new content view frame
    NSRect contentViewFrame = [[self.searchWindow contentView] frame];
    
    // Update scroll view frame
    CGFloat scrollHeight = resultsHeight;
    CGFloat scrollY = kWindowPadding;
    [self.resultsScrollView setFrame:NSMakeRect(kWindowPadding, scrollY, 
                                                kSearchWindowWidth - kWindowPadding * 2, 
                                                scrollHeight)];
    
    // Update search field position (at top of content view)
    CGFloat fieldY = contentViewFrame.size.height - kSearchFieldHeight - kWindowPadding;
    NSRect fieldFrame = [self.searchField frame];
    fieldFrame.origin.y = fieldY;
    [self.searchField setFrame:fieldFrame];
    
    NSLog(@"ActionSearchController: Updated layout - contentView: %.0fx%.0f, searchField at y=%.0f",
          contentViewFrame.size.width, contentViewFrame.size.height, fieldY);
    
    // Redraw content view
    [[self.searchWindow contentView] setNeedsDisplay:YES];
}

- (void)updateHighlight
{
    for (NSUInteger i = 0; i < [self.resultViews count]; i++) {
        ActionSearchResultView *view = [self.resultViews objectAtIndex:i];
        view.isHighlighted = (i == (NSUInteger)self.selectedIndex);
        [view setNeedsDisplay:YES];
    }
}

#pragma mark - Actions

- (void)resultClicked:(ActionSearchResultView *)sender
{
    [self executeActionForResult:sender.result];
}

- (void)executeActionForResult:(ActionSearchResult *)result
{
    if (!result || !result.menuItem) {
        NSLog(@"ActionSearchController: Cannot execute action - no valid result");
        return;
    }
    
    NSLog(@"ActionSearchController: Executing action: %@", [result path]);
    
    // Hide the popup first
    [self hideSearchPopup];
    
    // Get the original menu item
    NSMenuItem *originalItem = result.menuItem;
    
    // Try to invoke the action
    if ([originalItem target] && [originalItem action]) {
        @try {
            [[originalItem target] performSelector:[originalItem action] withObject:originalItem];
        }
        @catch (NSException *e) {
            NSLog(@"ActionSearchController: Exception executing action: %@", e);
        }
    } else if ([originalItem action]) {
        NSMenu *menu = [originalItem menu];
        if (menu) {
            @try {
                [menu performActionForItemAtIndex:[menu indexOfItem:originalItem]];
            }
            @catch (NSException *e) {
                NSLog(@"ActionSearchController: Exception performing menu action: %@", e);
            }
        }
    }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification
{
    (void)notification;
    NSString *searchString = [self.searchField stringValue];
    [self searchWithString:searchString];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    (void)control;
    (void)textView;
    
    if (commandSelector == @selector(moveUp:)) {
        if (self.selectedIndex > 0) {
            self.selectedIndex--;
            [self updateHighlight];
        }
        return YES;
    } else if (commandSelector == @selector(moveDown:)) {
        if (self.selectedIndex < (NSInteger)[self.filteredResults count] - 1) {
            self.selectedIndex++;
            [self updateHighlight];
        }
        return YES;
    } else if (commandSelector == @selector(insertNewline:)) {
        // Enter key - execute selected action
        if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)[self.filteredResults count]) {
            ActionSearchResult *result = [self.filteredResults objectAtIndex:self.selectedIndex];
            [self executeActionForResult:result];
        }
        return YES;
    } else if (commandSelector == @selector(cancelOperation:)) {
        // Escape key - close popup
        [self hideSearchPopup];
        return YES;
    }
    
    return NO;
}

@end


#pragma mark - ActionSearchMenuView

@implementation ActionSearchMenuView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        NSLog(@"ActionSearchMenuView: Initialized with frame %.0f,%.0f %.0fx%.0f",
              frameRect.origin.x, frameRect.origin.y, frameRect.size.width, frameRect.size.height);
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    
    // Draw background matching menu bar
    [[[GSTheme theme] menuItemBackgroundColor] set];
    NSRectFill(self.bounds);
    
    // Draw the search icon/text
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont menuFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor textColor]
    };
    
    NSString *label = @"🔍";
    NSSize labelSize = [label sizeWithAttributes:attrs];
    CGFloat x = (self.bounds.size.width - labelSize.width) / 2;
    CGFloat y = (self.bounds.size.height - labelSize.height) / 2;
    [label drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
}

- (void)setAppMenuWidget:(AppMenuWidget *)widget
{
    _appMenuWidget = widget;
    [[ActionSearchController sharedController] setAppMenuWidget:widget];
}

- (void)mouseDown:(NSEvent *)event
{
    (void)event;
    
    NSLog(@"ActionSearchMenuView: mouseDown triggered");
    
    // Get position below this view
    NSRect frame = [self frame];
    NSPoint point = NSMakePoint(NSMidX(frame), frame.origin.y);
    
    // Convert to screen coordinates
    point = [self convertPoint:point toView:nil];
    NSRect windowFrame = [[self window] frame];
    point.x += windowFrame.origin.x;
    point.y += windowFrame.origin.y;
    
    NSLog(@"ActionSearchMenuView: Triggering popup at screen point %.0f, %.0f", point.x, point.y);
    
    [[ActionSearchController sharedController] toggleSearchPopupAtPoint:point];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}

@end
