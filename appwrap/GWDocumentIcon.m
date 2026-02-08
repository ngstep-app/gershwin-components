/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
 
#import "GWDocumentIcon.h"
#import "GWUtils.h"

@implementation GWDocumentIcon

+ (NSString *)createDocumentIconInResources:(NSString *)resourcesPath
                                    appName:(NSString *)appName
                           appIconFilename:(NSString *)appIconFilename
                                    mimeType:(NSString *)mimeType
                                    typeName:(NSString *)typeName
                                        size:(int)size
{
  if (!appName || !resourcesPath) return nil;

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *sanApp = [GWUtils sanitizeFileName:appName];
  NSString *sanType = [GWUtils sanitizeFileName:typeName ? typeName : mimeType];

  NSString *docFilename = [NSString stringWithFormat:@"%@-doc-%@.png", sanApp, sanType];
  NSString *docPath = [resourcesPath stringByAppendingPathComponent:docFilename];

  // 1. Load app icon from bundle resources
  NSImage *appIcon = nil;
  if (appIconFilename && [appIconFilename length] > 0)
    {
      NSString *appIconFull = [resourcesPath stringByAppendingPathComponent:appIconFilename];
      if ([fm fileExistsAtPath:appIconFull])
        {
          appIcon = [[NSImage alloc] initWithContentsOfFile:appIconFull];
        }
    }

  // 2. Load generic document icon from the current theme/system
  // We prioritize known names to ensure we follow the visual style of the selected GNUstep theme.
  // Many themes use common_Unknown or page_portrait as the base for documents.
  NSArray *baseNames = @[@"NSDocument", @"common_document", @"common_Unknown", @"Unknown", @"page_portrait", @"NSDocumentIcon"];
  NSImage *docBase = nil;
  for (NSString *name in baseNames)
    {
      docBase = [NSImage imageNamed:name];
      // If we got an image, use it. We don't discard common_Unknown anymore because 
      // in the Eau theme it might be the intended document icon.
      if (docBase)
        {
          NSDebugLog(@"Found base icon: %@ with name: %@", name, [docBase name]);
          break;
        }
    }

  // Fallback to NSWorkspace if theme images aren't found directly
  if (!docBase)
    {
      docBase = [[NSWorkspace sharedWorkspace] iconForFileType:@"public.data"];
    }
  
  NSDebugLog(@"createDocumentIcon: selected docBase=%@ name=%@ appIcon=%@ size=%d", 
        docBase, [docBase name], appIcon, size);

  // 3. Create canvas and draw
  NSImage *canvas = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
  [canvas lockFocus];

  // Start with transparent background
  [[NSColor clearColor] set];
  NSRectFill(NSMakeRect(0, 0, size, size));

  if (docBase)
    {
      [docBase drawInRect:NSMakeRect(0, 0, size, size)
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0];
    }
  else
    {
      // Draw a proper "Generic Document" icon fallback (White sheet, folded corner, lines)
      NSRect r = NSMakeRect(size * 0.15, size * 0.05, size * 0.7, size * 0.9);
      
      // Page body
      [[NSColor whiteColor] setFill];
      [[NSColor darkGrayColor] setStroke];
      NSBezierPath *p = [NSBezierPath bezierPath];
      CGFloat corner = size * 0.2;
      [p moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
      [p lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(r))];
      [p lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(r) - corner)];
      [p lineToPoint:NSMakePoint(NSMaxX(r) - corner, NSMaxY(r))];
      [p lineToPoint:NSMakePoint(NSMinX(r), NSMaxY(r))];
      [p closePath];
      
      [p fill];
      [p setLineWidth:size * 0.01];
      [p stroke];
      
      // Folded corner
      NSBezierPath *fold = [NSBezierPath bezierPath];
      [fold moveToPoint:NSMakePoint(NSMaxX(r) - corner, NSMaxY(r))];
      [fold lineToPoint:NSMakePoint(NSMaxX(r) - corner, NSMaxY(r) - corner)];
      [fold lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(r) - corner)];
      [[NSColor colorWithCalibratedWhite:0.9 alpha:1.0] setFill];
      [fold fill];
      [fold stroke];
      
      // Horizontal lines (dummy text)
      [[NSColor lightGrayColor] setStroke];
      [NSBezierPath setDefaultLineWidth:size * 0.01];
      for (int i=0; i<6; i++)
        {
          CGFloat y = NSMaxY(r) - corner - size*0.1 - (i * size * 0.1);
          if (y < NSMinY(r) + size*0.1) break;
          [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(r) + size*0.1, y)
                                    toPoint:NSMakePoint(NSMaxX(r) - size*0.1, y)];
        }
    }

  // 4. Draw app icon overlay centered, 45% of document size
  if (appIcon)
    {
      CGFloat overlaySize = size * 0.45;
      NSRect overlayRect = NSMakeRect((size - overlaySize) / 2.0, (size - overlaySize) / 2.0, overlaySize, overlaySize);

      // Draw the app icon with transparency preserved
      [appIcon drawInRect:overlayRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
      [appIcon release];
    }

  // 4.5. Draw file extension text below the app icon
  // Extract file extension from MIME type
  NSArray *extensions = [GWUtils extensionsForMIMEType:mimeType];
  NSString *extensionText = nil;
  
  if (extensions && [extensions count] > 0)
    {
      // Get the first extension and make it uppercase with a dot
      NSString *ext = [extensions objectAtIndex:0];
      if (ext && [ext length] > 0)
        {
          // Remove leading dot if present and add uppercase dot and extension
          if ([ext hasPrefix:@"."])
            {
              extensionText = [[ext substringFromIndex:1] uppercaseString];
            }
          else
            {
              extensionText = [ext uppercaseString];
            }
          extensionText = [NSString stringWithFormat:@"%@", extensionText];
        }
    }
  
  // Draw the extension text below the app icon
  if (extensionText && [extensionText length] > 0)
    {
      // Calculate text position - slightly above previous baseline (half a line up)
      CGFloat overlaySize = size * 0.45;
      CGFloat overlayY = (size - overlaySize) / 2.0;
      CGFloat textBottom = overlayY - size * 0.08;  // Small gap below icon
      
      // Create text attributes (dark grey color, bold)
      NSFont *font = [NSFont boldSystemFontOfSize:size * 0.12];
      NSColor *textColor = [NSColor colorWithCalibratedWhite:0.25 alpha:1.0];
      NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, textColor, NSForegroundColorAttributeName, nil];
      
      // Measure text
      NSSize textSize = [extensionText sizeWithAttributes:attrs];
      
      // Draw text centered below the icon and moved up by half a line
      NSPoint textPoint = NSMakePoint((size - textSize.width) / 2.0, textBottom - (textSize.height * 0.5));
      [extensionText drawAtPoint:textPoint withAttributes:attrs];
    }

  // 5. Capture as PNG
  NSData *pngData = nil;
  NSData *tiffData = [canvas TIFFRepresentation];
  if (tiffData)
    {
      NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiffData];
      if (rep)
        {
          pngData = [rep representationUsingType:NSPNGFileType properties:nil];
        }
    }
  [canvas unlockFocus];
  [canvas release];

  if (!(pngData && [pngData writeToFile:docPath atomically:YES]))
    {
      NSLog(@"Failed to write document icon to %@", docPath);
      return nil;
    }

  // Basic validation
  NSImage *verify = [[NSImage alloc] initWithContentsOfFile:docPath];
  BOOL valid = (verify && [verify size].width > 0);
  [verify release];

  if (valid)
    {
      NSDebugLog(@"Document icon created and validated: %@", docPath);
      return docFilename;
    }

  NSLog(@"Removing invalid document icon: %@", docPath);
  [[NSFileManager defaultManager] removeItemAtPath:docPath error:NULL];
  return nil;
}

@end
