#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface MenuCacheEntry : NSObject

@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, assign) NSTimeInterval lastAccessed;
@property (nonatomic, assign) NSTimeInterval cached;
@property (nonatomic, assign) NSUInteger accessCount;
@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *objectPath;
@property (nonatomic, strong) NSString *applicationName;

- (id)initWithMenu:(NSMenu *)menu 
       serviceName:(NSString *)serviceName 
        objectPath:(NSString *)objectPath
   applicationName:(NSString *)applicationName;
- (void)touch;
- (NSTimeInterval)age;
- (BOOL)isStale:(NSTimeInterval)maxAge;

@end

@interface MenuCacheManager : NSObject

@property (nonatomic, strong) NSMutableDictionary *cache;               // windowId -> MenuCacheEntry
@property (nonatomic, strong) NSMutableArray *lruOrder;                 // Array of window IDs in LRU order
@property (nonatomic, assign) NSUInteger maxCacheSize;
@property (nonatomic, assign) NSTimeInterval maxCacheAge;
@property (nonatomic, strong) NSTimer *cleanupTimer;

// Statistics
@property (nonatomic, assign) NSUInteger cacheHits;
@property (nonatomic, assign) NSUInteger cacheMisses;
@property (nonatomic, assign) NSUInteger cacheEvictions;

+ (MenuCacheManager *)sharedManager;

// Cache operations
- (NSMenu *)getCachedMenuForWindow:(unsigned long)windowId;
- (void)cacheMenu:(NSMenu *)menu 
        forWindow:(unsigned long)windowId 
      serviceName:(NSString *)serviceName 
       objectPath:(NSString *)objectPath
  applicationName:(NSString *)applicationName;
- (void)invalidateCacheForWindow:(unsigned long)windowId;
- (void)invalidateCacheForApplication:(NSString *)applicationName;
- (void)clearCache;

// Cache management
- (void)setMaxCacheSize:(NSUInteger)maxSize;
- (void)setMaxCacheAge:(NSTimeInterval)maxAge;
- (void)performMaintenance;

// Statistics
- (NSDictionary *)getCacheStatistics;
- (void)logCacheStatistics;

// Window lifecycle
- (void)windowBecameActive:(unsigned long)windowId;
- (void)windowBecameInactive:(unsigned long)windowId;
- (void)applicationSwitched:(NSString *)fromApp toApp:(NSString *)toApp;

// Application classification
- (BOOL)isComplexApplication:(NSString *)applicationName;

@end
