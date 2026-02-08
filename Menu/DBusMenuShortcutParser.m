/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "DBusMenuShortcutParser.h"

@implementation DBusMenuShortcutParser

+ (NSString *)parseShortcutArray:(NSArray *)shortcutArray
{
    // Convert DBus shortcut array to string format
    // DBus shortcuts are typically nested arrays like ((Control, t)) or ((Control, Shift, x))
    if (![shortcutArray isKindOfClass:[NSArray class]] || [shortcutArray count] == 0) {
        NSDebugLog(@"DBusMenuShortcutParser: Invalid shortcut array - not array or empty");
        return nil;
    }
    
    NSDebugLog(@"DBusMenuShortcutParser: Parsing shortcut array: %@", shortcutArray);
    
    // The shortcut array might be nested - check if first element is an array
    NSArray *actualShortcut = shortcutArray;
    if ([shortcutArray count] > 0 && [[shortcutArray objectAtIndex:0] isKindOfClass:[NSArray class]]) {
        // Take the first nested array - this is the actual shortcut
        actualShortcut = [shortcutArray objectAtIndex:0];
        NSDebugLog(@"DBusMenuShortcutParser: Found nested shortcut array: %@", actualShortcut);
    }
    
    NSMutableArray *components = [NSMutableArray array];
    NSString *key = nil;
    
    for (id item in actualShortcut) {
        if ([item isKindOfClass:[NSString class]]) {
            NSString *component = (NSString *)item;
            NSDebugLog(@"DBusMenuShortcutParser: Processing shortcut component: '%@'", component);
            
            // Check if it's a modifier - map modifiers (case-insensitive)
            NSString *lowerComponent = [component lowercaseString];
            if ([lowerComponent isEqualToString:@"control_l"] || [lowerComponent isEqualToString:@"control_r"] || 
                [lowerComponent isEqualToString:@"control"] || [lowerComponent isEqualToString:@"ctrl"]) {
                [components addObject:@"ctrl"]; // Control key
                NSDebugLog(@"DBusMenuShortcutParser: Added Control modifier");
            } else if ([lowerComponent isEqualToString:@"shift_l"] || [lowerComponent isEqualToString:@"shift_r"] || 
                       [lowerComponent isEqualToString:@"shift"]) {
                [components addObject:@"shift"];
                NSDebugLog(@"DBusMenuShortcutParser: Added Shift modifier");
            } else if ([lowerComponent isEqualToString:@"alt_l"] || [lowerComponent isEqualToString:@"alt_r"] || 
                       [lowerComponent isEqualToString:@"alt"]) {
                [components addObject:@"alt"];
                NSDebugLog(@"DBusMenuShortcutParser: Added Alt modifier");
            } else if ([lowerComponent isEqualToString:@"meta_l"] || [lowerComponent isEqualToString:@"meta_r"] || 
                       [lowerComponent isEqualToString:@"super_l"] || [lowerComponent isEqualToString:@"super_r"] ||
                       [lowerComponent isEqualToString:@"meta"] || [lowerComponent isEqualToString:@"super"]) {
                [components addObject:@"cmd"]; // Command/Super key
                NSDebugLog(@"DBusMenuShortcutParser: Added Command modifier");
            } else {
                // This should be the key
                key = [self normalizeKeyName:component];
                NSDebugLog(@"DBusMenuShortcutParser: Found key: '%@' -> '%@'", component, key);
            }
        } else if ([item isKindOfClass:[NSNumber class]]) {
            // Handle numeric keysyms
            NSNumber *keysym = (NSNumber *)item;
            key = [self normalizeKeyName:[keysym stringValue]];
            NSDebugLog(@"DBusMenuShortcutParser: Found numeric key: %@ -> '%@'", keysym, key);
        }
    }
    
    NSString *result = nil;
    if (key && [components count] > 0) {
        result = [NSString stringWithFormat:@"%@+%@", [components componentsJoinedByString:@"+"], key];
    } else if (key) {
        result = key;
    }
    
    NSDebugLog(@"DBusMenuShortcutParser: Shortcut parsing result: '%@'", result);
    return result;
}

