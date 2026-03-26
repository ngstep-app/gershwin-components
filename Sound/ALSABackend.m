/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ALSA Backend Implementation
 */

#import "ALSABackend.h"
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

// ALSA mixer control names we look for
static NSString *const kMasterControl = @"Master";
static NSString *const kPCMControl = @"PCM";
static NSString *const kSpeakerControl = @"Speaker";
static NSString *const kHeadphoneControl = @"Headphone";
static NSString *const kCaptureControl = @"Capture";
static NSString *const kMicControl = @"Mic";

@implementation ALSABackend

@synthesize delegate;

#pragma mark - Initialization

- (id)init
{
    self = [super init];
    if (self) {
        cachedOutputDevices = [[NSMutableArray alloc] init];
        cachedInputDevices = [[NSMutableArray alloc] init];
        cachedAlertSounds = [[NSMutableArray alloc] init];
        defaultOutput = nil;
        defaultInput = nil;
        currentAlert = nil;
        alertDevice = nil;
        cachedAlertVolume = 1.0;
        playUIEffects = YES;
        playVolumeChangeFeedback = YES;
        isMonitoringInputLevel = NO;
        inputLevelTimer = nil;
        currentOutputCard = 0;
        currentInputCard = 0;
        currentFeedbackTask = nil;
        
        // Set up file paths
        NSString *home = NSHomeDirectory();
        asoundrcPath = [[home stringByAppendingPathComponent:@".asoundrc"] retain];
        defaultsFilePath = [[home stringByAppendingPathComponent:
                            @".config/gershwin/sound-defaults.plist"] retain];
        
        [self findToolPaths];
        [self enumerateDevices];
        [self loadAlertSounds];
        [self loadDefaultDevices];
    }
    return self;
}

- (void)dealloc
{
    // Cancel any pending deferred save and flush immediately
    if (deferredSaveTimer) {
        dispatch_source_cancel(deferredSaveTimer);
        dispatch_release(deferredSaveTimer);
        deferredSaveTimer = nil;
    }
    [self savePreferences];

    [self stopInputLevelMonitoring];
    [cachedOutputDevices release];
    [cachedInputDevices release];
    [cachedAlertSounds release];
    [defaultOutput release];
    [defaultInput release];
    [currentAlert release];
    [alertDevice release];
    [amixerPath release];
    [aplayPath release];
    [arecordPath release];
    [alsactlPath release];
    [asoundrcPath release];
    [defaultsFilePath release];
    if (currentFeedbackTask && [currentFeedbackTask isRunning]) {
        [currentFeedbackTask terminate];
    }
    [currentFeedbackTask release];
    [super dealloc];
}

- (BOOL)findToolPaths
{
    // Find amixer
    NSArray *searchPaths = @[@"/usr/bin/amixer", @"/bin/amixer", 
                             @"/usr/local/bin/amixer", @"/sbin/amixer"];
    
    for (NSString *path in searchPaths) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            amixerPath = [path retain];
            break;
        }
    }
    
    // Find aplay
    searchPaths = @[@"/usr/bin/aplay", @"/bin/aplay", 
                    @"/usr/local/bin/aplay"];
    for (NSString *path in searchPaths) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            aplayPath = [path retain];
            break;
        }
    }
    
    // Find arecord
    searchPaths = @[@"/usr/bin/arecord", @"/bin/arecord", 
                    @"/usr/local/bin/arecord"];
    for (NSString *path in searchPaths) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            arecordPath = [path retain];
            break;
        }
    }
    
    // Find alsactl
    searchPaths = @[@"/usr/sbin/alsactl", @"/sbin/alsactl", 
                    @"/usr/bin/alsactl", @"/usr/local/sbin/alsactl"];
    for (NSString *path in searchPaths) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            alsactlPath = [path retain];
            break;
        }
    }
    
    return (amixerPath != nil && aplayPath != nil);
}

#pragma mark - SoundBackend Protocol - Identification

- (NSString *)backendName
{
    return @"ALSA";
}

- (NSString *)backendVersion
{
    // Get ALSA version from /proc/asound/version
    NSString *versionPath = @"/proc/asound/version";
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:versionPath 
                                                  encoding:NSUTF8StringEncoding 
                                                     error:&error];
    if (content) {
        // Parse "Advanced Linux Sound Architecture Driver Version X.X.X"
        NSRange range = [content rangeOfString:@"Version "];
        if (range.location != NSNotFound) {
            NSString *version = [content substringFromIndex:NSMaxRange(range)];
            version = [[version componentsSeparatedByString:@"."] 
                       componentsJoinedByString:@"."];
            // Trim whitespace and newlines
            version = [version stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            return version;
        }
    }
    return @"Unknown";
}

- (BOOL)isAvailable
{
    // Check if ALSA is available by looking for /proc/asound
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/proc/asound" 
                                             isDirectory:&isDir]) {
        return isDir && amixerPath != nil;
    }
    return NO;
}

#pragma mark - Device Enumeration

- (void)enumerateDevices
{
    [cachedOutputDevices removeAllObjects];
    [cachedInputDevices removeAllObjects];
    
    // Get playback devices: aplay -l
    NSString *playbackOutput = [self runCommand:aplayPath 
                                  withArguments:@[@"-l"]];
    if (playbackOutput) {
        [self parsePlaybackDevices:playbackOutput];
    }
    
    // Get capture devices: arecord -l
    NSString *captureOutput = [self runCommand:arecordPath 
                                 withArguments:@[@"-l"]];
    if (captureOutput) {
        [self parseCaptureDevices:captureOutput];
    }
    
    // Update mixer controls for each device
    for (AudioDevice *device in cachedOutputDevices) {
        NSDictionary *controls = [self getMixerControls:device.cardIndex];
        if (controls) {
            [self updateDeviceWithMixerControls:device controls:controls isOutput:YES];
        }
    }
    
    for (AudioDevice *device in cachedInputDevices) {
        NSDictionary *controls = [self getMixerControls:device.cardIndex];
        if (controls) {
            [self updateDeviceWithMixerControls:device controls:controls isOutput:NO];
        }
    }
}

