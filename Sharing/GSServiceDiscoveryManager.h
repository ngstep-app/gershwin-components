/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Service Discovery Manager - Cross-platform mDNS service announcement
 * 
 * This manager provides a unified interface for announcing services via mDNS/DNS-SD.
 * It supports both Apple's dns-sd (mDNSResponder) and Avahi, with automatic detection
 * of available backends.
 *
 * Architecture:
 * - GSServiceDiscoveryManager: Main interface (Objective-C)
 * - Backend abstraction layer: Auto-detects dns-sd or Avahi
 * - State persistence: Tracks announced services for reboot resilience
 * - Error handling: Robust error handling with automatic retry
 */

#import <Foundation/Foundation.h>

/**
 * Service types that can be announced
 */
typedef enum {
    GSServiceTypeSSH,
    GSServiceTypeVNC,
    GSServiceTypeSFTP,
    GSServiceTypeAFP,
    GSServiceTypeSMB,
    GSServiceTypeWebDAV
} GSServiceType;

/**
 * Backend type for service discovery
 */
typedef enum {
    GSServiceBackendNone,       // No backend available
    GSServiceBackendDNSSD,      // Apple's dns-sd (mDNSResponder)
    GSServiceBackendAvahi,      // Avahi
    GSServiceBackendNSNetService // GNUstep NSNetService (wraps dns-sd or Avahi)
} GSServiceBackend;

/**
 * GSServiceDiscoveryManager
 *
 * Thread-safe singleton manager for mDNS service announcement.
 * Automatically detects available mDNS backend and manages service registration.
 */
@interface GSServiceDiscoveryManager : NSObject
{
    GSServiceBackend backend;
    NSMutableDictionary *registeredServices; // Maps service type -> NSNetService or state
    NSRecursiveLock *lock;
    BOOL isAvailable;
    NSString *computerName;
}

/**
 * Returns the shared singleton instance
 */
+ (instancetype)sharedManager;

/**
 * Returns YES if mDNS service discovery is available on this system
 */
- (BOOL)isAvailable;

/**
 * Returns the backend type being used
 */
- (GSServiceBackend)backend;

/**
 * Returns a human-readable name for the backend
 */
- (NSString *)backendName;

/**
 * Sets the computer name to use for service announcements.
 * If not set, uses the system hostname.
 */
- (void)setComputerName:(NSString *)name;

/**
 * Announces a service via mDNS.
 * 
 * @param serviceType The type of service to announce
 * @param port The port number the service is listening on
 * @param txtRecord Optional TXT record dictionary (can be nil)
 * @return YES if the service was successfully announced, NO otherwise
 */
- (BOOL)announceService:(GSServiceType)serviceType 
                   port:(NSInteger)port
              txtRecord:(NSDictionary *)txtRecord;

/**
 * Stops announcing a service.
 *
 * @param serviceType The type of service to stop announcing
 */
- (void)unannounceService:(GSServiceType)serviceType;

/**
 * Checks if a service is currently being announced
 *
 * @param serviceType The type of service to check
 * @return YES if the service is currently announced, NO otherwise
 */
- (BOOL)isServiceAnnounced:(GSServiceType)serviceType;

/**
 * Returns the standard service type string for a given service type
 * (e.g., "_ssh._tcp." for SSH)
 */
- (NSString *)serviceTypeString:(GSServiceType)serviceType;

/**
 * Returns the default port for a given service type
 */
- (NSInteger)defaultPortForService:(GSServiceType)serviceType;

/**
 * Saves the current announced services state to disk.
 * This allows services to be re-announced after a reboot.
 */
- (void)saveState;

/**
 * Restores announced services from saved state.
 * Called automatically on initialization.
 */
- (void)restoreState;

/**
 * Returns an array of currently announced service types
 */
- (NSArray *)announcedServices;

@end
