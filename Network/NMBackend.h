/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NetworkManager Backend
 *
 * Uses dlopen() to dynamically load libnm at runtime, so the preference pane
 * can still load on systems without NetworkManager installed.
 */

#import "NetworkBackend.h"

@interface NMBackend : NSObject <NetworkBackend>
{
    id<NetworkBackendDelegate> delegate;
    
    // Dynamic library handle
    void *nmLibHandle;
    BOOL nmAvailable;
    
    // Cached data
    NSMutableArray *cachedInterfaces;
    NSMutableArray *cachedConnections;
    NSMutableArray *cachedWLANs;
    BOOL wifiEnabled;
    
    // NM Client object (opaque pointer to NMClient*)
    void *nmClient;
    
    // Function pointers
    void *(*nm_client_new)(void *cancellable, void **error);
    void (*nm_client_get_devices)(void *client);
    int (*nm_client_get_state)(void *client);
    BOOL (*nm_client_wireless_get_enabled)(void *client);
    void (*nm_client_wireless_set_enabled)(void *client, BOOL enabled);
    const char* (*nm_client_get_version)(void *client);
    void* (*nm_client_get_primary_connection)(void *client);
    void* (*nm_client_get_connections)(void *client);
    void* (*nm_client_activate_connection_async)(void *client, void *connection, 
                                                  void *device, const char *path,
                                                  void *cancellable, void *callback, 
                                                  void *user_data);
    void* (*nm_client_add_and_activate_connection_async)(void *client, void *connection,
                                                          void *device, const char *path,
                                                          void *cancellable, void *callback,
                                                          void *user_data);
    void* (*nm_client_deactivate_connection_async)(void *client, void *active,
                                                    void *cancellable, void *callback,
                                                    void *user_data);
    
    // Device functions
    const char* (*nm_device_get_iface)(void *device);
    int (*nm_device_get_device_type)(void *device);
    int (*nm_device_get_state)(void *device);
    const char* (*nm_device_get_hw_address)(void *device);
    void* (*nm_device_get_ip4_config)(void *device);
    void* (*nm_device_get_active_connection)(void *device);
    
    // WiFi device functions
    void* (*nm_device_wifi_get_access_points)(void *device);
    void* (*nm_device_wifi_get_active_access_point)(void *device);
    BOOL (*nm_device_wifi_request_scan_async)(void *device, void *cancellable, 
                                               void *callback, void *user_data);
    
    // Access point functions
    const char* (*nm_access_point_get_ssid_as_str)(void *ap);
    const char* (*nm_access_point_get_bssid)(void *ap);
    int (*nm_access_point_get_strength)(void *ap);
    int (*nm_access_point_get_flags)(void *ap);
    int (*nm_access_point_get_wpa_flags)(void *ap);
    int (*nm_access_point_get_rsn_flags)(void *ap);
    int (*nm_access_point_get_frequency)(void *ap);
    
    // Connection functions
    const char* (*nm_connection_get_uuid)(void *connection);
    const char* (*nm_connection_get_id)(void *connection);
    void* (*nm_connection_get_setting_connection)(void *connection);
    void* (*nm_connection_get_setting_wireless)(void *connection);
    void* (*nm_connection_get_setting_ip4_config)(void *connection);
    BOOL (*nm_remote_connection_delete)(void *connection, void *cancellable, void **error);
    BOOL (*nm_remote_connection_commit_changes)(void *connection, BOOL save, 
                                                 void *cancellable, void **error);
    
    // Settings functions  
    const char* (*nm_setting_connection_get_connection_type)(void *setting);
    BOOL (*nm_setting_connection_get_autoconnect)(void *setting);
    const char* (*nm_setting_connection_get_interface_name)(void *setting);
    void* (*nm_setting_wireless_get_ssid)(void *setting);
    
    // IP config functions
    void* (*nm_ip_config_get_addresses)(void *config);
    void* (*nm_ip_config_get_nameservers)(void *config);
    const char* (*nm_ip_config_get_gateway)(void *config);
    
    // IP address functions
    const char* (*nm_ip_address_get_address)(void *addr);
    int (*nm_ip_address_get_prefix)(void *addr);
    
    // Simple connection creation
    void* (*nm_simple_connection_new)(void);
    void (*nm_connection_add_setting)(void *connection, void *setting);
    
    // GLib functions
    int (*g_slist_length)(void *list);
    void* (*g_slist_nth_data)(void *list, unsigned int n);
    void* (*g_ptr_array_index)(void *array, unsigned int index);
    unsigned int (*g_ptr_array_get_length)(void *array);
    const char* (*g_bytes_get_data)(void *bytes, size_t *size);
    
    // nmcli path for fallback operations
    NSString *nmcliPath;
    
    // network-helper path for privileged operations
    NSString *helperPath;

    // sudo path for privileged operations
    NSString *sudoPath;
}

@property (assign) id<NetworkBackendDelegate> delegate;

// Loading and initialization
- (BOOL)loadNetworkManagerLibrary;
- (void)unloadNetworkManagerLibrary;
- (BOOL)initializeNMClient;

// Helper methods
- (NetworkInterfaceType)interfaceTypeFromNMDeviceType:(int)nmType;
- (NetworkConnectionState)stateFromNMDeviceState:(int)nmState;
- (WLANSecurityType)securityFromAccessPointFlags:(int)flags wpaFlags:(int)wpa rsnFlags:(int)rsn;
- (NSString *)findNmcliPath;
- (NSString *)findHelperPath;
- (void)reportErrorWithMessage:(NSString *)message;

// nmcli fallback methods
- (NSArray *)getInterfacesViaNmcli;
- (NSArray *)getConnectionsViaNmcli;
- (NSMutableArray *)buildWLANsList;
- (void)updateCachedWLANs:(NSArray *)networks;
- (BOOL)connectToWiFiViaNmcli:(NSString *)ssid password:(NSString *)password security:(WLANSecurityType)security;
- (BOOL)connectToSecuredWLAN:(NSString *)ssid password:(NSString *)password security:(WLANSecurityType)security;
- (void)deleteConnectionBySSID:(NSString *)ssid;
- (BOOL)activateConnectionViaNmcli:(NSString *)uuid;
- (BOOL)deactivateConnectionViaNmcli:(NSString *)uuid;

// Privileged helper methods (uses sudo -A -E)
- (BOOL)runPrivilegedHelper:(NSArray *)arguments error:(NSError **)error;

@end