- (void)parsePlaybackDevices:(NSString *)output
{
    // Parse output like:
    // card 0: Audio [Bose USB Audio], device 0: USB Audio [USB Audio]
    //   Subdevices: 1/1
    //   Subdevice #0: subdevice #0
    
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    
    for (NSString *line in lines) {
        if ([line hasPrefix:@"card "]) {
            AudioDevice *device = [[AudioDevice alloc] init];
            device.direction = AudioDeviceDirectionOutput;
            device.state = AudioDeviceStateAvailable;
            
            // Parse card number
            NSScanner *scanner = [NSScanner scannerWithString:line];
            [scanner scanString:@"card " intoString:nil];
            int cardNum = 0;
            [scanner scanInt:&cardNum];
            device.cardIndex = cardNum;
            
            // Parse card name (between first [ and ])
            NSRange openBracket = [line rangeOfString:@"["];
            NSRange closeBracket = [line rangeOfString:@"]"];
            if (openBracket.location != NSNotFound && 
                closeBracket.location != NSNotFound &&
                closeBracket.location > openBracket.location) {
                NSRange nameRange = NSMakeRange(openBracket.location + 1,
                    closeBracket.location - openBracket.location - 1);
                device.cardName = [line substringWithRange:nameRange];
                device.displayName = device.cardName;
            }
            
            // Parse device number
            NSRange deviceRange = [line rangeOfString:@"device "];
            if (deviceRange.location != NSNotFound) {
                NSString *devicePart = [line substringFromIndex:
                                       NSMaxRange(deviceRange)];
                device.deviceIndex = [devicePart intValue];
            }
            
            // Create identifier
            device.identifier = [NSString stringWithFormat:@"hw:%d,%d", 
                                cardNum, device.deviceIndex];
            device.name = device.identifier;
            
            // Guess device type from name
            device.type = [self guessDeviceType:device.displayName 
                                       cardName:device.cardName];
            
            // Set mixer name
            device.mixerName = [NSString stringWithFormat:@"hw:%d", cardNum];
            
            [cachedOutputDevices addObject:device];
            [device release];
        }
    }
    
    // Set first device as default if none selected
    if ([cachedOutputDevices count] > 0 && defaultOutput == nil) {
        AudioDevice *first = [cachedOutputDevices objectAtIndex:0];
        first.isDefault = YES;
        defaultOutput = [first retain];
        currentOutputCard = first.cardIndex;
    }
}

- (void)parseCaptureDevices:(NSString *)output
{
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    
    for (NSString *line in lines) {
        if ([line hasPrefix:@"card "]) {
            AudioDevice *device = [[AudioDevice alloc] init];
            device.direction = AudioDeviceDirectionInput;
            device.state = AudioDeviceStateAvailable;
            
            // Parse card number
            NSScanner *scanner = [NSScanner scannerWithString:line];
            [scanner scanString:@"card " intoString:nil];
            int cardNum = 0;
            [scanner scanInt:&cardNum];
            device.cardIndex = cardNum;
            
            // Parse card name
            NSRange openBracket = [line rangeOfString:@"["];
            NSRange closeBracket = [line rangeOfString:@"]"];
            if (openBracket.location != NSNotFound && 
                closeBracket.location != NSNotFound &&
                closeBracket.location > openBracket.location) {
                NSRange nameRange = NSMakeRange(openBracket.location + 1,
                    closeBracket.location - openBracket.location - 1);
                device.cardName = [line substringWithRange:nameRange];
                device.displayName = device.cardName;
            }
            
            // Parse device number
            NSRange deviceRange = [line rangeOfString:@"device "];
            if (deviceRange.location != NSNotFound) {
                NSString *devicePart = [line substringFromIndex:
                                       NSMaxRange(deviceRange)];
                device.deviceIndex = [devicePart intValue];
            }
            
            device.identifier = [NSString stringWithFormat:@"hw:%d,%d", 
                                cardNum, device.deviceIndex];
            device.name = device.identifier;
            device.type = AudioDeviceTypeBuiltInMicrophone;
            device.mixerName = [NSString stringWithFormat:@"hw:%d", cardNum];
            
            [cachedInputDevices addObject:device];
            [device release];
        }
    }
    
    // Set first device as default if none selected
    if ([cachedInputDevices count] > 0 && defaultInput == nil) {
        AudioDevice *first = [cachedInputDevices objectAtIndex:0];
        first.isDefault = YES;
        defaultInput = [first retain];
        currentInputCard = first.cardIndex;
    }
}

- (AudioDeviceType)guessDeviceType:(NSString *)name cardName:(NSString *)cardName
{
    NSString *lowerName = [name lowercaseString];
    NSString *lowerCard = [cardName lowercaseString];
    
    // Check for USB audio
    if ([lowerName containsString:@"usb"] || [lowerCard containsString:@"usb"]) {
        return AudioDeviceTypeUSBAudio;
    }
    
    // Check for HDMI
    if ([lowerName containsString:@"hdmi"] || [lowerCard containsString:@"hdmi"]) {
        return AudioDeviceTypeHDMI;
    }
    
    // Check for DisplayPort
    if ([lowerName containsString:@"displayport"] || [lowerName containsString:@"dp"]) {
        return AudioDeviceTypeDisplayPort;
    }
    
    // Check for Bluetooth
    if ([lowerName containsString:@"bluetooth"] || [lowerName containsString:@"bt"]) {
        return AudioDeviceTypeBluetooth;
    }
    
    // Check for headphones
    if ([lowerName containsString:@"headphone"]) {
        return AudioDeviceTypeHeadphones;
    }
    
    // Check for SPDIF/digital
    if ([lowerName containsString:@"spdif"] || [lowerName containsString:@"digital"]) {
        return AudioDeviceTypeSPDIF;
    }
    
    // Default to built-in speaker for output
    return AudioDeviceTypeBuiltInSpeaker;
}

