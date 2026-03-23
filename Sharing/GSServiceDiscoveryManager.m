/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Service Discovery Manager Implementation - Simplified to use NSNetService only
 */

#import "GSServiceDiscoveryManager.h"
#import <sys/utsname.h>

// State file location
#define STATE_FILE_PATH @"/var/lib/gershwin/sharing-services-state.plist"
#define STATE_FILE_DIR @"/var/lib/gershwin"

@interface GSServiceDiscoveryManager (Private)
- (NSString *)getHostname;
- (NSData *)txtRecordDataFromDictionary:(NSDictionary *)dict;
@end

@implementation GSServiceDiscoveryManager

static GSServiceDiscoveryManager *sharedInstance = nil;

+ (instancetype)sharedManager
{
    @synchronized([GSServiceDiscoveryManager class]) {
        if (sharedInstance == nil) {
            sharedInstance = [[GSServiceDiscoveryManager alloc] init];
        }
    }
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        NSDebugLog(@"GSServiceDiscoveryManager: init starting");
        
        lock = [[NSRecursiveLock alloc] init];
        registeredServices = [[NSMutableDictionary alloc] init];
        computerName = nil;
        
        NSDebugLog(@"GSServiceDiscoveryManager: Checking for NSNetService");
        
        // Check if NSNetService is available (it handles dns-sd/Avahi internally)
        Class netServiceClass = NSClassFromString(@"NSNetService");
        if (netServiceClass != nil) {
            backend = GSServiceBackendNSNetService;
            isAvailable = YES;
            NSDebugLog(@"GSServiceDiscoveryManager: NSNetService available");
        } else {
            backend = GSServiceBackendNone;
            isAvailable = NO;
            NSDebugLog(@"GSServiceDiscoveryManager: NSNetService NOT available");
        }
        
        NSDebugLog(@"GSServiceDiscoveryManager: init complete (state restoration deferred)");
        // NOTE: State restoration is now called explicitly when needed, not automatically
    }
    return self;
}

- (void)dealloc
{
    [lock lock];
    
    // Stop all announced services
    NSArray *serviceKeys = [registeredServices allKeys];
    for (NSNumber *serviceTypeNum in serviceKeys) {
        GSServiceType serviceType = [serviceTypeNum intValue];
        [self unannounceService:serviceType];
    }
    
    [registeredServices release];
    [computerName release];
    [lock unlock];
    [lock release];
    
    [super dealloc];
}

#pragma mark - Public API

- (BOOL)isAvailable
{
    return isAvailable;
}

- (GSServiceBackend)backend
{
    return backend;
}

- (NSString *)backendName
{
    return isAvailable ? @"NSNetService" : @"None";
}

- (void)setComputerName:(NSString *)name
{
    [lock lock];
    ASSIGN(computerName, name);
    
    // Update all announced services with new name
    NSArray *serviceKeys = [[registeredServices allKeys] copy];
    for (NSNumber *serviceTypeNum in serviceKeys) {
        GSServiceType serviceType = [serviceTypeNum intValue];
        id service = [registeredServices objectForKey:serviceTypeNum];
        
        // Re-announce with new name if using NSNetService
        if ([service isKindOfClass:[NSNetService class]]) {
            NSNetService *netService = (NSNetService *)service;
            NSInteger port = [netService port];
            NSDictionary *txtDict = nil; // TODO: Extract from current service if needed
            
            // Stop and re-announce with new name
            [self unannounceService:serviceType];
            [self announceService:serviceType port:port txtRecord:txtDict];
        }
    }
    [serviceKeys release];
    [lock unlock];
}

- (NSString *)serviceTypeString:(GSServiceType)serviceType
{
    switch (serviceType) {
        case GSServiceTypeSSH:
            return @"_ssh._tcp.";
        case GSServiceTypeVNC:
            return @"_rfb._tcp.";
        case GSServiceTypeSFTP:
            return @"_sftp-ssh._tcp.";
        case GSServiceTypeAFP:
            return @"_afpovertcp._tcp.";
        case GSServiceTypeSMB:
            return @"_smb._tcp.";
        case GSServiceTypeWebDAV:
            return @"_webdav._tcp.";
        default:
            return nil;
    }
}

