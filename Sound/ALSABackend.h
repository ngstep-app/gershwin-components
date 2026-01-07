/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ALSA Backend
 *
 * Uses amixer and aplay command-line tools to interact with ALSA.
 * This approach allows the preference pane to work without linking
 * directly against libasound, making it more portable.
 */

#import "SoundBackend.h"

@interface ALSABackend : NSObject <SoundBackend>
{
    id<SoundBackendDelegate> delegate;
    
    // Cached data
    NSMutableArray *cachedOutputDevices;
    NSMutableArray *cachedInputDevices;
    AudioDevice *defaultOutput;
    AudioDevice *defaultInput;
    
    // Alert sounds
    NSMutableArray *cachedAlertSounds;
    AlertSound *currentAlert;
    float cachedAlertVolume;
    AudioDevice *alertDevice;
    
    // Settings
    BOOL playUIEffects;
    BOOL playVolumeChangeFeedback;
    
    // Input level monitoring
    NSTimer *inputLevelTimer;
    BOOL isMonitoringInputLevel;
    
    // Tool paths
    NSString *amixerPath;
    NSString *aplayPath;
    NSString *arecordPath;
    NSString *alsactlPath;
    
    // Current card for operations
    int currentOutputCard;
    int currentInputCard;
    
    // ALSA configuration file paths
    NSString *asoundrcPath;
    NSString *defaultsFilePath;
}

@property (assign) id<SoundBackendDelegate> delegate;

// Initialization
- (BOOL)findToolPaths;

// Device enumeration
- (void)enumerateDevices;
- (void)parsePlaybackDevices:(NSString *)output;
- (void)parseCaptureDevices:(NSString *)output;
- (AudioDeviceType)guessDeviceType:(NSString *)name cardName:(NSString *)cardName;

// Mixer control
- (NSDictionary *)getMixerControls:(int)cardIndex;
- (BOOL)setMixerControl:(NSString *)control value:(NSString *)value card:(int)cardIndex;
- (float)parseVolumeFromMixerOutput:(NSString *)output;
- (BOOL)parseMuteFromMixerOutput:(NSString *)output;

// Immediate amixer control switching (forces immediate ALSA device change)
- (BOOL)switchALSAControlImmediately:(NSString *)controlName 
                                 toValue:(NSString *)value 
                                   onCard:(int)cardIndex;
- (NSArray *)getAvailableALSAControls:(int)cardIndex;

// Default device management
- (void)loadDefaultDevices;
- (BOOL)saveDefaultDevice:(AudioDevice *)device isOutput:(BOOL)isOutput;
- (NSString *)buildAsoundrcContent;

// Immediate device switching (force switch even if audio is playing)
- (BOOL)forceImmediateOutputDeviceSwitch:(AudioDevice *)device;
- (BOOL)forceImmediateInputDeviceSwitch:(AudioDevice *)device;

// Alert sounds
- (void)loadAlertSounds;
- (NSString *)alertSoundDirectory;
- (NSString *)userAlertSoundDirectory;

// Input level monitoring
- (void)inputLevelTimerFired:(NSTimer *)timer;
- (float)measureInputLevel;

// Helper methods
- (NSString *)runCommand:(NSString *)command withArguments:(NSArray *)args;
- (NSString *)runCommandWithPipe:(NSString *)command arguments:(NSArray *)args;
- (void)reportErrorWithMessage:(NSString *)message;

@end
