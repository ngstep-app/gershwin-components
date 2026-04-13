/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "ActionSearch.h"
#import "AppMenuWidget.h"
#import "X11ShortcutManager.h"
#import <GNUstepGUI/GSTheme.h>
#import <pthread.h>
#import <dispatch/dispatch.h>

// Singleton instance
static ActionSearchController *_sharedController = nil;
static pthread_mutex_t _singletonMutex = PTHREAD_MUTEX_INITIALIZER;

static const CGFloat kSearchFieldWidth = 200;
static const CGFloat kSearchFieldHeight = 22;
static const CGFloat kMaxResultsShown = 15;


#pragma mark - ActionSearchPanel (custom panel that accepts keyboard)

@interface ActionSearchPanel : NSPanel
@end

@implementation ActionSearchPanel

- (BOOL)canBecomeKeyWindow
{
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

@end


#pragma mark - ActionSearchResult

@implementation ActionSearchResult

- (id)initWithMenuItem:(NSMenuItem *)item path:(NSString *)path
{
    self = [super init];
    if (self) {
        self.menuItem = item;
        self.title = [item title];
        self.path = path;
        self.keyEquivalent = [item keyEquivalent] ?: @"";
        self.modifierMask = [item keyEquivalentModifierMask];
        self.enabled = [item isEnabled];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"ActionSearchResult: %@ (%@)", self.title, self.path];
}

@end


#pragma mark - ActionSearchController

@interface ActionSearchController ()
@property (nonatomic, assign) BOOL resultsMenuTracking;
@end

@implementation ActionSearchController

- (void)_deferredFocusToSearchField
{
    if ([self.searchPanel isVisible]) {
        [self.searchPanel makeKeyWindow];
        [self.searchPanel makeFirstResponder:self.searchField];
        [self.searchField selectText:nil];
    }
}

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
        
        [self createSearchPanel];
        [self createResultsMenu];
    }
    return self;
}

- (void)createSearchPanel
{
    // Create a small panel just for the search field
    // Use borderless style - keyboard routing is handled in MenuApplication.sendEvent:
    // Reduce vertical padding and make the panel transparent so the results menu can sit flush
    NSRect panelRect = NSMakeRect(0, 0, kSearchFieldWidth + 16, kSearchFieldHeight + 4);
    
    self.searchPanel = [[ActionSearchPanel alloc] initWithContentRect:panelRect
                                                  styleMask:NSBorderlessWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    [self.searchPanel setLevel:NSPopUpMenuWindowLevel];
    [self.searchPanel setHasShadow:NO];
    // Use a transparent background so there is no visible gap between field and results menu
    [self.searchPanel setOpaque:NO];
    [self.searchPanel setBackgroundColor:[NSColor clearColor]];
    [self.searchPanel setBecomesKeyOnlyIfNeeded:NO];
    [self.searchPanel setReleasedWhenClosed:NO];
    
    // Create search field (positioned close to bottom edge)
    self.searchField = [[NSTextField alloc] initWithFrame:
        NSMakeRect(8, 2, kSearchFieldWidth, kSearchFieldHeight)];
    [self.searchField setDelegate:self];
    [self.searchField setBordered:YES];
    [self.searchField setBezeled:YES];
    [self.searchField setBezelStyle:NSTextFieldRoundedBezel];
    [self.searchField setEditable:YES];
    [self.searchField setSelectable:YES];
    [self.searchField setEnabled:YES];
    [self.searchField setFont:[NSFont systemFontOfSize:12]];
    
    // Placeholder
    NSAttributedString *placeholder = [[NSAttributedString alloc] 
        initWithString:@"Search menus..."
        attributes:@{
            NSForegroundColorAttributeName: [NSColor grayColor],
            NSFontAttributeName: [NSFont systemFontOfSize:12]
        }];
    [[self.searchField cell] setPlaceholderAttributedString:placeholder];
    
    [[self.searchPanel contentView] addSubview:self.searchField];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(searchPanelDidResignKey:)
                   name:NSWindowDidResignKeyNotification
                 object:self.searchPanel];
    [center addObserver:self
               selector:@selector(applicationDidResignActive:)
                   name:NSApplicationDidResignActiveNotification
                 object:nil];
    
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Created search panel");
}