- (void)updateDeviceWithMixerControls:(AudioDevice *)device 
                             controls:(NSDictionary *)controls 
                             isOutput:(BOOL)isOutput
{
    // Find the appropriate volume control
    NSArray *outputControls = @[kMasterControl, kPCMControl, 
                                kSpeakerControl, kHeadphoneControl];
    NSArray *inputControls = @[kCaptureControl, kMicControl];
    
    NSArray *controlsToCheck = isOutput ? outputControls : inputControls;
    
    for (NSString *controlName in controlsToCheck) {
        NSDictionary *ctrl = [controls objectForKey:controlName];
        if (ctrl) {
            AudioControl *volControl = [[AudioControl alloc] init];
            volControl.identifier = controlName;
            volControl.name = controlName;
            
            NSNumber *volNum = [ctrl objectForKey:@"volume"];
            if (volNum) {
                volControl.value = [volNum floatValue] / 100.0;
            }
            
            NSNumber *muteNum = [ctrl objectForKey:@"muted"];
            if (muteNum) {
                volControl.isMuted = [muteNum boolValue];
                volControl.hasMuteControl = YES;
            }
            
            device.volumeControl = volControl;
            [volControl release];
            break;
        }
    }
}

#pragma mark - Mixer Control

- (NSDictionary *)getMixerControls:(int)cardIndex
{
    // Run amixer to get all controls for a card
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", cardIndex],
                            @"scontrols"]];
    
    if (!output) return nil;
    
    NSMutableDictionary *controls = [NSMutableDictionary dictionary];
    
    // Parse simple control names
    // Format: Simple mixer control 'Master',0
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSRange quoteStart = [line rangeOfString:@"'"];
        if (quoteStart.location != NSNotFound) {
            NSRange quoteEnd = [line rangeOfString:@"'" 
                options:0 
                range:NSMakeRange(quoteStart.location + 1, 
                                 [line length] - quoteStart.location - 1)];
            if (quoteEnd.location != NSNotFound) {
                NSString *name = [line substringWithRange:
                    NSMakeRange(quoteStart.location + 1,
                               quoteEnd.location - quoteStart.location - 1)];
                
                // Get control details
                NSDictionary *details = [self getControlDetails:name 
                                                           card:cardIndex];
                if (details) {
                    [controls setObject:details forKey:name];
                }
            }
        }
    }
    
    return controls;
}

- (NSDictionary *)getControlDetails:(NSString *)controlName card:(int)cardIndex
{
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", cardIndex],
                            @"sget", controlName]];
    
    if (!output) return nil;
    
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    
    // Parse volume percentage
    // Look for patterns like [60%] or Playback 60 [60%]
    NSRange percentRange = [output rangeOfString:@"[" options:0];
    while (percentRange.location != NSNotFound) {
        NSRange endRange = [output rangeOfString:@"%]" 
            options:0 
            range:NSMakeRange(percentRange.location, 
                             [output length] - percentRange.location)];
        if (endRange.location != NSNotFound) {
            NSString *numStr = [output substringWithRange:
                NSMakeRange(percentRange.location + 1,
                           endRange.location - percentRange.location - 1)];
            int percent = [numStr intValue];
            [details setObject:@(percent) forKey:@"volume"];
            break;
        }
        
        NSUInteger nextStart = percentRange.location + 1;
        if (nextStart >= [output length]) break;
        percentRange = [output rangeOfString:@"[" 
            options:0 
            range:NSMakeRange(nextStart, [output length] - nextStart)];
    }
    
    // Parse mute state - look for [on] or [off]
    if ([output containsString:@"[off]"]) {
        [details setObject:@YES forKey:@"muted"];
    } else if ([output containsString:@"[on]"]) {
        [details setObject:@NO forKey:@"muted"];
    }
    
    return details;
}

- (BOOL)setMixerControl:(NSString *)control 
                  value:(NSString *)value 
                   card:(int)cardIndex
{
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", cardIndex],
                            @"sset", control, value]];
    
    return (output != nil);
}

#pragma mark - Immediate ALSA Control Switching

- (BOOL)switchALSAControlImmediately:(NSString *)controlName 
                            toValue:(NSString *)value 
                              onCard:(int)cardIndex
{
    NSLog(@"ALSABackend: switchALSAControlImmediately: %@ = %@ on card %d", 
          controlName, value, cardIndex);
    
    // Run amixer with explicit card specification for immediate switching
    NSString *cardStr = [NSString stringWithFormat:@"%d", cardIndex];
    NSArray *args = @[@"-c", cardStr, @"sset", controlName, value, @"-q"];
    
    NSString *output = [self runCommand:amixerPath withArguments:args];
    
    if (output == nil) {
        NSLog(@"ALSABackend: switchALSAControlImmediately: FAILED - amixer returned no output");
        return NO;
    }
    
    NSLog(@"ALSABackend: switchALSAControlImmediately: SUCCESS");
    NSLog(@"ALSABackend:   output: %@", output);
    
    return YES;
}

- (NSArray *)getAvailableALSAControls:(int)cardIndex
{
    NSLog(@"ALSABackend: getAvailableALSAControls: card %d", cardIndex);
    
    NSString *cardStr = [NSString stringWithFormat:@"%d", cardIndex];
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", cardStr, @"scontrols"]];
    
    if (!output) {
        NSLog(@"ALSABackend: getAvailableALSAControls: FAILED - no output from amixer");
        return nil;
    }
    
    NSMutableArray *controls = [NSMutableArray array];
    
    // Parse control names from amixer output
    // Format: Simple mixer control 'Master',0
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSRange quoteStart = [line rangeOfString:@"'"];
        if (quoteStart.location != NSNotFound) {
            NSRange quoteEnd = [line rangeOfString:@"'" 
                options:0 
                range:NSMakeRange(quoteStart.location + 1, 
                                 [line length] - quoteStart.location - 1)];
            if (quoteEnd.location != NSNotFound) {
                NSString *name = [line substringWithRange:
                    NSMakeRange(quoteStart.location + 1,
                               quoteEnd.location - quoteStart.location - 1)];
                [controls addObject:name];
                NSLog(@"ALSABackend:   found control: %@", name);
            }
        }
    }
    
    return controls;
}