+ (NSDictionary *)parseKeyCombo:(NSString *)keyCombo
{
    if (!keyCombo || [keyCombo length] == 0) {
        return @{@"key": @"", @"modifiers": @0};
    }
    
    NSDebugLog(@"DBusMenuShortcutParser: Parsing key combo: '%@'", keyCombo);
    
    NSArray *parts = [keyCombo componentsSeparatedByString:@"+"];
    NSUInteger modifierMask = 0;
    NSString *key = @"";
    
    for (NSString *part in parts) {
        NSString *cleanPart = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSDebugLog(@"DBusMenuShortcutParser: Processing key combo part: '%@'", cleanPart);
        
        // Case-insensitive modifier matching for Canonical AppMenu compatibility
        NSString *lowerPart = [cleanPart lowercaseString];
        if ([lowerPart isEqualToString:@"cmd"] || [lowerPart isEqualToString:@"command"]) {
            modifierMask |= NSCommandKeyMask;
            NSDebugLog(@"DBusMenuShortcutParser: Added Command modifier mask");
        } else if ([lowerPart isEqualToString:@"shift"]) {
            modifierMask |= NSShiftKeyMask;
            NSDebugLog(@"DBusMenuShortcutParser: Added Shift modifier mask");
        } else if ([lowerPart isEqualToString:@"alt"] || [lowerPart isEqualToString:@"option"]) {
            modifierMask |= NSAlternateKeyMask;
            NSDebugLog(@"DBusMenuShortcutParser: Added Alt modifier mask");
        } else if ([lowerPart isEqualToString:@"ctrl"] || [lowerPart isEqualToString:@"control"]) {
            modifierMask |= NSControlKeyMask;
            NSDebugLog(@"DBusMenuShortcutParser: Added Control modifier mask");
        } else {
            // This should be the key
            key = [self normalizeKeyName:cleanPart];
            NSDebugLog(@"DBusMenuShortcutParser: Set key equivalent: '%@' (from '%@')", key, cleanPart);
        }
    }
    
    NSDebugLog(@"DBusMenuShortcutParser: Key combo result - key: '%@', modifiers: %lu", key, (unsigned long)modifierMask);
    return @{@"key": key, @"modifiers": @(modifierMask)};
}

+ (NSString *)normalizeKeyName:(NSString *)keyName
{
    if (!keyName || [keyName length] == 0) {
        return @"";
    }
    
    // Convert common key names to single characters for NSMenuItem
    NSString *normalized = [keyName lowercaseString];
    
    // Handle special keys
    if ([normalized isEqualToString:@"return"] || [normalized isEqualToString:@"enter"]) {
        return @"\r";
    } else if ([normalized isEqualToString:@"tab"]) {
        return @"\t";
    } else if ([normalized isEqualToString:@"space"]) {
        return @" ";
    } else if ([normalized isEqualToString:@"escape"] || [normalized isEqualToString:@"esc"]) {
        return @"\033";
    } else if ([normalized isEqualToString:@"backspace"]) {
        return @"\b";
    } else if ([normalized isEqualToString:@"delete"]) {
        return @"\177";
    } else if ([normalized hasPrefix:@"f"] && [normalized length] <= 3) {
        // Function keys - return as is for now, NSMenuItem will handle
        return normalized;
    } else if ([normalized length] == 1) {
        // Single character - use lowercase
        return normalized;
    }
    
    // For other keys, try to extract the first character
    if ([normalized length] > 1) {
        return [normalized substringToIndex:1];
    }
    
    return @"";
}

+ (NSString *)modifierMaskToString:(NSUInteger)modifierMask
{
    NSMutableArray *modifiers = [NSMutableArray array];
    
    if (modifierMask & NSCommandKeyMask) {
        [modifiers addObject:@"⌘"];
    }
    if (modifierMask & NSShiftKeyMask) {
        [modifiers addObject:@"⇧"];
    }
    if (modifierMask & NSAlternateKeyMask) {
        [modifiers addObject:@"⌥"];
    }
    if (modifierMask & NSControlKeyMask) {
        [modifiers addObject:@"⌃"];
    }
    
    return [modifiers componentsJoinedByString:@""];
}

+ (NSDictionary *)testParseKeyCombo:(NSString *)keyCombo
{
    return [self parseKeyCombo:keyCombo];
}

@end