- (void)createResultsMenu
{
    self.resultsMenu = [[NSMenu alloc] initWithTitle:@"Search Results"];
    [self.resultsMenu setAutoenablesItems:NO];

    // Use delegate methods to prevent the menu opening when the search panel is not visible
    [self.resultsMenu setDelegate:self];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(resultsMenuDidBeginTracking:)
                   name:NSMenuDidBeginTrackingNotification
                 object:self.resultsMenu];
    [center addObserver:self
               selector:@selector(resultsMenuDidEndTracking:)
                   name:NSMenuDidEndTrackingNotification
                 object:self.resultsMenu];
    
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Created results menu");
}

- (void)setAppMenuWidget:(AppMenuWidget *)widget
{
    _appMenuWidget = widget;
}

- (void)showSearchPopupAtPoint:(NSPoint)point
{
    // Suspend global key grabs
    [[X11ShortcutManager sharedManager] suspendKeyGrabs];
    
    // Collect menu items
    [self collectMenuItems];
    
    // Reset state
    [self.searchField setStringValue:@""];
    [self.filteredResults removeAllObjects];
    
    // Store location for showing results menu (unused, we position at left edge)
    self.popupLocation = point;

    // Position panel directly underneath the menu bar at the left edge of the screen
    NSRect panelFrame = [self.searchPanel frame];
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    const CGFloat menuBarHeight = [[GSTheme theme] menuBarHeight];

    // Left edge margin
    CGFloat leftMargin = screenFrame.origin.x + 8;

    panelFrame.origin.x = leftMargin;
    // Place panel such that its top aligns with the bottom of the menu bar
    panelFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - menuBarHeight - panelFrame.size.height;

    [self.searchPanel setFrame:panelFrame display:YES];

    // Ensure our application is active so the search field receives key events immediately
    [NSApp activateIgnoringOtherApps:YES];

    [self.searchPanel makeKeyAndOrderFront:nil];

    // Focus and select the search field so the caret is ready and typing works without extra click
    // Some window managers / race conditions require a short deferred make-first-responder to be reliable
    [self.searchPanel makeFirstResponder:self.searchField];
    [self.searchField selectText:nil];

    // Also enforce focus on the next runloop tick to handle edge cases where focus isn't accepted immediately
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _deferredFocusToSearchField];
    });

    // Some window managers are flaky about initial focus; attempt multiple re-assertions of
    // activation and first-responder to make sure typing works without an extra click.
    [NSApp activateIgnoringOtherApps:YES];
    [self.searchPanel makeKeyWindow];
    [self.searchPanel makeFirstResponder:self.searchField];
    [self.searchField selectText:nil];
    // Additional deferred enforcement in case focus is stolen by the WM during stacking
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _deferredFocusToSearchField];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _deferredFocusToSearchField];
    });

    // We rely on MenuApplication.sendEvent: to detect outside clicks and hide the search popup
    self.resultsMenuTracking = NO;

    NSDebugLLog(@"gwcomp", @"ActionSearchController: Showing search popup at left edge x=%.0f, y=%.0f", panelFrame.origin.x, panelFrame.origin.y);
}

- (void)hideSearchPopup
{
    if (self.resultsMenuTracking) {
        if ([self.resultsMenu respondsToSelector:@selector(cancelTracking)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.resultsMenu performSelector:@selector(cancelTracking)];
            #pragma clang diagnostic pop
        }
        self.resultsMenuTracking = NO;
    }

    // Ensure there are no stray menu windows left open
    [self closeAllMenuWindows];

    [self.searchPanel orderOut:nil];
    [[X11ShortcutManager sharedManager] resumeKeyGrabs];
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Hiding search popup");
}

- (void)toggleSearchPopupAtPoint:(NSPoint)point
{
    if ([self.searchPanel isVisible]) {
        [self hideSearchPopup];
    } else {
        [self showSearchPopupAtPoint:point];
    }
}

- (void)toggleSearch:(id)sender
{
    // If we have a stored location from a previous click, use it? 
    // Or just default to center of screen or under the mouse?
    // For Cmd-Space, let's put it in the center of the screen
    
    if ([self.searchPanel isVisible]) {
        [self hideSearchPopup];
        return;
    }
    
    // Default to center of screen if not triggered by mouse click in potential menu
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    NSPoint centerPoint = NSMakePoint(
        screenFrame.origin.x + screenFrame.size.width / 2,
        screenFrame.origin.y + screenFrame.size.height / 2 + 200 // Slightly above center
    );
    
    [self showSearchPopupAtPoint:centerPoint];
}

