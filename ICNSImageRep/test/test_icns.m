/*
 * Test program for ICNS loading
 */

#import <Foundation/Foundation.h>

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (argc < 2)
    {
        printf("Usage: %s <icns-file>\n", argv[0]);
        [pool release];
        return 1;
    }
    
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    
    NSDebugLLog(@"gwcomp", @"Attempting to load ICNS file: %@", path);
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    if (!data)
    {
        NSDebugLLog(@"gwcomp", @"✗ Failed to read file");
        [pool release];
        return 1;
    }
    
    NSDebugLLog(@"gwcomp", @"✓ Successfully read file: %lu bytes", (unsigned long)[data length]);
    
    if ([data length] >= 4)
    {
        const unsigned char *bytes = [data bytes];
        NSDebugLLog(@"gwcomp", @"  Magic: '%c%c%c%c'", bytes[0], bytes[1], bytes[2], bytes[3]);
        
        if (bytes[0] == 'i' && bytes[1] == 'c' && bytes[2] == 'n' && bytes[3] == 's')
        {
            NSDebugLLog(@"gwcomp", @"✓ File is a valid ICNS file");
        }
    }
    
    [pool release];
    return 0;
}
