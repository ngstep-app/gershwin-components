/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <dbus/dbus.h>

@interface MBDaemonLibDBus : NSObject {
    DBusServer *_server;
    DBusConnection *_systemBus;
    NSMutableArray *_connections;
    BOOL _running;
}

@property (nonatomic, assign) BOOL running;

- (BOOL)startWithSocketPath:(NSString *)socketPath;
- (void)stop;
- (void)runMainLoop;

@end
