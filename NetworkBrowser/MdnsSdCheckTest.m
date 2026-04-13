/*
 * MdnsSdCheckTest.m - Test mDNS-SD availability check
 *
 * This tool demonstrates how the NetworkBrowser checks for mDNS-SD support
 * and verifies that NSNetServiceBrowser is available in the GNUstep installation.
 */

#import <Foundation/Foundation.h>

int main(int argc, char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSDebugLLog(@"gwcomp", @"================================================");
  NSDebugLLog(@"gwcomp", @"mDNS-SD Support Check");
  NSDebugLLog(@"gwcomp", @"================================================");
  NSDebugLLog(@"gwcomp", @"");
  
  /* Check if NSNetServiceBrowser is available */
  Class netServiceBrowserClass = NSClassFromString(@"NSNetServiceBrowser");
  
  if (netServiceBrowserClass)
    {
      NSDebugLLog(@"gwcomp", @"✓ SUCCESS: NSNetServiceBrowser class is available");
      NSDebugLLog(@"gwcomp", @"  This GNUstep installation HAS mDNS-SD support");
      NSDebugLLog(@"gwcomp", @"");
      NSDebugLLog(@"gwcomp", @"  - NSNetServiceBrowser: %@", netServiceBrowserClass);
      
      /* Check for related classes */
      Class netServiceClass = NSClassFromString(@"NSNetService");
      if (netServiceClass)
        NSDebugLLog(@"gwcomp", @"  - NSNetService: %@", netServiceClass);
      
      Class netServiceDelegateClass = NSClassFromString(@"NSNetServiceDelegate");
      if (netServiceDelegateClass)
        NSDebugLLog(@"gwcomp", @"  - NSNetServiceDelegate: %@", netServiceDelegateClass);
      
      NSDebugLLog(@"gwcomp", @"");
      NSDebugLLog(@"gwcomp", @"Action: NetworkBrowser will proceed with service discovery");
    }
  else
    {
      NSDebugLLog(@"gwcomp", @"✗ WARNING: NSNetServiceBrowser class NOT available");
      NSDebugLLog(@"gwcomp", @"  This GNUstep installation does NOT have mDNS-SD support");
      NSDebugLLog(@"gwcomp", @"");
      NSDebugLLog(@"gwcomp", @"To fix this issue:");
      NSDebugLLog(@"gwcomp", @"  1. Install libdns_sd development files");
      NSDebugLLog(@"gwcomp", @"     - Debian/Ubuntu: sudo apt-get install libavahi-compat-libdnssd-dev");
      NSDebugLLog(@"gwcomp", @"     - Fedora/RHEL: sudo dnf install avahi-compat-libdns_sd-devel");
      NSDebugLLog(@"gwcomp", @"     - FreeBSD/OpenBSD: sudo pkg install mDNSResponder");
      NSDebugLLog(@"gwcomp", @"     - macOS: Xcode Command Line Tools (xcode-select --install)");
      NSDebugLLog(@"gwcomp", @"");
      NSDebugLLog(@"gwcomp", @"  2. Rebuild GNUstep with DNS-SD support");
      NSDebugLLog(@"gwcomp", @"");
      NSDebugLLog(@"gwcomp", @"Action: NetworkBrowser will show warning and ask user to continue or quit");
    }
  
  NSDebugLLog(@"gwcomp", @"");
  NSDebugLLog(@"gwcomp", @"================================================");
  
  [pool drain];
  return netServiceBrowserClass ? 0 : 1;
}
