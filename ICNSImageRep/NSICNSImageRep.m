/*
 * NSICNSImageRep.m
 * ICNS Image Representation for GNUstep
 *
 * Provides support for reading ICNS icon files throughout the system.
 */

#import "NSICNSImageRep.h"
#import <Foundation/Foundation.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphics.h>
#import <icns.h>

@implementation NSICNSImageRep

+ (void)load
{
    NSDebugLLog(@"gwcomp", @"Registering NSICNSImageRep");
    [NSImageRep registerImageRepClass:[NSICNSImageRep class]];
}

+ (NSArray *)imageUnfilteredFileTypes
{
    return [NSArray arrayWithObjects:@"icns", nil];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
    return [NSArray arrayWithObjects:@"com.icns", nil];
}

+ (BOOL)canInitWithData:(NSData *)data
{
    if (!data || [data length] < 4)
        return NO;
    
    const unsigned char *bytes = [data bytes];
    return (bytes[0] == 'i' &&
            bytes[1] == 'c' &&
            bytes[2] == 'n' &&
            bytes[3] == 's');
}

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (!self)
        return nil;

    _icnsData = [data retain];
    _representations = [[NSMutableArray alloc] init];

    icns_family_t *family = NULL;
    int status = icns_import_family_data([data length], (icns_byte_t *)[data bytes], &family);
    
    if (status != ICNS_STATUS_OK)
    {
        NSDebugLLog(@"gwcomp", @"Failed to read ICNS family: %d", status);
        [self release];
        return nil;
    }

    icns_type_t icon_types[] = {
        ICNS_512x512_32BIT_ARGB_DATA,
        ICNS_256x256_32BIT_ARGB_DATA,
        ICNS_128x128_32BIT_ARGB_DATA,
        ICNS_64x64_32BIT_ARGB_DATA,
        ICNS_48x48_32BIT_DATA,
        ICNS_32x32_32BIT_DATA,
        ICNS_16x16_32BIT_DATA
    };
    
    int num_types = sizeof(icon_types) / sizeof(icns_type_t);
    NSSize largestSize = NSZeroSize;
    
    for (int i = 0; i < num_types; i++)
    {
        icns_image_t image;
        status = icns_get_image32_with_mask_from_family(family, icon_types[i], &image);
        
        if (status == ICNS_STATUS_OK && image.imageWidth > 0 && image.imageHeight > 0)
        {
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL
                              pixelsWide:image.imageWidth
                              pixelsHigh:image.imageHeight
                           bitsPerSample:8
                         samplesPerPixel:4
                                hasAlpha:YES
                                isPlanar:NO
                          colorSpaceName:NSCalibratedRGBColorSpace
                             bytesPerRow:image.imageWidth * 4
                            bitsPerPixel:32];

            if (bitmap)
            {
                memcpy([bitmap bitmapData], image.imageData,
                       image.imageWidth * image.imageHeight * 4);
                
                [_representations addObject:bitmap];
                [bitmap release];
                
                if (image.imageWidth > largestSize.width)
                {
                    largestSize = NSMakeSize(image.imageWidth, image.imageHeight);
                }
            }
            
            icns_free_image(&image);
        }
    }

    if (family)
        free(family);

    if ([_representations count] == 0)
    {
        NSDebugLLog(@"gwcomp", @"No valid ICNS representations found");
        [self release];
        return nil;
    }

    [self setSize:largestSize];
    
    NSDebugLLog(@"gwcomp", @"Successfully loaded ICNS with %lu representations, size: %.0fx%.0f",
          (unsigned long)[_representations count], largestSize.width, largestSize.height);
    
    return self;
}

- (void)dealloc
{
    [_icnsData release];
    [_representations release];
    [super dealloc];
}

- (BOOL)draw
{
    if ([_representations count] == 0)
        return NO;
    
    NSBitmapImageRep *bestRep = [_representations objectAtIndex:0];
    return [bestRep draw];
}

- (NSData *)icnsData
{
    return _icnsData;
}

@end
