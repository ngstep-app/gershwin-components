/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "MenuProtocolManager.h"
#import "GNUStepMenuIPC.h"

@class AppMenuWidget;

@interface GNUStepMenuImporter : NSObject <MenuProtocolHandler, GSGNUstepMenuServer>

@property (nonatomic, weak) AppMenuWidget *appMenuWidget;

// Synchronously fetch fresh enabled/state data from the client and apply it
// to the stored NSMenu for windowId.  Called from AppMenuWidget.menuNeedsUpdate:
// right before a submenu is shown, guaranteeing up-to-date item states.
// Returns YES when the NSMenu was successfully refreshed.
- (BOOL)refreshMenuStateForWindow:(unsigned long)windowId;

@end
