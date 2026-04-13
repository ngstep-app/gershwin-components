/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MenuCacheManager.h"
#import "MenuUtils.h"

@implementation MenuCacheEntry

- (id)initWithMenu:(NSMenu *)menu 
       serviceName:(NSString *)serviceName 
        objectPath:(NSString *)objectPath
   applicationName:(NSString *)applicationName
{
    self = [super init];
    if (self) {
        self.menu = menu;
        self.cached = [NSDate timeIntervalSinceReferenceDate];
        self.lastAccessed = self.cached;
        self.accessCount = 1;
        self.serviceName = serviceName;
        self.objectPath = objectPath;
        self.applicationName = applicationName;
    }
    return self;
}

- (void)touch
{
    self.lastAccessed = [NSDate timeIntervalSinceReferenceDate];
    self.accessCount++;
}

- (NSTimeInterval)age
{
    return [NSDate timeIntervalSinceReferenceDate] - self.cached;
}

- (BOOL)isStale:(NSTimeInterval)maxAge
{
    NSTimeInterval effectiveMaxAge = maxAge;
    
    // Complex applications get 4x longer cache time
    if ([self isComplexApplication]) {
        effectiveMaxAge *= 4.0;
    }
    
    return [self age] > effectiveMaxAge;
}

- (BOOL)isComplexApplication
{
    return YES;
}

@end

@implementation MenuCacheManager

+ (MenuCacheManager *)sharedManager
{
    static MenuCacheManager *sharedInstance = nil;
    @synchronized(self) {
        if (!sharedInstance) {
            sharedInstance = [[MenuCacheManager alloc] init];
        }
    }
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        // Disable caching entirely for now to ensure instantaneous menu updates
        self.cache = [[NSMutableDictionary alloc] init];
        self.lruOrder = [[NSMutableArray alloc] init];
        _maxCacheSize = 0;    // caching disabled
        _maxCacheAge = 0.0;   // caching disabled
        
        // Initialize statistics
        self.cacheHits = 0;
        self.cacheMisses = 0;
        self.cacheEvictions = 0;
        
        // Disable periodic maintenance timer to avoid async cache work
        if (self.cleanupTimer) {
            [self.cleanupTimer invalidate];
            self.cleanupTimer = nil;
        }
        
        // Ensure cache is clear
        [self.cache removeAllObjects];
        [self.lruOrder removeAllObjects];
        
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: CACHING DISABLED (maxSize=0 maxAge=0)");
    }
    return self;
}

#pragma mark - Cache Operations

- (NSMenu *)getCachedMenuForWindow:(unsigned long)windowId
{
    return [self getCachedMenuForWindow:windowId validateServiceName:nil];
}

- (NSMenu *)getCachedMenuForWindow:(unsigned long)windowId 
         validateServiceName:(NSString *)expectedServiceName
{
    // Caching is disabled - always return nil so menus are loaded fresh on every change
    (void)expectedServiceName;
    (void)windowId;
    self.cacheMisses++;
    return nil;
}

- (void)cacheMenu:(NSMenu *)menu 
        forWindow:(unsigned long)windowId 
      serviceName:(NSString *)serviceName 
       objectPath:(NSString *)objectPath
  applicationName:(NSString *)applicationName
{
    // Caching disabled - do not store any menus
    (void)menu; (void)windowId; (void)serviceName; (void)objectPath; (void)applicationName;
    return;
}

- (void)invalidateCacheForWindow:(unsigned long)windowId
{
    NSNumber *windowKey = [NSNumber numberWithUnsignedLong:windowId];
    MenuCacheEntry *entry = [self.cache objectForKey:windowKey];
    
    if (entry) {
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: Invalidating cache for window %lu (%@)", 
              windowId, [entry applicationName] ?: @"Unknown App");
        
        [self.cache removeObjectForKey:windowKey];
        [self.lruOrder removeObject:windowKey];
    }
}

