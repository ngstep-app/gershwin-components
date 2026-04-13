/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>
#import <GSAssistantUtilities.h>
#import "SystemSetupSteps.h"

@interface SystemSetupAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation SystemSetupAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    NSDebugLLog(@"gwcomp", @"SystemSetupAssistant: Last window closed, terminating application");
    return YES;
}
@end

@interface SystemSetupDelegate : NSObject <GSAssistantWindowDelegate>
@end

@implementation SystemSetupDelegate

- (void)assistantWindowWillFinish:(GSAssistantWindow *)window {
    NSDebugLLog(@"gwcomp", @"System setup assistant will finish");
}

- (void)assistantWindowDidFinish:(GSAssistantWindow *)window {
    NSDebugLLog(@"gwcomp", @"System setup assistant finished");
    [NSApp terminate:nil];
}

- (BOOL)assistantWindow:(GSAssistantWindow *)window shouldCancelWithConfirmation:(BOOL)showConfirmation {
    if (showConfirmation) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cancel Setup?";
        alert.informativeText = @"Are you sure you want to cancel the setup? Any progress will be lost.";
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel Setup", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Continue Setup", @"")];
        alert.alertStyle = NSWarningAlertStyle;
        
        NSModalResponse response = [alert runModal];
        return response == NSAlertFirstButtonReturn;
    }
    return YES;
}

@end

@interface SystemSetupAssistant : NSObject
+ (void)showSetupAssistant;
@end

@implementation SystemSetupAssistant

+ (void)showSetupAssistant {
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Starting showSetupAssistant");
    SystemSetupDelegate *delegate = [[SystemSetupDelegate alloc] init];
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Created delegate: %@", delegate);
    
    // Build the assistant using the builder
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Creating builder...");
    GSAssistantBuilder *builder = [GSAssistantBuilder builder];
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Created builder: %@", builder);
    
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Setting title...");
    [builder withTitle:NSLocalizedString(@"System Setup Assistant", @"")];
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Setting icon...");
    [builder withIcon:[NSImage imageNamed:@"NSApplicationIcon"]];
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Adding user info step...");
    SSUserInfoStep *userInfoStep = [[SSUserInfoStep alloc] init];
    [builder addStep:userInfoStep];
    [userInfoStep release];
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Adding preferences step...");
    SSPreferencesStep *preferencesStep = [[SSPreferencesStep alloc] init];
    [builder addStep:preferencesStep];
    [preferencesStep release];
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Adding progress step...");
    [builder addProgressStep:@"Applying Settings" 
           description:@"Please wait while we apply your settings..."];
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Adding completion step...");
    [builder addCompletionWithMessage:@"Setup completed successfully! Your system is now ready to use." 
           success:YES];
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Building assistant...");
    GSAssistantWindow *assistant = [builder build];
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Built assistant: %@", assistant);
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Setting delegate...");
    assistant.delegate = delegate;
    
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Showing window...");
    [assistant showWindow:nil];
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Making window key and front...");
    [assistant.window makeKeyAndOrderFront:nil];
    NSDebugLLog(@"gwcomp", @"[SystemSetupAssistant] Assistant window should now be visible");
}

@end

// Main application entry point
int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        
        // Set up application delegate to ensure proper termination
        SystemSetupAppDelegate *appDelegate = [[SystemSetupAppDelegate alloc] init];
        [NSApp setDelegate:appDelegate];
        
        // Create menu bar
        NSMenu *mainMenu = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [mainMenu addItem:appMenuItem];
        [NSApp setMainMenu:mainMenu];
        
        NSMenu *appMenu = [[NSMenu alloc] init];
        NSMenuItem *quitMenuItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenu addItem:quitMenuItem];
        [appMenuItem setSubmenu:appMenu];
        
        // Show the assistant immediately
        [SystemSetupAssistant showSetupAssistant];
        
        [NSApp run];
        
        [appDelegate release];
    }
    return 0;
}
