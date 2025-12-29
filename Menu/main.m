/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "MenuApplication.h"
#import "MenuController.h"
#import <signal.h>

int main(int __attribute__((unused)) argc, const char * __attribute__((unused)) argv[])
{
    NSLog(@"Menu.app: Starting application initialization...");
    
    @autoreleasepool {
        @try {
            // Create MenuApplication directly as the main application instance
            MenuApplication *app = [[MenuApplication alloc] init];
            
            // Set it as the shared application instance manually
            NSApp = app;
            
            NSLog(@"Menu.app: About to start main run loop...");
            
            // Run the application with better exception handling
            @try {
                [app run];
            } @catch (NSException *runException) {
                NSLog(@"Menu.app: Exception in run loop: %@", runException);
                NSLog(@"Menu.app: Run loop exception reason: %@", [runException reason]);
            }
            
            NSLog(@"Menu.app: Main run loop exited normally");
        } @catch (NSException *exception) {
            NSLog(@"Menu.app: Caught exception in main: %@", exception);
            NSLog(@"Menu.app: Exception reason: %@", [exception reason]);
            NSLog(@"Menu.app: Exception stack: %@", [exception callStackSymbols]);
            return 1;
        }
    }
    
    NSLog(@"Menu.app: Application exiting normally");
    return 0;
}
