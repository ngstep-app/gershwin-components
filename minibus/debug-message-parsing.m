/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <glib.h>
#import <gio/gio.h>
#import "MBClient.h"

static void mb_hexdump(NSData *data, NSString *prefix) {
    const uint8_t *bytes = [data bytes];
    NSUInteger length = [data length];
    
    printf("%s (%lu bytes):\n", [prefix UTF8String], length);
    for (NSUInteger i = 0; i < length; i += 16) {
        printf("%04lx: ", i);
        
        // Print hex bytes
        for (NSUInteger j = 0; j < 16; j++) {
            if (i + j < length) {
                printf("%02x ", bytes[i + j]);
            } else {
                printf("   ");
            }
        }
        
        printf(" ");
        
        // Print ASCII
        for (NSUInteger j = 0; j < 16 && i + j < length; j++) {
            uint8_t byte = bytes[i + j];
            printf("%c", (byte >= 32 && byte < 127) ? byte : '.');
        }
        
        printf("\n");
    }
    printf("\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"Starting D-Bus message parsing debug tool");
        
        // Connect to D-Bus using GDBus
        GError *error = NULL;
        GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
        if (!connection) {
            NSDebugLLog(@"gwcomp", @"Failed to connect to session bus: %s", error->message);
            g_error_free(error);
            return 1;
        }
        
        NSDebugLLog(@"gwcomp", @"Connected to D-Bus session bus");
        
        // Try calling StartServiceByName with debugging
        NSDebugLLog(@"gwcomp", @"Calling StartServiceByName for 'org.xfce.Session.Manager'...");
        
        GVariant *result = g_dbus_connection_call_sync(
            connection,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus", 
            "org.freedesktop.DBus",
            "StartServiceByName",
            g_variant_new("(su)", "org.xfce.Session.Manager", 0),
            G_VARIANT_TYPE("(u)"),
            G_DBUS_CALL_FLAGS_NONE,
            -1,
            NULL,
            &error
        );
        
        if (result) {
            guint32 reply_code;
            g_variant_get(result, "(u)", &reply_code);
            NSDebugLLog(@"gwcomp", @"StartServiceByName returned: %u", reply_code);
            g_variant_unref(result);
        } else {
            NSDebugLLog(@"gwcomp", @"StartServiceByName failed: %s", error ? error->message : "Unknown error");
            if (error) g_error_free(error);
        }
        
        // Try creating a proxy for org.freedesktop.DBus (should work)
        NSDebugLLog(@"gwcomp", @"Creating proxy for org.freedesktop.DBus...");
        
        GDBusProxy *bus_proxy = g_dbus_proxy_new_sync(
            connection,
            G_DBUS_PROXY_FLAGS_NONE,
            NULL,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            NULL,
            &error
        );
        
        if (bus_proxy) {
            NSDebugLLog(@"gwcomp", @"Successfully created proxy for org.freedesktop.DBus");
            
            // Test ListNames
            GVariant *names_result = g_dbus_proxy_call_sync(
                bus_proxy,
                "ListNames",
                NULL,
                G_DBUS_CALL_FLAGS_NONE,
                -1,
                NULL,
                &error
            );
            
            if (names_result) {
                NSDebugLLog(@"gwcomp", @"ListNames succeeded");
                g_variant_unref(names_result);
            } else {
                NSDebugLLog(@"gwcomp", @"ListNames failed: %s", error ? error->message : "Unknown error");
                if (error) g_error_free(error);
            }
            
            g_object_unref(bus_proxy);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to create proxy for org.freedesktop.DBus: %s", error ? error->message : "Unknown error");
            if (error) g_error_free(error);
        }
        
        // Now try a non-existent service
        NSDebugLLog(@"gwcomp", @"Creating proxy for org.xfce.Session.Manager...");
        
        GDBusProxy *session_proxy = g_dbus_proxy_new_sync(
            connection,
            G_DBUS_PROXY_FLAGS_NONE,
            NULL,
            "org.xfce.Session.Manager",
            "/org/xfce/Session/Manager",
            "org.xfce.Session.Manager",
            NULL,
            &error
        );
        
        if (session_proxy) {
            NSDebugLLog(@"gwcomp", @"Successfully created proxy for org.xfce.Session.Manager");
            g_object_unref(session_proxy);
        } else {
            NSDebugLLog(@"gwcomp", @"Failed to create proxy for org.xfce.Session.Manager: %s", error ? error->message : "Unknown error");
            if (error) {
                NSDebugLLog(@"gwcomp", @"Error domain: %s, code: %d", g_quark_to_string(error->domain), error->code);
                g_error_free(error);
            }
        }
        
        g_object_unref(connection);
    }
    
    return 0;
}