#pragma mark - Menu Collection

- (void)collectMenuItems
{
    [self.allMenuItems removeAllObjects];
    
    if (!self.appMenuWidget) {
        NSDebugLLog(@"gwcomp", @"ActionSearchController: No appMenuWidget set");
        return;
    }
    
    NSMenu *currentMenu = [self.appMenuWidget currentMenu];
    if (!currentMenu) {
        NSDebugLLog(@"gwcomp", @"ActionSearchController: No current menu available");
        return;
    }
    
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Collecting items from: %@", [currentMenu title]);
    [self collectItemsFromMenu:currentMenu withPath:@""];
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Collected %lu menu items", (unsigned long)[self.allMenuItems count]);
}

- (void)collectItemsFromMenu:(NSMenu *)menu withPath:(NSString *)path
{
    if (!menu) return;
    
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item isSeparatorItem]) continue;
        
        // Skip the Search... menu item to avoid the search results containing itself
        if ([[item title] isEqualToString:@"Search..."]) continue;
        
        NSString *itemPath;
        NSString *itemTitle = [item title];
        
        // Append submenu indicator if this item has a submenu
        if ([item hasSubmenu]) {
            itemTitle = [NSString stringWithFormat:@"%@ ▷", itemTitle];
        }
        
        if ([path length] > 0) {
            itemPath = [NSString stringWithFormat:@"%@ %@", path, itemTitle];
        } else {
            itemPath = itemTitle;
        }
        
        if ([item hasSubmenu]) {
            [self collectItemsFromMenu:[item submenu] withPath:itemPath];
        } else if ([item action] != nil) {
            // Include both enabled and disabled items, but track enabled state
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
        
        if ([self.filteredResults count] >= kMaxResultsShown) {
            break;
        }
    }
    
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Search '%@' found %lu results", 
          searchString, (unsigned long)[self.filteredResults count]);
    
    [self showResultsMenu];
}