- (NSInteger)defaultPortForService:(GSServiceType)serviceType
{
    switch (serviceType) {
        case GSServiceTypeSSH:
        case GSServiceTypeSFTP:
            return 22;
        case GSServiceTypeVNC:
            return 5900;
        case GSServiceTypeAFP:
            return 548;
        case GSServiceTypeSMB:
            return 445;
        case GSServiceTypeWebDAV:
            return 8080;
        default:
            return 0;
    }
}

- (NSString *)getHostname
{
    if (computerName) {
        return computerName;
    }
    
    struct utsname buf;
    if (uname(&buf) == 0) {
        return [NSString stringWithUTF8String:buf.nodename];
    }
    
    return @"localhost";
}

- (NSData *)txtRecordDataFromDictionary:(NSDictionary *)dict
{
    if (!dict || [dict count] == 0) {
        return nil;
    }
    
    // Use NSNetService's built-in method if available
    Class netServiceClass = NSClassFromString(@"NSNetService");
    if ([netServiceClass respondsToSelector:@selector(dataFromTXTRecordDictionary:)]) {
        return [netServiceClass performSelector:@selector(dataFromTXTRecordDictionary:) 
                                     withObject:dict];
    }
    
    return nil;
}

#pragma mark - Service Announcement

- (BOOL)announceService:(GSServiceType)serviceType 
                   port:(NSInteger)port
              txtRecord:(NSDictionary *)txtRecord
{
    if (!isAvailable) {
        NSDebugLog(@"GSServiceDiscoveryManager: Cannot announce service - NSNetService not available");
        return NO;
    }
    
    [lock lock];
    
    NSNumber *serviceKey = [NSNumber numberWithInt:serviceType];
    
    // Check if already announced
    if ([registeredServices objectForKey:serviceKey] != nil) {
        NSDebugLog(@"GSServiceDiscoveryManager: Service type %d already announced, re-announcing", serviceType);
        [self unannounceService:serviceType];
    }
    
    NSString *serviceTypeStr = [self serviceTypeString:serviceType];
    if (!serviceTypeStr) {
        NSDebugLog(@"GSServiceDiscoveryManager: Invalid service type: %d", serviceType);
        [lock unlock];
        return NO;
    }
    
    NSString *hostname = [self getHostname];
    NSDebugLog(@"GSServiceDiscoveryManager: Announcing %@ on port %ld as %@", 
          serviceTypeStr, (long)port, hostname);
    
    BOOL success = NO;
    
    // Use NSNetService API (it handles dns-sd/Avahi internally)
    Class netServiceClass = NSClassFromString(@"NSNetService");
    if (netServiceClass) {
        NSNetService *service = [[netServiceClass alloc] initWithDomain:@""
                                                                   type:serviceTypeStr
                                                                   name:hostname
                                                                   port:(int)port];
        if (service) {
            // Set TXT record if provided
            if (txtRecord) {
                NSData *txtData = [self txtRecordDataFromDictionary:txtRecord];
                if (txtData && [service respondsToSelector:@selector(setTXTRecordData:)]) {
                    [service performSelector:@selector(setTXTRecordData:) withObject:txtData];
                }
            }
            
            // Publish the service
            [service publish];
            [registeredServices setObject:service forKey:serviceKey];
            [service release];
            success = YES;
            
            NSDebugLog(@"GSServiceDiscoveryManager: Successfully announced service via NSNetService");
        }
    }
    
    if (success) {
        // Save state for reboot persistence
        [self saveState];
    }
    
    [lock unlock];
    return success;
}

- (void)unannounceService:(GSServiceType)serviceType
{
    [lock lock];
    
    NSNumber *serviceKey = [NSNumber numberWithInt:serviceType];
    id service = [registeredServices objectForKey:serviceKey];
    
    if (!service) {
        NSDebugLog(@"GSServiceDiscoveryManager: Service type %d is not announced", serviceType);
        [lock unlock];
        return;
    }
    
    NSDebugLog(@"GSServiceDiscoveryManager: Unannouncing service type %d", serviceType);
    
    if ([service isKindOfClass:[NSNetService class]]) {
        // Stop NSNetService (it handles cleanup internally)
        NSNetService *netService = (NSNetService *)service;
        [netService stop];
    }
    
    [registeredServices removeObjectForKey:serviceKey];
    
    // Save state
    [self saveState];
    
    [lock unlock];
}

