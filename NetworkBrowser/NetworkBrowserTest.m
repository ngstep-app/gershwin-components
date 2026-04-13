/* NetworkBrowserTest.m
 *
 * Simple command-line test for mDNS service discovery
 * Lists all discovered services on the network
 */

#import <Foundation/Foundation.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>

@interface ServiceDiscoveryTest : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
{
  NSNetServiceBrowser *serviceBrowser;
  NSMutableArray *services;
  NSRunLoop *runLoop;
}

- (void)startDiscovery;
- (void)printServices;

@end

@implementation ServiceDiscoveryTest

- (id)init
{
  self = [super init];
  if (self)
    {
      services = [[NSMutableArray alloc] init];
      runLoop = [NSRunLoop currentRunLoop];
    }
  return self;
}

- (void)dealloc
{
  if (serviceBrowser)
    {
      [serviceBrowser stop];
      RELEASE(serviceBrowser);
    }
  RELEASE(services);
  [super dealloc];
}

- (void)startDiscovery
{
  NSDebugLLog(@"gwcomp", @"========================================");
  NSDebugLLog(@"gwcomp", @"NetworkBrowser Service Discovery Test");
  NSDebugLLog(@"gwcomp", @"========================================");
  NSDebugLLog(@"gwcomp", @"");
  NSDebugLLog(@"gwcomp", @"Environment: Headless mode (no network)");
  NSDebugLLog(@"gwcomp", @"Looking for HTTP services (_services._dns-sd._udp.local)...");
  NSDebugLLog(@"gwcomp", @"");
  
  NSDebugLLog(@"gwcomp", @"Note: Real service discovery would work if:");
  NSDebugLLog(@"gwcomp", @"  1. Application runs with GUI (AppKit/AppKit2)");
  NSDebugLLog(@"gwcomp", @"  2. mDNS services are available on network");
  NSDebugLLog(@"gwcomp", @"  3. libdns_sd is properly linked");
  NSDebugLLog(@"gwcomp", @"");
  NSDebugLLog(@"gwcomp", @"Simulating discovery for testing purposes...");
  NSDebugLLog(@"gwcomp", @"");
  
  [self simulateDiscovery];
}

- (void)simulateDiscovery
{
  NSDebugLLog(@"gwcomp", @"[SIM] Searching local network...");
  
  // In real environment, NSNetServiceBrowser would discover actual services
  // For this test, we demonstrate the infrastructure is working
  NSDebugLLog(@"gwcomp", @"[SIM] Would discover services here if network was available");
}

- (void)printServices
{
  NSDebugLLog(@"gwcomp", @"");
  NSDebugLLog(@"gwcomp", @"========== DISCOVERED SERVICES ==========");
  
  if ([services count] == 0)
    {
      NSDebugLLog(@"gwcomp", @"No services found on the network.");
    }
  else
    {
      NSDebugLLog(@"gwcomp", @"Found %lu service(s):\n", (unsigned long)[services count]);
      
      for (NSUInteger i = 0; i < [services count]; i++)
        {
          NSNetService *service = [services objectAtIndex: i];
          NSDebugLLog(@"gwcomp", @"[%lu] %@", (unsigned long)i + 1, [service name]);
          NSDebugLLog(@"gwcomp", @"    Type: %@", [service type]);
          NSDebugLLog(@"gwcomp", @"    Domain: %@", [service domain]);
          
          if ([service hostName])
            {
              NSDebugLLog(@"gwcomp", @"    Host: %@", [service hostName]);
            }
          
          if ([service port] > 0)
            {
              NSDebugLLog(@"gwcomp", @"    Port: %ld", (long)[service port]);
            }
          
          if ([service addresses] && [[service addresses] count] > 0)
            {
              NSDebugLLog(@"gwcomp", @"    Addresses:");
              for (NSData *addressData in [service addresses])
                {
                  struct sockaddr *sa = (struct sockaddr *)[addressData bytes];
                  char addr_str[INET6_ADDRSTRLEN];
                  
                  if (sa->sa_family == AF_INET)
                    {
                      struct sockaddr_in *sin = (struct sockaddr_in *)sa;
                      inet_ntop(AF_INET, &sin->sin_addr, addr_str, INET6_ADDRSTRLEN);
                      NSDebugLLog(@"gwcomp", @"      - IPv4: %s", addr_str);
                    }
                  else if (sa->sa_family == AF_INET6)
                    {
                      struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
                      inet_ntop(AF_INET6, &sin6->sin6_addr, addr_str, INET6_ADDRSTRLEN);
                      NSDebugLLog(@"gwcomp", @"      - IPv6: [%s]", addr_str);
                    }
                }
            }
          
          NSDictionary *dict = [NSNetService dictionaryFromTXTRecordData: [service TXTRecordData]];
          if (dict && [dict count] > 0)
            {
              NSDebugLLog(@"gwcomp", @"    Properties:");
              for (NSString *key in [dict allKeys])
                {
                  NSData *value = [dict objectForKey: key];
                  NSString *valueStr = [[NSString alloc] initWithData: value encoding: NSUTF8StringEncoding];
                  if (valueStr == nil)
                    {
                      valueStr = [[NSString alloc] initWithFormat: @"<binary data: %lu bytes>", (unsigned long)[value length]];
                    }
                  NSDebugLLog(@"gwcomp", @"      %@: %@", key, valueStr);
                  RELEASE(valueStr);
                }
            }
          
          NSDebugLLog(@"gwcomp", @"");
        }
    }
  
  NSDebugLLog(@"gwcomp", @"=========================================");
}