- (void)invalidateCacheForApplication:(NSString *)applicationName
{
    if (!applicationName) {
        return;
    }
    
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Invalidating cache for application: %@", applicationName);
    
    NSMutableArray *windowsToRemove = [NSMutableArray array];
    
    for (NSNumber *windowKey in [self.cache allKeys]) {
        MenuCacheEntry *entry = [self.cache objectForKey:windowKey];
        if ([[entry applicationName] isEqualToString:applicationName]) {
            [windowsToRemove addObject:windowKey];
        }
    }
    
    for (NSNumber *windowKey in windowsToRemove) {
        unsigned long windowId = [windowKey unsignedLongValue];
        [self invalidateCacheForWindow:windowId];
    }
    
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Invalidated %lu cached menus for application %@", 
          (unsigned long)[windowsToRemove count], applicationName);
}

- (void)clearCache
{
    NSUInteger count = [self.cache count];
    [self.cache removeAllObjects];
    [self.lruOrder removeAllObjects];
    
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Cleared entire cache (%lu entries)", (unsigned long)count);
}

#pragma mark - Cache Management

- (void)setMaxCacheSize:(NSUInteger)maxSize
{
    _maxCacheSize = maxSize;
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Set max cache size to %lu", (unsigned long)maxSize);
    
    // Evict entries if we're now over the limit
    while ([self.cache count] > _maxCacheSize && [self.lruOrder count] > 0) {
        [self evictLRUEntry];
    }
}

- (void)setMaxCacheAge:(NSTimeInterval)maxAge
{
    _maxCacheAge = maxAge;
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Set max cache age to %.1fs", maxAge);
}

- (void)performMaintenance
{
    NSMutableArray *staleWindows = [NSMutableArray array];
    
    // Find stale entries
    for (NSNumber *windowKey in [self.cache allKeys]) {
        MenuCacheEntry *entry = [self.cache objectForKey:windowKey];
        if ([entry isStale:self.maxCacheAge]) {
            [staleWindows addObject:windowKey];
        }
    }
    
    // Remove stale entries
    for (NSNumber *windowKey in staleWindows) {
        unsigned long windowId = [windowKey unsignedLongValue];
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: Removing stale cache entry for window %lu", windowId);
        [self invalidateCacheForWindow:windowId];
    }
    
    if ([staleWindows count] > 0) {
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: Maintenance removed %lu stale entries", 
              (unsigned long)[staleWindows count]);
    }
    
    // Log statistics periodically (every 10 minutes)
    static NSUInteger maintenanceCount = 0;
    maintenanceCount++;
    if (maintenanceCount % 10 == 0) {
        [self logCacheStatistics];
    }
}

- (void)evictLRUEntry
{
    if ([self.lruOrder count] == 0) {
        return;
    }
    
    NSNumber *lruWindowKey = [self.lruOrder lastObject];
    unsigned long windowId = [lruWindowKey unsignedLongValue];
    
    MenuCacheEntry *entry = [self.cache objectForKey:lruWindowKey];
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Evicting LRU entry for window %lu (%@)", 
          windowId, [entry applicationName] ?: @"Unknown App");
    
    [self.cache removeObjectForKey:lruWindowKey];
    [self.lruOrder removeLastObject];
    self.cacheEvictions++;
}

- (void)moveToFront:(NSNumber *)windowKey
{
    [self.lruOrder removeObject:windowKey];
    [self.lruOrder insertObject:windowKey atIndex:0];
}

#pragma mark - Statistics

- (NSDictionary *)getCacheStatistics
{
    NSUInteger totalRequests = self.cacheHits + self.cacheMisses;
    double hitRatio = (totalRequests > 0) ? ((double)self.cacheHits / totalRequests) * 100.0 : 0.0;
    
    return @{
        @"cacheSize": @([self.cache count]),
        @"maxCacheSize": @(self.maxCacheSize),
        @"maxCacheAge": @(self.maxCacheAge),
        @"cacheHits": @(self.cacheHits),
        @"cacheMisses": @(self.cacheMisses),
        @"cacheEvictions": @(self.cacheEvictions),
        @"hitRatio": @(hitRatio),
        @"totalRequests": @(totalRequests)
    };
}