- (float)parseVolumeFromMixerOutput:(NSString *)output
{
    // Look for [XX%]
    NSRange start = [output rangeOfString:@"["];
    while (start.location != NSNotFound) {
        NSRange end = [output rangeOfString:@"%]" 
            options:0 
            range:NSMakeRange(start.location, [output length] - start.location)];
        if (end.location != NSNotFound) {
            NSString *numStr = [output substringWithRange:
                NSMakeRange(start.location + 1, end.location - start.location - 1)];
            return [numStr floatValue] / 100.0;
        }
        
        NSUInteger nextStart = start.location + 1;
        if (nextStart >= [output length]) break;
        start = [output rangeOfString:@"[" 
            options:0 
            range:NSMakeRange(nextStart, [output length] - nextStart)];
    }
    return 0.0;
}

- (BOOL)parseMuteFromMixerOutput:(NSString *)output
{
    return [output containsString:@"[off]"];
}

#pragma mark - Output Device Management

- (NSArray *)outputDevices
{
    return [[cachedOutputDevices copy] autorelease];
}

- (AudioDevice *)defaultOutputDevice
{
    return [[defaultOutput retain] autorelease];
}

- (BOOL)setDefaultOutputDevice:(AudioDevice *)device
{
    NSLog(@"ALSABackend: setDefaultOutputDevice: %@", device ? device.name : @"(nil)");
    if (!device) {
        NSLog(@"ALSABackend: setDefaultOutputDevice: FAILED - device is nil");
        return NO;
    }
    
    // Update the cached default
    for (AudioDevice *dev in cachedOutputDevices) {
        dev.isDefault = [dev.identifier isEqualToString:device.identifier];
        if (dev.isDefault) {
            [defaultOutput release];
            defaultOutput = [dev retain];
            currentOutputCard = dev.cardIndex;
            NSLog(@"ALSABackend:   set card index to %d", currentOutputCard);
        }
    }
    
    // Save to configuration
    BOOL success = [self saveDefaultDevice:device isOutput:YES];
    NSLog(@"ALSABackend: setDefaultOutputDevice: %@", success ? @"SUCCESS" : @"FAILED");
    return success;
}

- (AudioDevice *)outputDeviceWithIdentifier:(NSString *)identifier
{
    for (AudioDevice *device in cachedOutputDevices) {
        if ([device.identifier isEqualToString:identifier]) {
            return device;
        }
    }
    return nil;
}

#pragma mark - Input Device Management

- (NSArray *)inputDevices
{
    return [[cachedInputDevices copy] autorelease];
}

- (AudioDevice *)defaultInputDevice
{
    return [[defaultInput retain] autorelease];
}

- (BOOL)setDefaultInputDevice:(AudioDevice *)device
{
    NSLog(@"ALSABackend: setDefaultInputDevice: %@", device ? device.name : @"(nil)");
    if (!device) {
        NSLog(@"ALSABackend: setDefaultInputDevice: FAILED - device is nil");
        return NO;
    }
    
    for (AudioDevice *dev in cachedInputDevices) {
        dev.isDefault = [dev.identifier isEqualToString:device.identifier];
        if (dev.isDefault) {
            [defaultInput release];
            defaultInput = [dev retain];
            currentInputCard = dev.cardIndex;
            NSLog(@"ALSABackend:   set card index to %d", currentInputCard);
        }
    }
    
    BOOL success = [self saveDefaultDevice:device isOutput:NO];
    NSLog(@"ALSABackend: setDefaultInputDevice: %@", success ? @"SUCCESS" : @"FAILED");
    return success;
}

- (AudioDevice *)inputDeviceWithIdentifier:(NSString *)identifier
{
    for (AudioDevice *device in cachedInputDevices) {
        if ([device.identifier isEqualToString:identifier]) {
            return device;
        }
    }
    return nil;
}

#pragma mark - Master Volume Control

- (float)outputVolume
{
    if (!defaultOutput) return 0.0;
    
    // Get current volume from mixer
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", currentOutputCard],
                            @"sget", kPCMControl]];
    
    // Fall back to Master if PCM not found
    if (!output || ![output containsString:@"Playback"]) {
        output = [self runCommand:amixerPath 
                    withArguments:@[@"-c", 
                      [NSString stringWithFormat:@"%d", currentOutputCard],
                      @"sget", kMasterControl]];
    }
    
    if (output) {
        return [self parseVolumeFromMixerOutput:output];
    }
    
    return defaultOutput.volumeControl ? defaultOutput.volumeControl.value : 0.0;
}

- (BOOL)setOutputVolume:(float)volume
{
    NSLog(@"ALSABackend: setOutputVolume: %.2f", volume);
    if (volume < 0.0) volume = 0.0;
    if (volume > 1.0) volume = 1.0;
    
    int percent = (int)(volume * 100);
    NSString *value = [NSString stringWithFormat:@"%d%%", percent];
    NSLog(@"ALSABackend:   setting to %@, card %d", value, currentOutputCard);
    
    // Try PCM first, then Master
    BOOL success = [self setMixerControl:kPCMControl 
                                   value:value 
                                    card:currentOutputCard];
    
    if (!success) {
        NSLog(@"ALSABackend:   PCM control failed, trying Master");
        success = [self setMixerControl:kMasterControl 
                                  value:value 
                                   card:currentOutputCard];
    }
    
    if (success && defaultOutput.volumeControl) {
        defaultOutput.volumeControl.value = volume;
    }
    
    NSLog(@"ALSABackend: setOutputVolume: %@", success ? @"SUCCESS" : @"FAILED");
    
    // Play feedback if enabled
    if (success && playVolumeChangeFeedback) {
        [self playVolumeFeedback];
    }
    
    return success;
}

- (BOOL)isOutputMuted
{
    if (!defaultOutput) return NO;
    
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", currentOutputCard],
                            @"sget", kPCMControl]];
    
    if (!output) {
        output = [self runCommand:amixerPath 
                    withArguments:@[@"-c", 
                      [NSString stringWithFormat:@"%d", currentOutputCard],
                      @"sget", kMasterControl]];
    }
    
    if (output) {
        return [self parseMuteFromMixerOutput:output];
    }
    
    return defaultOutput.volumeControl ? defaultOutput.volumeControl.isMuted : NO;
}