- (void)showResultsMenu
{
    // Don't show results unless the search panel is visible and there is a query
    if (![self.searchPanel isVisible]) {
        NSDebugLLog(@"gwcomp", @"ActionSearchController: Not showing results menu because search panel is not visible");
        return;
    }

    NSString *currentQuery = [[self.searchField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([currentQuery length] == 0) {
        // Nothing to show
        return;
    }

    // Clear old items
    [self.resultsMenu removeAllItems];
    
    if ([self.filteredResults count] == 0) {
        return;
    }
    
    // Add result items, with separators between different top-level menus
    NSString *previousTopLevelMenu = @"";
    for (NSUInteger i = 0; i < [self.filteredResults count]; i++) {
        ActionSearchResult *result = [self.filteredResults objectAtIndex:i];
        
        // Extract top-level menu (first component of the path)
        NSString *topLevelMenu = result.path;
        NSRange firstSpace = [topLevelMenu rangeOfString:@" "];
        if (firstSpace.location != NSNotFound) {
            topLevelMenu = [topLevelMenu substringToIndex:firstSpace.location];
        }
        // Remove submenu indicator if present
        topLevelMenu = [topLevelMenu stringByReplacingOccurrencesOfString:@" ▷" withString:@""];
        
        // Add separator if top-level menu changed (but not before the first item)
        if (i > 0 && ![topLevelMenu isEqual:previousTopLevelMenu]) {
            [self.resultsMenu addItem:[NSMenuItem separatorItem]];
        }
        
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[result path]
                                                      action:@selector(resultMenuItemClicked:)
                                               keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:result];
        // Respect the enabled state from the original menu item
        [item setEnabled:[result enabled]];
        
        // Show keyboard shortcut if available
        if ([[result keyEquivalent] length] > 0) {
            [item setKeyEquivalent:[result keyEquivalent]];
            [item setKeyEquivalentModifierMask:[result modifierMask]];
        }
        
        [self.resultsMenu addItem:item];
        previousTopLevelMenu = topLevelMenu;
    }
    
    // Position menu below the search panel at the left edge of the screen
    NSRect panelFrame = [self.searchPanel frame];
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    CGFloat leftX = screenFrame.origin.x + 8;
    
    // If a menu is already tracking, cancel it so we can re-populate and re-open
    if (self.resultsMenuTracking) {
        if ([self.resultsMenu respondsToSelector:@selector(cancelTracking)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.resultsMenu performSelector:@selector(cancelTracking)];
            #pragma clang diagnostic pop
        }
        self.resultsMenuTracking = NO;
    }

    // Align menu with the left edge and show it directly under the search panel
    NSPoint menuLocation = NSMakePoint(leftX, panelFrame.origin.y - 1);

    // Pop up the menu in screen coordinates (inView:nil) so it's flush with screen edge
    self.resultsMenuTracking = YES;
    [self.resultsMenu popUpMenuPositioningItem:nil 
                                    atLocation:menuLocation 
                                        inView:nil];
}

- (void)resultMenuItemClicked:(NSMenuItem *)sender
{
    ActionSearchResult *result = [sender representedObject];
    if (result) {
        NSDebugLLog(@"gwcomp", @"ActionSearchController: Selected: %@", [result path]);
        [self hideSearchPopup];
        [self executeActionForResult:result];
    }
}

#pragma mark - Action Execution

- (void)executeActionForResult:(ActionSearchResult *)result
{
    if (!result || !result.menuItem) {
        NSDebugLLog(@"gwcomp", @"ActionSearchController: Cannot execute - no result or menu item");
        return;
    }
    
    NSMenuItem *originalItem = result.menuItem;
    
    NSDebugLLog(@"gwcomp", @"ActionSearchController: Executing action for: %@", [result path]);
    
    // Try to invoke the menu item's action
    if ([originalItem target] && [originalItem action]) {
        @try {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [[originalItem target] performSelector:[originalItem action] withObject:originalItem];
            #pragma clang diagnostic pop
        } @catch (NSException *exception) {
            NSDebugLLog(@"gwcomp", @"ActionSearchController: Exception executing action: %@", exception);
        }
    } else if ([originalItem action]) {
        // No target - try first responder chain
        [NSApp sendAction:[originalItem action] to:nil from:originalItem];
    }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification
{
    (void)notification;
    NSString *searchString = [self.searchField stringValue];
    [self searchWithString:searchString];
}

#pragma mark - Focus Tracking

- (void)closeAllMenuWindows
{
    // Iterate over all app windows and close any that appear to be menu windows (NSMenu panels)
    for (NSWindow *win in [NSApp windows]) {
        NSString *cls = NSStringFromClass([win class]);
        if ([cls hasPrefix:@"NSMenu"] || [cls hasPrefix:@"NSStatusBar"]) {
            // Order out the menu window to ensure it disappears
            @try {
                [win orderOut:nil];
                NSDebugLLog(@"gwcomp", @"ActionSearchController: Closed menu window of class %@", cls);
            } @catch (NSException *e) {
                (void)e;
            }
        }
    }
}


- (void)searchPanelDidResignKey:(NSNotification *)notification
{
    (void)notification;
    if (self.resultsMenuTracking) {
        return;
    }
    [self hideSearchPopup];
}

- (void)applicationDidResignActive:(NSNotification *)notification
{
    (void)notification;
    [self hideSearchPopup];
}

- (void)resultsMenuDidBeginTracking:(NSNotification *)notification
{
    (void)notification;
    self.resultsMenuTracking = YES;
}

- (void)resultsMenuDidEndTracking:(NSNotification *)notification
{
    (void)notification;
    self.resultsMenuTracking = NO;
    // Hide search UI whenever results tracking ends unless the search panel is the key window
    // (user might have clicked back into the search field)
    if (![self.searchPanel isKeyWindow]) {
        [self hideSearchPopup];
    } else {
        // If search panel is still key (user clicked back into field), keep it open but stop tracking state
    }
}

#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu *)menu
{
    if (menu == self.resultsMenu) {
        // Prevent the results menu from opening unless the search panel is visible
        if (![self.searchPanel isVisible]) {
            NSDebugLLog(@"gwcomp", @"ActionSearchController: Preventing results menu open because search panel is hidden");
            // Explicitly close any menu windows to ensure no stray menu remains
            [self closeAllMenuWindows];
            self.resultsMenuTracking = NO;
        }
    }
}

- (void)menuDidClose:(NSMenu *)menu
{
    if (menu == self.resultsMenu) {
        self.resultsMenuTracking = NO;
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    (void)control;
    (void)textView;

    // Handle common text commands for the search field
    if (commandSelector == @selector(selectAll:)) {
        [textView selectAll:nil];
        return YES;
    }
    if (commandSelector == @selector(copy:)) {
        [textView copy:nil];
        return YES;
    }
    if (commandSelector == @selector(paste:)) {
        [textView paste:nil];
        return YES;
    }

    // Arrow down should show results and highlight the first result if present
    if (commandSelector == @selector(moveDown:)) {
        if ([self.filteredResults count] > 0) {
            [self showResultsMenu];

            // Highlight the first selectable item if possible
            NSInteger firstIndex = -1;
            NSArray *items = [self.resultsMenu itemArray];
            for (NSInteger ii = 0; ii < (NSInteger)[items count]; ii++) {
                NSMenuItem *mi = [items objectAtIndex:ii];
                if (![mi isSeparatorItem] && [mi isEnabled]) { firstIndex = ii; break; }
            }
            if (firstIndex >= 0) {
                if ([self.resultsMenu respondsToSelector:@selector(setHighlightedItemIndex:)]) {
                    // Use NSInvocation to call selector with NSInteger argument safely
                    SEL sel = @selector(setHighlightedItemIndex:);
                    NSMethodSignature *sig = [self.resultsMenu methodSignatureForSelector:sel];
                    if (sig) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setSelector:sel];
                        [inv setTarget:self.resultsMenu];
                        NSInteger idx = firstIndex;
                        [inv setArgument:&idx atIndex:2];
                        [inv invoke];
                    }
                }
            }
            return YES;
        }
        return NO;
    }

    // Arrow up should show results and highlight the last item
    if (commandSelector == @selector(moveUp:)) {
        if ([self.filteredResults count] > 0) {
            [self showResultsMenu];
            // Find last selectable enabled item and highlight it
            NSInteger lastIndex = -1;
            NSArray *items = [self.resultsMenu itemArray];
            for (NSInteger ii = (NSInteger)[items count] - 1; ii >= 0; ii--) {
                NSMenuItem *mi = [items objectAtIndex:ii];
                if (![mi isSeparatorItem] && [mi isEnabled]) { lastIndex = ii; break; }
            }
            if (lastIndex >= 0 && [self.resultsMenu respondsToSelector:@selector(setHighlightedItemIndex:)]) {
                SEL sel = @selector(setHighlightedItemIndex:);
                NSMethodSignature *sig = [self.resultsMenu methodSignatureForSelector:sel];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setSelector:sel];
                    [inv setTarget:self.resultsMenu];
                    NSInteger idx = lastIndex;
                    [inv setArgument:&idx atIndex:2];
                    [inv invoke];
                }
            }
            return YES;
        }
        return NO;
    }

    if (commandSelector == @selector(cancelOperation:)) {
        // Escape key - hide popup and reset, then return focus to other app
        [self.searchField setStringValue:@""];
        [self hideSearchPopup];

        // Deactivate the Menu application so other apps regain keyboard focus
        [NSApp deactivate];

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
        // Nothing special needed
    }
    return self;
}

- (void)setAppMenuWidget:(AppMenuWidget *)widget
{
    _appMenuWidget = widget;
    [[ActionSearchController sharedController] setAppMenuWidget:widget];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    
    // Draw search icon (magnifying glass)
    NSString *searchIcon = @"🔍";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor darkGrayColor]
    };
    
    NSSize iconSize = [searchIcon sizeWithAttributes:attrs];
    NSPoint iconPoint = NSMakePoint((self.bounds.size.width - iconSize.width) / 2,
                                    (self.bounds.size.height - iconSize.height) / 2);
    [searchIcon drawAtPoint:iconPoint withAttributes:attrs];
}

- (void)mouseDown:(NSEvent *)event
{
    (void)event;
    
    // Get click location in screen coordinates
    NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
    NSPoint screenLocation = [[self window] convertBaseToScreen:
        [self convertPoint:locationInView toView:nil]];
    
    [[ActionSearchController sharedController] toggleSearchPopupAtPoint:screenLocation];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}

@end