- (BOOL)isServiceAnnounced:(GSServiceType)serviceType
{
    [lock lock];
    NSNumber *serviceKey = [NSNumber numberWithInt:serviceType];
    BOOL announced = ([registeredServices objectForKey:serviceKey] != nil);
    [lock unlock];
    return announced;
}

- (NSArray *)announcedServices
{
    [lock lock];
    NSArray *keys = [registeredServices allKeys];
    [lock unlock];
    return keys;
}

#pragma mark - State Persistence

- (void)saveState
{
    [lock lock];
    
    // Create state directory if it doesn't exist
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *stateDir = STATE_FILE_DIR;
    
    BOOL isDir;
    if (![fm fileExistsAtPath:stateDir isDirectory:&isDir]) {
        NSError *error = nil;
        if (![fm createDirectoryAtPath:stateDir 
           withIntermediateDirectories:YES 
                            attributes:nil 
                                 error:&error]) {
            NSDebugLog(@"GSServiceDiscoveryManager: Failed to create state directory: %@", error);
            [lock unlock];
            return;
        }
    }
    
    // Build state dictionary
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    NSEnumerator *keyEnum = [registeredServices keyEnumerator];
    NSNumber *serviceKey;
    
    while ((serviceKey = [keyEnum nextObject])) {
        id service = [registeredServices objectForKey:serviceKey];
        NSMutableDictionary *serviceInfo = [NSMutableDictionary dictionary];
        
        if ([service isKindOfClass:[NSNetService class]]) {
            NSNetService *netService = (NSNetService *)service;
            [serviceInfo setObject:[NSNumber numberWithInt:[netService port]] forKey:@"port"];
            [serviceInfo setObject:[self serviceTypeString:[serviceKey intValue]] forKey:@"type"];
        }
        
        [state setObject:serviceInfo forKey:[serviceKey stringValue]];
    }
    
    // Write to disk
    BOOL success = [state writeToFile:STATE_FILE_PATH atomically:YES];
    if (success) {
        NSDebugLog(@"GSServiceDiscoveryManager: Saved state to %@", STATE_FILE_PATH);
    } else {
        NSDebugLog(@"GSServiceDiscoveryManager: Failed to save state to %@", STATE_FILE_PATH);
    }
    
    [lock unlock];
}

- (void)restoreState
{
    if (!isAvailable) {
        NSDebugLog(@"GSServiceDiscoveryManager: Skipping state restoration - NSNetService not available");
        return;
    }
    
    [lock lock];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:STATE_FILE_PATH]) {
        NSDebugLog(@"GSServiceDiscoveryManager: No saved state found");
        [lock unlock];
        return;
    }
    
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:STATE_FILE_PATH];
    if (!state || [state count] == 0) {
        NSDebugLog(@"GSServiceDiscoveryManager: No services to restore");
        [lock unlock];
        return;
    }
    
    NSDebugLog(@"GSServiceDiscoveryManager: Restoring %lu services from state file", (unsigned long)[state count]);
    
    NSEnumerator *keyEnum = [state keyEnumerator];
    NSString *serviceKeyStr;
    
    while ((serviceKeyStr = [keyEnum nextObject])) {
        NSDictionary *serviceInfo = [state objectForKey:serviceKeyStr];
        GSServiceType serviceType = [serviceKeyStr intValue];
        NSNumber *portNum = [serviceInfo objectForKey:@"port"];
        
        if (portNum) {
            NSInteger port = [portNum intValue];
            NSDebugLog(@"GSServiceDiscoveryManager: Restoring service type %d on port %ld", 
                  serviceType, (long)port);
            
            // Re-announce the service
            [self announceService:serviceType port:port txtRecord:nil];
        }
    }
    
    NSDebugLog(@"GSServiceDiscoveryManager: State restoration complete");
    [lock unlock];
}

@end