- (BOOL)setOutputMuted:(BOOL)muted
{
    NSLog(@"ALSABackend: setOutputMuted: %@", muted ? @"YES" : @"NO");
    NSString *value = muted ? @"mute" : @"unmute";
    NSLog(@"ALSABackend:   setting to %@, card %d", value, currentOutputCard);
    
    BOOL success = [self setMixerControl:kPCMControl 
                                   value:value 
                                    card:currentOutputCard];
    
    if (!success) {
        NSLog(@"ALSABackend:   PCM control failed, trying Master");
        success = [self setMixerControl:kMasterControl 
                                  value:value 
                                   card:currentOutputCard];
    }
    
    if (success && defaultOutput.volumeControl) {
        defaultOutput.volumeControl.isMuted = muted;
    }
    
    NSLog(@"ALSABackend: setOutputMuted: %@", success ? @"SUCCESS" : @"FAILED");
    return success;
}

- (float)outputBalance
{
    // ALSA doesn't have a standard balance control
    // Would need to compare left/right channel volumes
    return 0.5; // Center
}

- (BOOL)setOutputBalance:(float)balance
{
    NSLog(@"ALSABackend: setOutputBalance: %.2f", balance);
    // TODO: Implement by adjusting left/right channel volumes
    NSLog(@"ALSABackend: setOutputBalance: SUCCESS (not yet implemented)");
    return YES;
}

#pragma mark - Input Volume Control

- (float)inputVolume
{
    if (!defaultInput) return 0.0;
    
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", currentInputCard],
                            @"sget", kCaptureControl]];
    
    if (!output) {
        output = [self runCommand:amixerPath 
                    withArguments:@[@"-c", 
                      [NSString stringWithFormat:@"%d", currentInputCard],
                      @"sget", kMicControl]];
    }
    
    if (output) {
        return [self parseVolumeFromMixerOutput:output];
    }
    
    return defaultInput.volumeControl ? defaultInput.volumeControl.value : 0.0;
}

- (BOOL)setInputVolume:(float)volume
{
    NSLog(@"ALSABackend: setInputVolume: %.2f", volume);
    if (volume < 0.0) volume = 0.0;
    if (volume > 1.0) volume = 1.0;
    
    int percent = (int)(volume * 100);
    NSString *value = [NSString stringWithFormat:@"%d%%", percent];
    NSLog(@"ALSABackend:   setting to %@, card %d", value, currentInputCard);
    
    BOOL success = [self setMixerControl:kCaptureControl 
                                   value:value 
                                    card:currentInputCard];
    
    if (!success) {
        NSLog(@"ALSABackend:   Capture control failed, trying Mic");
        success = [self setMixerControl:kMicControl 
                                  value:value 
                                   card:currentInputCard];
    }
    
    if (success && defaultInput.volumeControl) {
        defaultInput.volumeControl.value = volume;
    }
    
    NSLog(@"ALSABackend: setInputVolume: %@", success ? @"SUCCESS" : @"FAILED");
    return success;
}

- (BOOL)isInputMuted
{
    if (!defaultInput) return NO;
    
    NSString *output = [self runCommand:amixerPath 
                          withArguments:@[@"-c", 
                            [NSString stringWithFormat:@"%d", currentInputCard],
                            @"sget", kCaptureControl]];
    
    if (output) {
        return [self parseMuteFromMixerOutput:output];
    }
    
    return defaultInput.volumeControl ? defaultInput.volumeControl.isMuted : NO;
}

- (BOOL)setInputMuted:(BOOL)muted
{
    NSLog(@"ALSABackend: setInputMuted: %@", muted ? @"YES" : @"NO");
    NSString *value = muted ? @"mute" : @"unmute";
    NSLog(@"ALSABackend:   setting to %@, card %d", value, currentInputCard);
    
    BOOL success = [self setMixerControl:kCaptureControl 
                                   value:value 
                                    card:currentInputCard];
    
    if (success && defaultInput.volumeControl) {
        defaultInput.volumeControl.isMuted = muted;
    }
    
    NSLog(@"ALSABackend: setInputMuted: %@", success ? @"SUCCESS" : @"FAILED");
    return success;
}

#pragma mark - Input Level Monitoring

- (float)inputLevel
{
    return [self measureInputLevel];
}

- (BOOL)startInputLevelMonitoring
{
    if (isMonitoringInputLevel) return YES;

    isMonitoringInputLevel = YES;
    inputLevelTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                             dispatch_get_main_queue());
    dispatch_source_set_timer(inputLevelTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                              100 * NSEC_PER_MSEC, 0);
    dispatch_source_set_event_handler(inputLevelTimer, ^{
        [self inputLevelTimerFired];
    });
    dispatch_resume(inputLevelTimer);

    return YES;
}

- (BOOL)stopInputLevelMonitoring
{
    if (!isMonitoringInputLevel) return YES;

    isMonitoringInputLevel = NO;
    if (inputLevelTimer) {
        dispatch_source_cancel(inputLevelTimer);
        dispatch_release(inputLevelTimer);
        inputLevelTimer = nil;
    }

    return YES;
}

- (void)inputLevelTimerFired
{
    float level = [self measureInputLevel];
    
    if ([delegate respondsToSelector:@selector(soundBackend:inputLevelDidChange:)]) {
        [delegate soundBackend:self inputLevelDidChange:level];
    }
}

- (float)measureInputLevel
{
    // This is a simplified implementation
    // A proper implementation would use ALSA's PCM capture to measure actual levels
    // For now, return a simulated value based on capture volume setting
    return 0.0;
}

#pragma mark - Device-Specific Volume Control

- (float)volumeForDevice:(AudioDevice *)device
{
    if (!device) return 0.0;
    return device.volumeControl ? device.volumeControl.value : 0.0;
}

