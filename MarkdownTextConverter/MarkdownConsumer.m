/*
 * MarkdownConsumer.m
 *
 * Parses Markdown text into NSAttributedString
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MarkdownConsumer.h"
#include <stdio.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSTextAttachment.h>
#import "CodeTextBlock.h"

/* Forward declarations of helper functions */
static BOOL isHeading(NSString *line, NSUInteger *level);
static BOOL isListItem(NSString *line, BOOL *isOrdered, NSUInteger *number);
static BOOL isHorizontalRule(NSString *line);
static BOOL isCodeFence(NSString *line, NSString **language);

@implementation MarkdownConsumer

+ (void)initialize
{
  if (self == [MarkdownConsumer class])
    {
      /* Register with GNUstep text converter system if needed, 
         but for now we are using it directly */
    }
}

+ (NSAttributedString *)parseData:(NSData *)aData
                          options:(NSDictionary *)options
               documentAttributes:(NSDictionary **)dict
                            error:(NSError **)error
                            class:(Class)class
{
  MarkdownConsumer *consumer;
  NSAttributedString *result;
  
  if (aData == nil || [aData length] == 0)
    {
      return [[[class alloc] initWithString:@""] autorelease];
    }
  
  consumer = [[self alloc] initWithClass:class];
  result = [consumer _parseMarkdownData:aData];
  
  if (dict != NULL)
    {
      *dict = [[consumer->_documentAttributes copy] autorelease];
    }
  
  RELEASE(consumer);
  