- (void)logCacheStatistics
{
    NSDictionary *stats = [self getCacheStatistics];
    
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: === CACHE STATISTICS ===");
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Cache size: %@ / %@", stats[@"cacheSize"], stats[@"maxCacheSize"]);
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Cache hits: %@, misses: %@, evictions: %@", 
          stats[@"cacheHits"], stats[@"cacheMisses"], stats[@"cacheEvictions"]);
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Hit ratio: %.1f%% (%@ total requests)", 
          [stats[@"hitRatio"] doubleValue], stats[@"totalRequests"]);
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Max cache age: %.1fs", [stats[@"maxCacheAge"] doubleValue]);
    
    // Log current cache contents
    if ([self.cache count] > 0) {
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: Cached windows:");
        for (NSNumber *windowKey in self.lruOrder) {
            MenuCacheEntry *entry = [self.cache objectForKey:windowKey];
            NSDebugLLog(@"gwcomp", @"MenuCacheManager:   Window %@ (%@): %lu items, age %.1fs, accessed %lu times",
                  windowKey, [entry applicationName] ?: @"Unknown",
                  (unsigned long)[[entry menu] numberOfItems],
                  [entry age], (unsigned long)[entry accessCount]);
        }
    }
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: ========================");
}

#pragma mark - Window Lifecycle

- (void)windowBecameActive:(unsigned long)windowId
{
    NSNumber *windowKey = [NSNumber numberWithUnsignedLong:windowId];
    MenuCacheEntry *entry = [self.cache objectForKey:windowKey];
    
    if (entry) {
        [entry touch];
        [self moveToFront:windowKey];
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: Window %lu became active, moved to cache front", windowId);
    }
}

- (void)windowBecameInactive:(unsigned long)windowId
{
    // Currently no special handling for inactive windows
    // Could implement priority reduction here if needed
}

- (void)applicationSwitched:(NSString *)fromApp toApp:(NSString *)toApp
{
    NSDebugLLog(@"gwcomp", @"MenuCacheManager: Application switched from '%@' to '%@'", 
          fromApp ?: @"Unknown", toApp ?: @"Unknown");
    
    // For complex applications like GIMP, increase cache persistence
    if ([self isComplexApplication:toApp]) {
        NSDebugLLog(@"gwcomp", @"MenuCacheManager: Detected complex application '%@', using extended cache persistence", toApp);
        // Complex apps get longer cache time
        // This is handled per-entry in the cache logic
    }
    
    // Could implement application-level cache prioritization here
    // For now, just log the switch for debugging
}

- (BOOL)isComplexApplication:(NSString *)applicationName
{
    if (!applicationName) {
        return NO;
    }
    
    // List of applications known to have complex menus that benefit from aggressive caching
    NSArray *complexApps = @[
        @"gimp",
        @"GIMP",
        @"gimp-2.10",
        @"inkscape",
        @"Inkscape", 
        @"blender",
        @"Blender",
        @"libreoffice",
        @"LibreOffice",
        @"firefox",
        @"Firefox",
        @"thunderbird",
        @"Thunderbird",
        @"eclipse",
        @"Eclipse",
        @"netbeans",
        @"NetBeans",
        @"code",
        @"Code",
        @"visual-studio-code",
        @"qtcreator",
        @"Qt Creator"
    ];
    
    NSString *lowerAppName = [applicationName lowercaseString];
    for (NSString *complexApp in complexApps) {
        if ([lowerAppName containsString:[complexApp lowercaseString]]) {
            return YES;
        }
    }
    
    return NO;
}

@end
