/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * BSD Network Backend
 *
 * Uses native FreeBSD tools (ifconfig, wpa_cli, sysrc, dhclient)
 * to manage network interfaces and connections. This backend is
 * selected automatically when running on FreeBSD.
 *
 * The backend uses command-line tools rather than direct system calls
 * for better portability and to match the FreeBSD administration model.
 */

#import "NetworkBackend.h"

@interface BSDBackend : NSObject <NetworkBackend>
{
    id<NetworkBackendDelegate> delegate;

    /* Tool availability */
    BOOL backendAvailable;
    NSString *ifconfigPath;
    NSString *sysrcPath;
    NSString *wpaCliPath;
    NSString *dhclientPath;
    NSString *sysctlPath;
    NSString *sudoPath;

    /* network-helper for privileged operations */
    NSString *helperPath;

    /* Cached state */
    NSMutableArray *cachedInterfaces;
    NSMutableArray *cachedConnections;
    NSMutableArray *cachedWLANs;
    BOOL wifiEnabled;

    /* Wireless device mapping: physical device -> wlan device */
    NSMutableDictionary *wlanDeviceMap;   /* e.g. iwm0 -> wlan0 */
    NSString *primaryWLANDevice;          /* e.g. wlan0 */
}

@property (assign) id<NetworkBackendDelegate> delegate;

/* Tool discovery */
- (NSString *)findExecutable:(NSString *)name;
- (NSString *)findHelperPath;
- (BOOL)discoverTools;

/* Interface helpers */
- (NSArray *)listInterfaceNames;
- (NetworkInterface *)parseInterfaceDetails:(NSString *)ifaceName;
- (NetworkInterfaceType)classifyInterface:(NSString *)ifaceName;
- (NetworkConnectionState)parseInterfaceState:(NSString *)output;
- (IPConfiguration *)parseIPv4Config:(NSString *)output;
- (NSString *)parseHardwareAddress:(NSString *)output;

/* Wireless helpers */
- (NSString *)discoverWLANDevice;
- (void)ensureWLANDevice;
- (NSArray *)parseIfconfigScan:(NSString *)output;
- (NSArray *)parseWpaCliScanResults:(NSString *)output;
- (WLANSecurityType)parseSecurityCaps:(NSString *)caps;

/* NIC setup (rc.conf configuration, similar to GhostBSD setup-nic) */
- (BOOL)setupNIC:(NSString *)deviceName;

/* Command execution */
- (NSString *)runCommand:(NSString *)path arguments:(NSArray *)args;
- (int)runCommandWithStatus:(NSString *)path arguments:(NSArray *)args
                     output:(NSString **)output;
- (BOOL)runPrivilegedHelper:(NSArray *)arguments error:(NSError **)error;
- (void)waitForTaskCompletion:(NSDictionary *)taskInfo;

/* Error handling */
- (void)reportErrorWithMessage:(NSString *)message;

@end
