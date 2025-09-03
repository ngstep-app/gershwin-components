#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "GNUstepGUI/GSTheme.h"

@interface MenuBarView : NSView

@property (nonatomic, strong) NSColor *backgroundColor;

- (void)drawRect:(NSRect)dirtyRect;

@end