- (BOOL)setVolume:(float)volume forDevice:(AudioDevice *)device
{
    if (!device) return NO;
    
    int percent = (int)(volume * 100);
    NSString *value = [NSString stringWithFormat:@"%d%%", percent];
    NSString *controlName = device.volumeControl ? 
                            device.volumeControl.identifier : kPCMControl;
    
    BOOL success = [self setMixerControl:controlName 
                                   value:value 
                                    card:device.cardIndex];
    
    if (success && device.volumeControl) {
        device.volumeControl.value = volume;
    }
    
    return success;
}

- (BOOL)isMutedForDevice:(AudioDevice *)device
{
    if (!device) return NO;
    return device.volumeControl ? device.volumeControl.isMuted : NO;
}

- (BOOL)setMuted:(BOOL)muted forDevice:(AudioDevice *)device
{
    if (!device) return NO;
    
    NSString *value = muted ? @"mute" : @"unmute";
    NSString *controlName = device.volumeControl ? 
                            device.volumeControl.identifier : kPCMControl;
    
    BOOL success = [self setMixerControl:controlName 
                                   value:value 
                                    card:device.cardIndex];
    
    if (success && device.volumeControl) {
        device.volumeControl.isMuted = muted;
    }
    
    return success;
}

#pragma mark - Port Selection

- (BOOL)setActivePort:(AudioPort *)port forDevice:(AudioDevice *)device
{
    if (!port || !device) return NO;
    
    // Update cached state
    for (AudioPort *p in device.ports) {
        p.isActive = [p.identifier isEqualToString:port.identifier];
    }
    device.activePort = port;
    
    // ALSA doesn't have a standard way to switch ports
    // This would be hardware/driver specific
    return YES;
}

#pragma mark - Alert Sounds

- (void)loadAlertSounds
{
    [cachedAlertSounds removeAllObjects];

    // Only search Library/Sounds directories (system, local, network, and user)
    NSMutableArray *searchDirs = [NSMutableArray array];
    [searchDirs addObject:@"/System/Library/Sounds"];
    [searchDirs addObject:@"/Local/Library/Sounds"];
    [searchDirs addObject:@"/Network/Library/Sounds"];
    [searchDirs addObject:[self userAlertSoundDirectory]];

    NSArray *extensions = @[@"aiff", @"aif", @"wav", @"au", @"snd"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *userDir = [self userAlertSoundDirectory];

    for (NSString *dir in searchDirs) {
        if (![fm fileExistsAtPath:dir]) continue;

        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];

        if (!files) {
            NSLog(@"ALSABackend: loadAlertSounds: could not scan %@", dir);
            continue;
        }

        for (NSString *file in files) {
            NSString *ext = [[file pathExtension] lowercaseString];
            if ([extensions containsObject:ext]) {
                AlertSound *sound = [[AlertSound alloc] init];
                sound.name = [file stringByDeletingPathExtension];
                sound.displayName = sound.name;
                sound.path = [dir stringByAppendingPathComponent:file];
                sound.isSystemSound = ![dir isEqualToString:userDir];

                [cachedAlertSounds addObject:sound];
                [sound release];
            }
        }
    }

    // Sort by name
    [cachedAlertSounds sortUsingComparator:^NSComparisonResult(AlertSound *a, AlertSound *b) {
        return [a.displayName compare:b.displayName];
    }];

    NSLog(@"ALSABackend: loadAlertSounds: found %lu alert sounds",
          (unsigned long)[cachedAlertSounds count]);

    // Set first sound as current if none selected
    if (currentAlert == nil && [cachedAlertSounds count] > 0) {
        currentAlert = [[cachedAlertSounds objectAtIndex:0] retain];
    }
}

- (NSString *)alertSoundDirectory
{
    return @"/System/Library/Sounds";
}

- (NSString *)userAlertSoundDirectory
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Sounds"];
}

- (NSArray *)availableAlertSounds
{
    return [[cachedAlertSounds copy] autorelease];
}

- (AlertSound *)currentAlertSound
{
    return [[currentAlert retain] autorelease];
}

- (BOOL)setCurrentAlertSound:(AlertSound *)sound
{
    if (!sound) return NO;

    [currentAlert release];
    currentAlert = [sound retain];

    // Coalesce and defer save so it doesn't block the UI
    [self deferSavePreferences];

    return YES;
}

- (float)alertVolume
{
    return cachedAlertVolume;
}

- (BOOL)setAlertVolume:(float)volume
{
    if (volume < 0.0) volume = 0.0;
    if (volume > 1.0) volume = 1.0;

    cachedAlertVolume = volume;
    [self deferSavePreferences];

    return YES;
}

- (BOOL)playAlertSound:(AlertSound *)sound
{
    NSLog(@"ALSABackend: playAlertSound: called");
    NSLog(@"ALSABackend:   sound = %@, name = %@, path = %@", 
          sound, sound.name, sound.path);
    
    if (!sound) {
        NSLog(@"ALSABackend:   sound is nil, calling NSBeep()");
        // Play system beep
        NSBeep();
        return YES;
    }
    
    if (sound.path && [[NSFileManager defaultManager] fileExistsAtPath:sound.path]) {
        // Use aplay to play the sound
        // Use plughw: instead of hw: to allow concurrent access via dmix
        NSString *device = defaultOutput ?
                          [NSString stringWithFormat:@"plughw:%d", currentOutputCard] :
                          @"default";
        
        NSLog(@"ALSABackend:   playing file: %@", sound.path);
        NSLog(@"ALSABackend:   using device: %@, aplayPath: %@", device, aplayPath);
        
        // Run aplay in background
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:aplayPath];
        [task setArguments:@[@"-D", device, @"-q", sound.path]];

        @try {
            [task launch];
            NSLog(@"ALSABackend:   aplay launched successfully");
        } @catch (NSException *e) {
            NSLog(@"ALSABackend:   Failed to play sound: %@", e);
            [task release];
            NSBeep();
            return NO;
        }

        // Track the task so it can be terminated if needed
        [currentFeedbackTask release];
        currentFeedbackTask = task;
        return YES;
    }
    
    NSLog(@"ALSABackend:   no valid path, falling back to NSBeep()");
    // Fall back to system beep
    NSBeep();
    return YES;
}

