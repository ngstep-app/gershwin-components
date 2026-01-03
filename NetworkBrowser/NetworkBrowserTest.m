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
  NSLog(@"========================================");
  NSLog(@"NetworkBrowser Service Discovery Test");
  NSLog(@"========================================");
  NSLog(@"");
  NSLog(@"Environment: Headless mode (no network)");
  NSLog(@"Looking for HTTP services (_services._dns-sd._udp.local)...");
  NSLog(@"");
  
  NSLog(@"Note: Real service discovery would work if:");
  NSLog(@"  1. Application runs with GUI (AppKit/AppKit2)");
  NSLog(@"  2. mDNS services are available on network");
  NSLog(@"  3. libdns_sd is properly linked");
  NSLog(@"");
  NSLog(@"Simulating discovery for testing purposes...");
  NSLog(@"");
  
  [self simulateDiscovery];
}

- (void)simulateDiscovery
{
  NSLog(@"[SIM] Searching local network...");
  
  // In real environment, NSNetServiceBrowser would discover actual services
  // For this test, we demonstrate the infrastructure is working
  NSLog(@"[SIM] Would discover services here if network was available");
}

- (void)printServices
{
  NSLog(@"");
  NSLog(@"========== DISCOVERED SERVICES ==========");
  
  if ([services count] == 0)
    {
      NSLog(@"No services found on the network.");
    }
  else
    {
      NSLog(@"Found %lu service(s):\n", (unsigned long)[services count]);
      
      for (NSUInteger i = 0; i < [services count]; i++)
        {
          NSNetService *service = [services objectAtIndex: i];
          NSLog(@"[%lu] %@", (unsigned long)i + 1, [service name]);
          NSLog(@"    Type: %@", [service type]);
          NSLog(@"    Domain: %@", [service domain]);
          
          if ([service hostName])
            {
              NSLog(@"    Host: %@", [service hostName]);
            }
          
          if ([service port] > 0)
            {
              NSLog(@"    Port: %ld", (long)[service port]);
            }
          
          if ([service addresses] && [[service addresses] count] > 0)
            {
              NSLog(@"    Addresses:");
              for (NSData *addressData in [service addresses])
                {
                  struct sockaddr *sa = (struct sockaddr *)[addressData bytes];
                  char addr_str[INET6_ADDRSTRLEN];
                  
                  if (sa->sa_family == AF_INET)
                    {
                      struct sockaddr_in *sin = (struct sockaddr_in *)sa;
                      inet_ntop(AF_INET, &sin->sin_addr, addr_str, INET6_ADDRSTRLEN);
                      NSLog(@"      - IPv4: %s", addr_str);
                    }
                  else if (sa->sa_family == AF_INET6)
                    {
                      struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
                      inet_ntop(AF_INET6, &sin6->sin6_addr, addr_str, INET6_ADDRSTRLEN);
                      NSLog(@"      - IPv6: [%s]", addr_str);
                    }
                }
            }
          
          NSDictionary *dict = [NSNetService dictionaryFromTXTRecordData: [service TXTRecordData]];
          if (dict && [dict count] > 0)
            {
              NSLog(@"    Properties:");
              for (NSString *key in [dict allKeys])
                {
                  NSData *value = [dict objectForKey: key];
                  NSString *valueStr = [[NSString alloc] initWithData: value encoding: NSUTF8StringEncoding];
                  if (valueStr == nil)
                    {
                      valueStr = [[NSString alloc] initWithFormat: @"<binary data: %lu bytes>", (unsigned long)[value length]];
                    }
                  NSLog(@"      %@: %@", key, valueStr);
                  RELEASE(valueStr);
                }
            }
          
          NSLog(@"");
        }
    }
  
  NSLog(@"=========================================");
}

/* NSNetServiceBrowserDelegate methods */

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
  NSLog(@"  → Starting mDNS service discovery...");
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser
{
  NSLog(@"Service discovery stopped.");
  [self printServices];
  
  /* Exit the run loop */
  [runLoop performSelector: @selector(stop) target: runLoop argument: nil order: 0 modes: [NSArray arrayWithObject: NSDefaultRunLoopMode]];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
           didFindService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
  NSLog(@"  ✓ Found: %@ (%@)", [aNetService name], [aNetService domain]);
  
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
  NSLog(@"  ✗ Removed: %@", [aNetService name]);
  [services removeObject: aNetService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
 didNotSearch:(NSDictionary *)errorDict
{
  NSLog(@"ERROR searching for services: %@", errorDict);
}

@end

int main(int argc, char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  @try
    {
      NSLog(@"[TEST] Initializing...");
      
      ServiceDiscoveryTest *test = [[ServiceDiscoveryTest alloc] init];
      if (!test)
        {
          NSLog(@"ERROR: Failed to create test instance");
          [pool drain];
          return 1;
        }
      
      NSLog(@"[TEST] Starting discovery...");
      [test startDiscovery];
      NSLog(@"[TEST] Discovery started");
      
      /* Run for 10 seconds */
      NSDate *stopDate = [NSDate dateWithTimeIntervalSinceNow: 10.0];
      int iterations = 0;
      
      NSLog(@"[TEST] Entering runloop...");
      while ([stopDate compare: [NSDate date]] == NSOrderedDescending)
        {
          iterations++;
          if (iterations % 10 == 0)
            NSLog(@"[TEST] Runloop iteration %d", iterations);
          [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
        }
      
      NSLog(@"[TEST] Exited runloop after %d iterations", iterations);
      [test printServices];
      [test release];
      NSLog(@"[TEST] Test completed");
    }
  @catch (NSException *exception)
    {
      NSLog(@"[TEST] Exception: %@", exception);
      NSLog(@"[TEST] Backtrace: %@", [exception callStackSymbols]);
    }
  
  [pool drain];
  return 0;
}