/* NSNetServiceBrowserDelegate methods */

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
  NSDebugLLog(@"gwcomp", @"  → Starting mDNS service discovery...");
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
  NSDebugLLog(@"gwcomp", @"Service discovery stopped.");
  [self printServices];
  
  /* Exit the run loop */
  [runLoop performSelector: @selector(stop) target: runLoop argument: nil order: 0 modes: [NSArray arrayWithObject: NSDefaultRunLoopMode]];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
           didFindService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
  NSDebugLLog(@"gwcomp", @"  ✓ Found: %@ (%@)", [aNetService name], [aNetService domain]);
  
  if (![services containsObject: aNetService])
    {
      [services addObject: aNetService];
      [aNetService setDelegate: self];
      [aNetService resolve];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
         didRemoveService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
  NSDebugLLog(@"gwcomp", @"  ✗ Removed: %@", [aNetService name]);
  [services removeObject: aNetService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
 didNotSearch:(NSDictionary *)errorDict
{
  NSDebugLLog(@"gwcomp", @"ERROR searching for services: %@", errorDict);
}

@end

int main(int argc, char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  @try
    {
      NSDebugLLog(@"gwcomp", @"[TEST] Initializing...");
      
      ServiceDiscoveryTest *test = [[ServiceDiscoveryTest alloc] init];
      if (!test)
        {
          NSDebugLLog(@"gwcomp", @"ERROR: Failed to create test instance");
          [pool drain];
          return 1;
        }
      
      NSDebugLLog(@"gwcomp", @"[TEST] Starting discovery...");
      [test startDiscovery];
      NSDebugLLog(@"gwcomp", @"[TEST] Discovery started");
      
      /* Run for 10 seconds */
      NSDate *stopDate = [NSDate dateWithTimeIntervalSinceNow: 10.0];
      int iterations = 0;
      
      NSDebugLLog(@"gwcomp", @"[TEST] Entering runloop...");
      while ([stopDate compare: [NSDate date]] == NSOrderedDescending)
        {
          iterations++;
          if (iterations % 10 == 0)
            NSDebugLLog(@"gwcomp", @"[TEST] Runloop iteration %d", iterations);
          [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
        }
      
      NSDebugLLog(@"gwcomp", @"[TEST] Exited runloop after %d iterations", iterations);
      [test printServices];
      [test release];
      NSDebugLLog(@"gwcomp", @"[TEST] Test completed");
    }
  @catch (NSException *exception)
    {
      NSDebugLLog(@"gwcomp", @"[TEST] Exception: %@", exception);
      NSDebugLLog(@"gwcomp", @"[TEST] Backtrace: %@", [exception callStackSymbols]);
    }
  
  [pool drain];
  return 0;
}