- (AudioDevice *)alertSoundDevice
{
    return alertDevice ?: defaultOutput;
}

- (BOOL)setAlertSoundDevice:(AudioDevice *)device
{
    [alertDevice release];
    alertDevice = [device retain];
    [self deferSavePreferences];
    return YES;
}

#pragma mark - Sound Effects Settings

- (BOOL)playUserInterfaceSoundEffects
{
    return playUIEffects;
}

- (BOOL)setPlayUserInterfaceSoundEffects:(BOOL)play
{
    playUIEffects = play;
    [self deferSavePreferences];
    return YES;
}

- (BOOL)playFeedbackWhenVolumeIsChanged
{
    return playVolumeChangeFeedback;
}

- (BOOL)setPlayFeedbackWhenVolumeIsChanged:(BOOL)play
{
    playVolumeChangeFeedback = play;
    [self deferSavePreferences];
    return YES;
}

- (void)playVolumeFeedback
{
    // Terminate any previous feedback sound to prevent process pile-up
    if (currentFeedbackTask && [currentFeedbackTask isRunning]) {
        [currentFeedbackTask terminate];
    }
    [currentFeedbackTask release];
    currentFeedbackTask = nil;

    // Play a short blip sound to indicate volume change
    if (currentAlert && currentAlert.path) {
        [self playAlertSound:currentAlert];
    } else {
        NSBeep();
    }
}

#pragma mark - Default Device Persistence

- (void)loadDefaultDevices
{
    // Load from user preferences
    NSString *configDir = [[defaultsFilePath stringByDeletingLastPathComponent] 
                           stringByExpandingTildeInPath];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:configDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:configDir 
                                  withIntermediateDirectories:YES 
                                                   attributes:nil 
                                                        error:nil];
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:defaultsFilePath]) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:defaultsFilePath];
        if (prefs) {
            NSString *outputId = [prefs objectForKey:@"defaultOutput"];
            NSString *inputId = [prefs objectForKey:@"defaultInput"];
            NSString *alertId = [prefs objectForKey:@"alertDevice"];
            NSString *alertSoundName = [prefs objectForKey:@"alertSound"];
            NSNumber *alertVol = [prefs objectForKey:@"alertVolume"];
            NSNumber *uiEffects = [prefs objectForKey:@"playUIEffects"];
            NSNumber *volFeedback = [prefs objectForKey:@"playVolumeFeedback"];
            
            if (outputId) {
                AudioDevice *dev = [self outputDeviceWithIdentifier:outputId];
                if (dev) {
                    [self setDefaultOutputDevice:dev];
                }
            }
            
            if (inputId) {
                AudioDevice *dev = [self inputDeviceWithIdentifier:inputId];
                if (dev) {
                    [self setDefaultInputDevice:dev];
                }
            }
            
            if (alertId) {
                alertDevice = [[self outputDeviceWithIdentifier:alertId] retain];
            }
            
            if (alertSoundName) {
                for (AlertSound *sound in cachedAlertSounds) {
                    if ([sound.name isEqualToString:alertSoundName]) {
                        [currentAlert release];
                        currentAlert = [sound retain];
                        break;
                    }
                }
            }
            
            if (alertVol) {
                cachedAlertVolume = [alertVol floatValue];
            }
            
            if (uiEffects) {
                playUIEffects = [uiEffects boolValue];
            }
            
            if (volFeedback) {
                playVolumeChangeFeedback = [volFeedback boolValue];
            }
        }
    }
}

- (BOOL)saveDefaultDevice:(AudioDevice *)device isOutput:(BOOL)isOutput
{
    // Update .asoundrc for ALSA default device
    NSString *asoundrc = [self buildAsoundrcContent];
    NSError *error = nil;
    
    [asoundrc writeToFile:asoundrcPath 
               atomically:YES 
                 encoding:NSUTF8StringEncoding 
                    error:&error];
    
    if (error) {
        NSLog(@"Failed to write .asoundrc: %@", error);
    }
    
    // Save to our preferences file
    return [self savePreferences];
}

#pragma mark - Immediate Device Switching

- (BOOL)forceImmediateOutputDeviceSwitch:(AudioDevice *)device
{
    if (!device) {
        NSLog(@"ALSABackend: forceImmediateOutputDeviceSwitch: FAILED - device is nil");
        return NO;
    }
    
    NSLog(@"ALSABackend: forceImmediateOutputDeviceSwitch: %@ (card %d, device %d)", 
          device.name, device.cardIndex, device.deviceIndex);
    
    // Step 1: Unmute the destination device if possible
    NSArray *volumeControls = @[kMasterControl, kPCMControl, kSpeakerControl, kHeadphoneControl];
    for (NSString *controlName in volumeControls) {
        if ([self setMixerControl:controlName 
                            value:@"unmute" 
                             card:device.cardIndex]) {
            NSLog(@"ALSABackend:   unmuted %@", controlName);
            break;
        }
    }
    
    // Step 2: Silence other output devices to force switching
    NSLog(@"ALSABackend:   silencing other output devices...");
    for (AudioDevice *otherDevice in cachedOutputDevices) {
        if (otherDevice.cardIndex != device.cardIndex) {
            NSLog(@"ALSABackend:   muting card %d", otherDevice.cardIndex);
            [self setMixerControl:kMasterControl 
                            value:@"mute" 
                             card:otherDevice.cardIndex];
            [self setMixerControl:kPCMControl 
                            value:@"mute" 
                             card:otherDevice.cardIndex];
        }
    }
    
    // Step 4: Update default device settings
    [self setDefaultOutputDevice:device];
    
    NSLog(@"ALSABackend: forceImmediateOutputDeviceSwitch: SUCCESS");
    return YES;
}