  if (result == nil && error != NULL)
    {
      *error = [NSError errorWithDomain:@"MarkdownConsumerErrorDomain"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse Markdown"}];
    }
  
  return result;
}

- (id)initWithClass:(Class)class
{
  self = [super init];
  if (self)
    {
      _attributedStringClass = class;
      _result = [[NSMutableAttributedString alloc] init];
      _documentAttributes = [[NSMutableDictionary alloc] init];
      
      /* Initialize font cache */
      [self _initializeFonts];
      
      /* Initialize paragraph styles */
      [self _initializeParagraphStyles];
      
      /* Initialize parser state */
      _inCodeBlock = NO;
      _inBlockquote = NO;
      _inList = NO;
      _listLevel = 0;
      _isOrderedList = NO;
      _codeBlockContent = nil;
      _codeBlockLanguage = nil;
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_result);
  RELEASE(_documentAttributes);
  RELEASE(_bodyFont);
  RELEASE(_boldFont);
  RELEASE(_italicFont);
  RELEASE(_boldItalicFont);
  RELEASE(_codeFont);
  RELEASE(_headingFonts);
  RELEASE(_normalParagraphStyle);
  RELEASE(_blockquoteParagraphStyle);
  RELEASE(_listParagraphStyles);
  RELEASE(_codeBlockLanguage);
  RELEASE(_codeBlockContent);
  RELEASE(_currentLine);
  [super dealloc];
}

#pragma mark - Fonts & system configuration

- (NSString *)_preferredFontFamilyFromFontsConfForRole:(NSString *)role
{
  /*
   * Try to read system fonts.conf and return a family name for the given role
   * Basic heuristic: find first <family>..</family> entry; prefer ones that
   * contain the role name (e.g., 'mono', 'sans', 'serif') if present.
   */
  NSString *path = @"/System/Library/Preferences/fonts.conf";
  NSError *err = nil;
  NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
  if (!contents)
    return nil;

  NSString *roleLower = [role lowercaseString];

  NSScanner *scanner = [NSScanner scannerWithString:contents];
  NSString *family = nil;
  while (![scanner isAtEnd])
    {
      if ([scanner scanUpToString:@"<family>" intoString:NULL])
        {
          if (![scanner scanString:@"<family>" intoString:NULL]) break;
          if ([scanner scanUpToString:@"</family>" intoString:&family])
            {
              NSString *famLower = [family lowercaseString];
              if (role == nil || [famLower rangeOfString:roleLower].location != NSNotFound)
                return [family stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
    }
  return nil;
}

- (NSFont *)_fontForFamilyName:(NSString *)family size:(CGFloat)size fallback:(NSFont *)fallback
{
  if (!family) return fallback;
  NSFontManager *fm = [NSFontManager sharedFontManager];
  NSArray *members = [fm availableMembersOfFontFamily:family];

  // If no direct members, try to find a matching family by substring
  if (!members || [members count] == 0)
    {
      NSArray *allFamilies = [fm availableFontFamilies];
      NSString *familyLower = [family lowercaseString];
      for (NSString *cand in allFamilies)
        {
          if ([[cand lowercaseString] rangeOfString:familyLower].location != NSNotFound)
            {
              members = [fm availableMembersOfFontFamily:cand];
              if (members && [members count] > 0)
                break;
            }
        }
    }

  if (members && [members count] > 0)
    {
      NSArray *member = [members objectAtIndex:0];
      if ([member count] > 0)
        {
          NSString *postScript = [member objectAtIndex:0];
          NSFont *f = [NSFont fontWithName:postScript size:size];
          if (f) return f;
        }
    }

  NSFont *f = [NSFont fontWithName:family size:size];
  return f ? f : fallback;
}

- (NSString *)_fontconfigFamilyForRole:(NSString *)role
{
  if (!role) return nil;

  // Try several likely fc-match locations to handle reduced PATH in some environments
  NSArray *candidates = @[@"fc-match", @"/usr/bin/fc-match", @"/usr/local/bin/fc-match", @"/bin/fc-match"];
  char buf[512];
  for (NSString *cmdPath in candidates)
    {
      char cmd[1024];
      snprintf(cmd, sizeof(cmd), "%s -f '%%{family}' %s", [cmdPath UTF8String], [role UTF8String]);
      FILE *fp = popen(cmd, "r");
      if (!fp) continue;
      if (fgets(buf, sizeof(buf), fp) == NULL)
        {
          pclose(fp);
          continue;
        }
      pclose(fp);
      NSString *s = [NSString stringWithUTF8String:buf];
      s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([s length] > 0)
        return s;
    }
  return nil;
}

- (NSString *)_fontconfigFamilyForName:(NSString *)name
{
  if (!name) return nil;

  NSArray *candidates = @[@"fc-match", @"/usr/bin/fc-match", @"/usr/local/bin/fc-match", @"/bin/fc-match"];
  char buf[512];

  for (NSString *cmdPath in candidates)
    {
      char cmd[1024];
      snprintf(cmd, sizeof(cmd), "%s -f '%%{family}' '%s'", [cmdPath UTF8String], [name UTF8String]);
      FILE *fp = popen(cmd, "r");
      if (!fp) continue;
      if (fgets(buf, sizeof(buf), fp) == NULL)
        {
          pclose(fp);
          continue;
        }
      pclose(fp);
      NSString *s = [NSString stringWithUTF8String:buf];
      s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([s length] > 0) return s;
    }
  return nil;
}

- (void)_initializeFonts
{
  NSFontManager *fontManager = [NSFontManager sharedFontManager];
  CGFloat systemSize = [NSFont systemFontSize];

  /* Body font: try system font config, fall back to Helvetica or system */
  NSString *preferredSans = [self _preferredFontFamilyFromFontsConfForRole:@"sans"];

  /* If fontconfig is available, ask it for the best match (ensures aliases like 'sans' map to configured family) */
  if (!preferredSans)
    {
      NSString *fc = [self _fontconfigFamilyForRole:@"sans"];
      if (fc && [fc length] > 0)
        preferredSans = fc;
    }

  /* Explicitly check fc-match 'Helvetica' as some systems alias Helvetica to Nimbus Sans; prefer it if present */
  NSString *hel = [self _fontconfigFamilyForName:@"Helvetica"];
  NSDebugLLog(@"gwcomp", @"[MarkdownConsumer] fc-match(Helvetica) -> %@", hel ? hel : @"(nil)");
  if (hel && [hel length] > 0)
    {
      preferredSans = hel;
    }

  /* Also check Courier mapping for monospace */
  NSString *courCheck = [self _fontconfigFamilyForName:@"Courier"];
  NSDebugLLog(@"gwcomp", @"[MarkdownConsumer] fc-match(Courier) -> %@", courCheck ? courCheck : @"(nil)");

  NSDebugLLog(@"gwcomp", @"[MarkdownConsumer] initial preferredSans from fonts.conf/fc-match: %@", preferredSans);

  // If fonts.conf/fc-match didn't yield a sans, prefer Nimbus if available (common Helvetica replacement)
  if (!preferredSans)
    {
      NSFontManager *fm = [NSFontManager sharedFontManager];
      for (NSString *fam in [fm availableFontFamilies])
        {
          if ([[[fam lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] rangeOfString:@"nimbus"].location != NSNotFound)
            {
              preferredSans = fam;
              break;
            }
        }
    }

  NSFont *fallbackBody = [NSFont fontWithName:@"Helvetica" size:systemSize];
  if (!fallbackBody) fallbackBody = [NSFont systemFontOfSize:systemSize];
  NSFont *body = nil;
  if (preferredSans)
    body = [self _fontForFamilyName:preferredSans size:systemSize fallback:fallbackBody];
  if (!body)
    body = fallbackBody;
  _bodyFont = RETAIN(body);
  NSDebugLLog(@"gwcomp", @"[MarkdownConsumer] selected body font: %@", _bodyFont);

  /* Bold/italic variants based on body font family members */
  NSFont *bold = nil;
  NSArray *members = [fontManager availableMembersOfFontFamily:[_bodyFont familyName]];
  if (!members) members = @[];
  for (NSArray *m in members)
    {
      NSString *style = [m objectAtIndex:1];
      if ([[style lowercaseString] rangeOfString:@"bold"].location != NSNotFound)
        {
          NSString *post = [m objectAtIndex:0];
          bold = [NSFont fontWithName:post size:systemSize];
          break;
        }
    }
  if (!bold)
    bold = [fontManager convertFont:_bodyFont toHaveTrait:NSBoldFontMask];
  _boldFont = RETAIN(bold);

  NSFont *italic = nil;
  for (NSArray *m in members)
    {
      NSString *style = [m objectAtIndex:1];
      if ([[style lowercaseString] rangeOfString:@"italic"].location != NSNotFound || [[style lowercaseString] rangeOfString:@"oblique"].location != NSNotFound)
        {
          NSString *post = [m objectAtIndex:0];
          italic = [NSFont fontWithName:post size:systemSize];
          break;
        }
    }
  if (!italic)
    italic = [fontManager convertFont:_bodyFont toHaveTrait:NSItalicFontMask];
  _italicFont = RETAIN(italic);

  _boldItalicFont = RETAIN([fontManager convertFont:_boldFont toHaveTrait:NSItalicFontMask]);

  /* Code font: consult font config for monospace */
  NSString *preferredMono = [self _preferredFontFamilyFromFontsConfForRole:@"mono"];

  /* Check fc-match 'Courier' to pick system substitute (e.g., Nimbus Mono PS) */
  NSString *cour = [self _fontconfigFamilyForName:@"Courier"];
  if (cour && [cour length] > 0)
    {
      preferredMono = cour;
    }

  NSFont *fallbackMono = [NSFont fontWithName:@"Courier" size:MAX(10.0, systemSize * 0.9)];
  if (!fallbackMono) fallbackMono = [NSFont userFixedPitchFontOfSize:MAX(10.0, systemSize * 0.9)];
  NSFont *mono = nil;
  if (preferredMono)
    mono = [self _fontForFamilyName:preferredMono size:MAX(10.0, systemSize * 0.9) fallback:fallbackMono];
  if (!mono)
    mono = fallbackMono;
  _codeFont = RETAIN(mono);

  /* Create heading fonts H1-H6 using bold body/family at larger sizes */
  _headingFonts = [[NSMutableArray alloc] initWithCapacity:6];
  CGFloat headingSizes[] = {systemSize * 2.0, systemSize * 1.7, systemSize * 1.5,
                            systemSize * 1.3, systemSize * 1.15, systemSize * 1.05};

  for (int i = 0; i < 6; i++)
    {
      NSFont *baseFont = [self _fontForFamilyName:[_bodyFont familyName] size:headingSizes[i] fallback:[NSFont systemFontOfSize:headingSizes[i]]];
      if (!baseFont)
        baseFont = [NSFont systemFontOfSize:headingSizes[i]];
      NSFont *headingFont = [fontManager convertFont:baseFont toHaveTrait:NSBoldFontMask];
      if (!headingFont)
        headingFont = [NSFont boldSystemFontOfSize:headingSizes[i]];
      [_headingFonts addObject:headingFont];
    }
}

- (void)_initializeParagraphStyles
{
  NSMutableParagraphStyle *normalStyle = [[NSMutableParagraphStyle alloc] init];
  [normalStyle setParagraphSpacing:18.0];
  _normalParagraphStyle = [normalStyle copy];
  RELEASE(normalStyle);
  
  NSMutableParagraphStyle *blockquoteStyle = [[NSMutableParagraphStyle alloc] init];
  [blockquoteStyle setParagraphSpacing:12.0];
  [blockquoteStyle setFirstLineHeadIndent:20.0];
  [blockquoteStyle setHeadIndent:20.0];
  _blockquoteParagraphStyle = [blockquoteStyle copy];
  RELEASE(blockquoteStyle);
  
  /* Create list paragraph styles for different levels */
  _listParagraphStyles = [[NSMutableArray alloc] initWithCapacity:5];
  for (int i = 0; i < 5; i++)
    {
      NSMutableParagraphStyle *listStyle = [[NSMutableParagraphStyle alloc] init];
      [listStyle setParagraphSpacing:6.0];
      [listStyle setFirstLineHeadIndent:20.0 * (i + 1)];
      [listStyle setHeadIndent:30.0 * (i + 1)];
      [_listParagraphStyles addObject:listStyle];
      RELEASE(listStyle);
    }
}

- (NSAttributedString *)_parseMarkdownData:(NSData *)data
{
  NSString *markdown = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
  
  if (markdown == nil)
    {
      return nil;
    }
  
  NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
  RELEASE(markdown);
  
  for (NSString *line in lines)
    {
      [self _processLine:line];
    }
  
  /* Finalize any open blocks */
  [self _finalizeOpenBlocks];
  
  return [[_result copy] autorelease];
}

- (void)_processLine:(NSString *)line
{
  NSString *trimmedLine = [line stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
  
  /* Handle code blocks */
  NSString *language = nil;
  if (isCodeFence(trimmedLine, &language))
    {
      if (_inCodeBlock)
        {
          /* End code block */
          [self _finalizeCodeBlock];
        }
      else
        {
          /* Start code block */
          _inCodeBlock = YES;
          _codeBlockLanguage = RETAIN(language);
          _codeBlockContent = [[NSMutableString alloc] init];
        }
      return;
    }
  
  if (_inCodeBlock)
    {
      /* Accumulate code block content */
      [_codeBlockContent appendString:line];
      [_codeBlockContent appendString:@"\n"];
      return;
    }
  
  /* Handle horizontal rules */
  if (isHorizontalRule(trimmedLine))
    {
      [self _addHorizontalRule];
      return;
    }
  
  /* Handle headings */
  NSUInteger headingLevel = 0;
  if (isHeading(trimmedLine, &headingLevel))
    {
      NSString *headingText = [trimmedLine substringFromIndex:headingLevel + 1];
      [self _addHeading:headingText level:headingLevel];
      return;
    }
  
  /* Handle list items */
  BOOL isOrdered = NO;
  NSUInteger listNumber = 0;
  if (isListItem(trimmedLine, &isOrdered, &listNumber))
    {
      /* Extract list item text */
      NSRange markerRange = [trimmedLine rangeOfString:isOrdered ? @"." : @" "];
      if (markerRange.location != NSNotFound)
        {
          NSString *itemText = [[trimmedLine substringFromIndex:markerRange.location + 1]
                                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
          [self _addListItem:itemText ordered:isOrdered number:listNumber];
        }
      return;
    }
  
  /* Handle blockquotes */
  if ([trimmedLine hasPrefix:@">"])
    {
      NSString *quoteText = [[trimmedLine substringFromIndex:1]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      [self _addBlockquote:quoteText];
      return;
    }
  
  /* Handle empty lines */
  if ([trimmedLine length] == 0)
    {
      [self _addParagraphBreak];
      return;
    }
  
  /* Regular paragraph */
  [self _addParagraph:line];
}

- (void)_addHeading:(NSString *)text level:(NSUInteger)level
{
  if (level < 1 || level > 6)
    level = 1;

  NSFont *headingFont = [_headingFonts objectAtIndex:level - 1];
  NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
  [para setParagraphSpacing: 12.0 + (6 - level) * 2.0];
  [para setFirstLineHeadIndent:0.0];
  [para setHeadIndent:0.0];
  [para setHeaderLevel: level];

  NSDictionary *attributes = @{
    NSFontAttributeName: headingFont,
    NSParagraphStyleAttributeName: para,
    NSForegroundColorAttributeName: [NSColor textColor]
  };

  NSAttributedString *headingString = [self _parseInlineMarkdown:text
                                                  withAttributes:attributes];
  [_result appendAttributedString:headingString];
  [_result appendAttributedString:[self _newlineWithParagraphStyle:_normalParagraphStyle]];
  RELEASE(para);
}

- (void)_addParagraph:(NSString *)text
{
  NSDictionary *attributes = @{
    NSFontAttributeName: _bodyFont,
    NSParagraphStyleAttributeName: _normalParagraphStyle
  };
  
  NSAttributedString *paraString = [self _parseInlineMarkdown:text
                                               withAttributes:attributes];
  [_result appendAttributedString:paraString];
}

- (void)_addListItem:(NSString *)text ordered:(BOOL)ordered number:(NSUInteger)number
{
  NSParagraphStyle *listStyle = _listLevel < [_listParagraphStyles count] ?
    [_listParagraphStyles objectAtIndex:_listLevel] : _normalParagraphStyle;
  
  NSDictionary *attributes = @{
    NSFontAttributeName: _bodyFont,
    NSParagraphStyleAttributeName: listStyle
  };
  
  /* Add list marker */
  NSString *marker = ordered ? 
    [NSString stringWithFormat:@"%lu. ", (unsigned long)number] : @"• ";
  NSAttributedString *markerString = [[NSAttributedString alloc] 
                                      initWithString:marker attributes:attributes];
  [_result appendAttributedString:markerString];
  RELEASE(markerString);
  
  /* Add list item content */
  NSAttributedString *itemString = [self _parseInlineMarkdown:text
                                               withAttributes:attributes];
  [_result appendAttributedString:itemString];
  [_result appendAttributedString:[self _newlineWithParagraphStyle:listStyle]];
  
  _inList = YES;
}

- (void)_addBlockquote:(NSString *)text
{
  NSDictionary *attributes = @{
    NSFontAttributeName: _bodyFont,
    NSParagraphStyleAttributeName: _blockquoteParagraphStyle,
    NSForegroundColorAttributeName: [NSColor grayColor]
  };
  
  NSAttributedString *quoteString = [self _parseInlineMarkdown:text
                                                withAttributes:attributes];
  [_result appendAttributedString:quoteString];
  [_result appendAttributedString:[self _newlineWithParagraphStyle:_blockquoteParagraphStyle]];
}

- (void)_addHorizontalRule
{
  NSString *hrString = @"────────────────────────────────────────\n";
  NSDictionary *attributes = @{
    NSFontAttributeName: _bodyFont,
    NSParagraphStyleAttributeName: _normalParagraphStyle,
    NSForegroundColorAttributeName: [NSColor grayColor]
  };
  
  NSAttributedString *hr = [[NSAttributedString alloc] initWithString:hrString
                                                           attributes:attributes];
  [_result appendAttributedString:hr];
  RELEASE(hr);
}

- (void)_addParagraphBreak
{
  if ([_result length] > 0)
    {
      [_result appendAttributedString:[self _newlineWithParagraphStyle:_normalParagraphStyle]];
    }
}

- (void)_finalizeCodeBlock
{
  if (_codeBlockContent && [_codeBlockContent length] > 0)
    {
      /* Create a text block with rounded background and padding */
      CodeTextBlock *block = [[CodeTextBlock alloc] init];
      [block setBackgroundColor: [NSColor colorWithCalibratedWhite:0.97 alpha:1.0]];
      [block setBorderColor: [NSColor colorWithCalibratedWhite:0.85 alpha:1.0]];
      [block setCornerRadius: 6.0];
      [block setWidth: 8.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];

      NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
      [para setParagraphSpacing:8.0];
      [para setFirstLineHeadIndent:10.0];
      [para setHeadIndent:10.0];
      [para setTextBlocks:@[block]];

      NSDictionary *attributes = @{
        NSFontAttributeName: _codeFont,
        NSParagraphStyleAttributeName: para,
        NSBackgroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.0 alpha:0.0] /* handled by block */
      };

      NSAttributedString *codeString = [[NSAttributedString alloc]
                                        initWithString:_codeBlockContent
                                            attributes:attributes];
      [_result appendAttributedString:codeString];
      RELEASE(codeString);
      RELEASE(para);
      RELEASE(block);

      [_result appendAttributedString:[self _newlineWithParagraphStyle:_normalParagraphStyle]];
    }
  
  RELEASE(_codeBlockContent);
  _codeBlockContent = nil;
  RELEASE(_codeBlockLanguage);
  _codeBlockLanguage = nil;
  _inCodeBlock = NO;
}

- (void)_finalizeOpenBlocks
{
  if (_inCodeBlock)
    {
      [self _finalizeCodeBlock];
    }
}

- (NSAttributedString *)_parseInlineMarkdown:(NSString *)text
                              withAttributes:(NSDictionary *)baseAttributes
{
  NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
  NSMutableDictionary *currentAttrs = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
  
  NSUInteger length = [text length];
  NSUInteger i = 0;
  NSMutableString *buffer = [NSMutableString string];
  
  while (i < length)
    {
      unichar ch = [text characterAtIndex:i];
      
      /* Handle escape sequences */
      if (ch == '\\' && i + 1 < length)
        {
          [buffer appendFormat:@"%C", [text characterAtIndex:i + 1]];
          i += 2;
          continue;
        }
      
      /* Handle inline code */
      if (ch == '`')
        {
          /* Flush buffer with current attributes */
          if ([buffer length] > 0)
            {
              NSAttributedString *chunk = [[NSAttributedString alloc]
                                           initWithString:buffer
                                               attributes:currentAttrs];
              [result appendAttributedString:chunk];
              RELEASE(chunk);
              [buffer setString:@""];
            }
          
          /* Find closing backtick */
          NSUInteger end = i + 1;
          while (end < length && [text characterAtIndex:end] != '`')
            end++;
          
          if (end < length)
            {
              NSString *codeText = [text substringWithRange:NSMakeRange(i + 1, end - i - 1)];
              NSMutableDictionary *codeAttrs = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
              [codeAttrs setObject:_codeFont forKey:NSFontAttributeName];
              [codeAttrs setObject:[NSColor colorWithCalibratedWhite:0.90 alpha:1.0]
                            forKey:NSBackgroundColorAttributeName];
              [codeAttrs setObject:[NSColor textColor] forKey:NSForegroundColorAttributeName];

              /* Small padding via paragraph style for inline code */
              NSMutableParagraphStyle *inlinePara = [[NSMutableParagraphStyle alloc] init];
              [inlinePara setFirstLineHeadIndent:2.0];
              [inlinePara setHeadIndent:2.0];
              [codeAttrs setObject:inlinePara forKey:NSParagraphStyleAttributeName];
              RELEASE(inlinePara);

              NSAttributedString *codeChunk = [[NSAttributedString alloc]
                                               initWithString:codeText
                                                   attributes:codeAttrs];
              [result appendAttributedString:codeChunk];
              RELEASE(codeChunk);
              i = end + 1;
              continue;
            }
        }
      
      /* Handle bold (**text** or __text__) */
      if ((ch == '*' || ch == '_') && i + 1 < length && [text characterAtIndex:i + 1] == ch)
        {
          /* Flush buffer */
          if ([buffer length] > 0)
            {
              NSAttributedString *chunk = [[NSAttributedString alloc]
                                           initWithString:buffer
                                               attributes:currentAttrs];
              [result appendAttributedString:chunk];
              RELEASE(chunk);
              [buffer setString:@""];
            }
          
          /* Find closing marker */
          NSString *marker = [NSString stringWithFormat:@"%C%C", ch, ch];
          NSRange searchRange = NSMakeRange(i + 2, length - i - 2);
          NSRange closeRange = [text rangeOfString:marker options:0 range:searchRange];
          
          if (closeRange.location != NSNotFound)
            {
              NSString *boldText = [text substringWithRange:
                                    NSMakeRange(i + 2, closeRange.location - i - 2)];
              NSMutableDictionary *boldAttrs = [NSMutableDictionary dictionaryWithDictionary:currentAttrs];
              [boldAttrs setObject:_boldFont forKey:NSFontAttributeName];
              
              /* Recursively parse for nested formatting */
              NSAttributedString *boldChunk = [self _parseInlineMarkdown:boldText
                                                          withAttributes:boldAttrs];
              [result appendAttributedString:boldChunk];
              i = closeRange.location + 2;
              continue;
            }
        }
      
      /* Handle italic (*text* or _text_) */
      if (ch == '*' || ch == '_')
        {
          /* Flush buffer */
          if ([buffer length] > 0)
            {
              NSAttributedString *chunk = [[NSAttributedString alloc]
                                           initWithString:buffer
                                               attributes:currentAttrs];
              [result appendAttributedString:chunk];
              RELEASE(chunk);
              [buffer setString:@""];
            }
          
          /* Find closing marker */
          NSString *marker = [NSString stringWithFormat:@"%C", ch];
          NSRange searchRange = NSMakeRange(i + 1, length - i - 1);
          NSRange closeRange = [text rangeOfString:marker options:0 range:searchRange];
          
          if (closeRange.location != NSNotFound)
            {
              NSString *italicText = [text substringWithRange:
                                      NSMakeRange(i + 1, closeRange.location - i - 1)];
              NSMutableDictionary *italicAttrs = [NSMutableDictionary dictionaryWithDictionary:currentAttrs];
              [italicAttrs setObject:_italicFont forKey:NSFontAttributeName];
              
              /* Recursively parse for nested formatting */
              NSAttributedString *italicChunk = [self _parseInlineMarkdown:italicText
                                                            withAttributes:italicAttrs];
              [result appendAttributedString:italicChunk];
              i = closeRange.location + 1;
              continue;
            }
        }
      
      /* Handle links [text](url) */
      if (ch == '[')
        {
          NSRange closeBracket = [text rangeOfString:@"]" options:0
                                               range:NSMakeRange(i + 1, length - i - 1)];
          if (closeBracket.location != NSNotFound &&
              closeBracket.location + 1 < length &&
              [text characterAtIndex:closeBracket.location + 1] == '(')
            {
              NSRange closeParen = [text rangeOfString:@")" options:0
                                                 range:NSMakeRange(closeBracket.location + 2,
                                                                  length - closeBracket.location - 2)];
              if (closeParen.location != NSNotFound)
                {
                  /* Flush buffer */
                  if ([buffer length] > 0)
                    {
                      NSAttributedString *chunk = [[NSAttributedString alloc]
                                                   initWithString:buffer
                                                       attributes:currentAttrs];
                      [result appendAttributedString:chunk];
                      RELEASE(chunk);
                      [buffer setString:@""];
                    }
                  
                  NSString *linkText = [text substringWithRange:
                                        NSMakeRange(i + 1, closeBracket.location - i - 1)];
                  NSString *linkURL = [text substringWithRange:
                                       NSMakeRange(closeBracket.location + 2,
                                                  closeParen.location - closeBracket.location - 2)];
                  
                  NSMutableDictionary *linkAttrs = [NSMutableDictionary dictionaryWithDictionary:currentAttrs];
                  [linkAttrs setObject:[NSURL URLWithString:linkURL] forKey:NSLinkAttributeName];
                  [linkAttrs setObject:[NSColor blueColor] forKey:NSForegroundColorAttributeName];
                  [linkAttrs setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle]
                                forKey:NSUnderlineStyleAttributeName];
                  
                  NSAttributedString *linkChunk = [[NSAttributedString alloc]
                                                   initWithString:linkText
                                                       attributes:linkAttrs];
                  [result appendAttributedString:linkChunk];
                  RELEASE(linkChunk);
                  i = closeParen.location + 1;
                  continue;
                }
            }
        }
      
      /* Handle strikethrough ~~text~~ */
      if (ch == '~' && i + 1 < length && [text characterAtIndex:i + 1] == '~')
        {
          /* Flush buffer */
          if ([buffer length] > 0)
            {
              NSAttributedString *chunk = [[NSAttributedString alloc]
                                           initWithString:buffer
                                               attributes:currentAttrs];
              [result appendAttributedString:chunk];
              RELEASE(chunk);
              [buffer setString:@""];
            }
          
          NSRange closeRange = [text rangeOfString:@"~~" options:0
                                             range:NSMakeRange(i + 2, length - i - 2)];
          if (closeRange.location != NSNotFound)
            {
              NSString *strikeText = [text substringWithRange:
                                      NSMakeRange(i + 2, closeRange.location - i - 2)];
              NSMutableDictionary *strikeAttrs = [NSMutableDictionary dictionaryWithDictionary:currentAttrs];
              [strikeAttrs setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle]
                              forKey:NSStrikethroughStyleAttributeName];
              
              NSAttributedString *strikeChunk = [[NSAttributedString alloc]
                                                 initWithString:strikeText
                                                     attributes:strikeAttrs];
              [result appendAttributedString:strikeChunk];
              RELEASE(strikeChunk);
              i = closeRange.location + 2;
              continue;
            }
        }
      
      /* Regular character */
      [buffer appendFormat:@"%C", ch];
      i++;
    }
  
  /* Flush remaining buffer */
  if ([buffer length] > 0)
    {
      NSAttributedString *chunk = [[NSAttributedString alloc]
                                   initWithString:buffer
                                       attributes:currentAttrs];
      [result appendAttributedString:chunk];
      RELEASE(chunk);
    }
  
  return [result autorelease];
}

- (NSAttributedString *)_newlineWithParagraphStyle:(NSParagraphStyle *)style
{
  NSDictionary *attrs = @{
    NSParagraphStyleAttributeName: style,
    NSFontAttributeName: _bodyFont
  };
  return [[[NSAttributedString alloc] initWithString:@"\n" attributes:attrs] autorelease];
}

@end

/* Helper functions */


static BOOL isHeading(NSString *line, NSUInteger *level)
{
  NSString *trimmed = [line stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
  
  if (![trimmed hasPrefix:@"#"])
    return NO;
  
  NSUInteger count = 0;
  NSUInteger length = [trimmed length];
  
  while (count < length && count < 6 && [trimmed characterAtIndex:count] == '#')
    count++;
  
  if (count < length && [trimmed characterAtIndex:count] == ' ')
    {
      *level = count;
      return YES;
    }
  
  return NO;
}

static BOOL isListItem(NSString *line, BOOL *isOrdered, NSUInteger *number)
{
  NSString *trimmed = [line stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
  
  if ([trimmed length] < 2)
    return NO;
  
  /* Check for unordered list markers */
  unichar first = [trimmed characterAtIndex:0];
  if ((first == '-' || first == '*' || first == '+') && 
      [trimmed characterAtIndex:1] == ' ')
    {
      *isOrdered = NO;
      *number = 0;
      return YES;
    }
  
  /* Check for ordered list markers */
  if (first >= '0' && first <= '9')
    {
      NSRange dotRange = [trimmed rangeOfString:@"."];
      if (dotRange.location != NSNotFound && dotRange.location < 5)
        {
          NSString *numStr = [trimmed substringToIndex:dotRange.location];
          *number = [numStr integerValue];
          *isOrdered = YES;
          return YES;
        }
    }
  
  return NO;
}

static BOOL isHorizontalRule(NSString *line)
{
  NSString *trimmed = [line stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
  
  if ([trimmed length] < 3)
    return NO;
  
  /* Check for ---, ***, or ___ */
  unichar first = [trimmed characterAtIndex:0];
  if (first != '-' && first != '*' && first != '_')
    return NO;
  
  for (NSUInteger i = 0; i < [trimmed length]; i++)
    {
      unichar ch = [trimmed characterAtIndex:i];
      if (ch != first && ch != ' ')
        return NO;
    }
  
  /* Count non-space characters */
  NSUInteger count = 0;
  for (NSUInteger i = 0; i < [trimmed length]; i++)
    {
      if ([trimmed characterAtIndex:i] != ' ')
        count++;
    }
  
  return count >= 3;
}

static BOOL isCodeFence(NSString *line, NSString **language)
{
  NSString *trimmed = [line stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
  
  if ([trimmed length] < 3)
    return NO;
  
  if ([trimmed hasPrefix:@"```"])
    {
      if (language != NULL && [trimmed length] > 3)
        {
          *language = [[trimmed substringFromIndex:3]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
      return YES;
    }
  
  return NO;
}