- (BOOL)forceImmediateInputDeviceSwitch:(AudioDevice *)device
{
    if (!device) {
        NSLog(@"ALSABackend: forceImmediateInputDeviceSwitch: FAILED - device is nil");
        return NO;
    }
    
    NSLog(@"ALSABackend: forceImmediateInputDeviceSwitch: %@ (card %d, device %d)", 
          device.name, device.cardIndex, device.deviceIndex);
    
    // Step 1: Enable the destination device input
    NSArray *inputControls = @[kCaptureControl, kMicControl];
    for (NSString *controlName in inputControls) {
        if ([self setMixerControl:controlName 
                            value:@"cap" 
                             card:device.cardIndex]) {
            NSLog(@"ALSABackend:   enabled capture on %@", controlName);
            break;
        }
    }
    
    // Step 2: Disable input capture on other devices
    NSLog(@"ALSABackend:   disabling capture on other input devices...");
    for (AudioDevice *otherDevice in cachedInputDevices) {
        if (otherDevice.cardIndex != device.cardIndex) {
            NSLog(@"ALSABackend:   disabling capture on card %d", otherDevice.cardIndex);
            [self setMixerControl:kCaptureControl 
                            value:@"nocap" 
                             card:otherDevice.cardIndex];
            [self setMixerControl:kMicControl 
                            value:@"nocap" 
                             card:otherDevice.cardIndex];
        }
    }
    
    // Step 3: Update default device settings
    [self setDefaultInputDevice:device];
    
    NSLog(@"ALSABackend: forceImmediateInputDeviceSwitch: SUCCESS");
    return YES;
}

- (void)deferSavePreferences
{
    // Cancel any previously scheduled save, then schedule a new one.
    // This coalesces rapid changes (e.g. clicking through sounds quickly)
    // into a single disk write after activity settles.
    //
    // Uses dispatch timer instead of performSelector:afterDelay: because
    // this method is called from a GCD queue (backendQueue) which does not
    // run an NSRunLoop, so performSelector:afterDelay: would never fire.
    if (deferredSaveTimer) {
        dispatch_source_cancel(deferredSaveTimer);
        dispatch_release(deferredSaveTimer);
        deferredSaveTimer = nil;
    }

    deferredSaveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                               dispatch_get_main_queue());
    dispatch_source_set_timer(deferredSaveTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(deferredSaveTimer, ^{
        [self savePreferences];
        dispatch_source_cancel(deferredSaveTimer);
        dispatch_release(deferredSaveTimer);
        deferredSaveTimer = nil;
    });
    dispatch_resume(deferredSaveTimer);
}

- (BOOL)savePreferences
{
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    
    if (defaultOutput) {
        [prefs setObject:defaultOutput.identifier forKey:@"defaultOutput"];
    }
    if (defaultInput) {
        [prefs setObject:defaultInput.identifier forKey:@"defaultInput"];
    }
    if (alertDevice) {
        [prefs setObject:alertDevice.identifier forKey:@"alertDevice"];
    }
    if (currentAlert) {
        [prefs setObject:currentAlert.name forKey:@"alertSound"];
    }
    [prefs setObject:@(cachedAlertVolume) forKey:@"alertVolume"];
    [prefs setObject:@(playUIEffects) forKey:@"playUIEffects"];
    [prefs setObject:@(playVolumeChangeFeedback) forKey:@"playVolumeFeedback"];
    
    NSString *configDir = [defaultsFilePath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:configDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:configDir 
                                  withIntermediateDirectories:YES 
                                                   attributes:nil 
                                                        error:nil];
    }
    
    return [prefs writeToFile:defaultsFilePath atomically:YES];
}

- (NSString *)buildAsoundrcContent
{
    NSMutableString *content = [NSMutableString string];
    
    [content appendString:@"# ALSA configuration\n"];
    [content appendString:@"# Generated by Sound Preferences\n\n"];
    
    if (defaultOutput) {
        [content appendFormat:@"pcm.!default {\n"];
        [content appendFormat:@"    type hw\n"];
        [content appendFormat:@"    card %d\n", defaultOutput.cardIndex];
        [content appendFormat:@"    device %d\n", defaultOutput.deviceIndex];
        [content appendFormat:@"}\n\n"];
        
        [content appendFormat:@"ctl.!default {\n"];
        [content appendFormat:@"    type hw\n"];
        [content appendFormat:@"    card %d\n", defaultOutput.cardIndex];
        [content appendFormat:@"}\n"];
    }
    
    return content;
}

#pragma mark - Refresh

- (void)refresh
{
    [self enumerateDevices];
    
    if ([delegate respondsToSelector:@selector(soundBackend:didUpdateOutputDevices:)]) {
        [delegate soundBackend:self didUpdateOutputDevices:cachedOutputDevices];
    }
    
    if ([delegate respondsToSelector:@selector(soundBackend:didUpdateInputDevices:)]) {
        [delegate soundBackend:self didUpdateInputDevices:cachedInputDevices];
    }
}

#pragma mark - Helper Methods

- (NSString *)runCommand:(NSString *)command withArguments:(NSArray *)args
{
    if (!command) return nil;

    // Wrap in @autoreleasepool to ensure NSPipe file handles and other
    // temporary objects are released promptly.  Without this, objects
    // created on GCD queue threads (which lack an automatic autorelease
    // pool drain) accumulate and leak file descriptors, eventually
    // hitting the "Too many open files" limit.
    NSString *result = nil;
    @autoreleasepool {
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe];

        [task setLaunchPath:command];
        [task setArguments:args];
        [task setStandardOutput:pipe];
        [task setStandardError:[NSPipe pipe]];

        @try {
            [task launch];
        } @catch (NSException *e) {
            NSLog(@"Failed to run command %@: %@", command, e);
            [task release];
            return nil;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];

        result = [[NSString alloc] initWithData:data
                                       encoding:NSUTF8StringEncoding];
        [task release];
    }
    return [result autorelease];
}

- (NSString *)runCommandWithPipe:(NSString *)command arguments:(NSArray *)args
{
    return [self runCommand:command withArguments:args];
}

- (void)reportErrorWithMessage:(NSString *)message
{
    NSLog(@"ALSABackend error: %@", message);
    
    if ([delegate respondsToSelector:@selector(soundBackend:didEncounterError:)]) {
        NSError *error = [NSError errorWithDomain:@"ALSABackend" 
                                             code:1 
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
        [delegate soundBackend:self didEncounterError:error];
    }
}

@end
