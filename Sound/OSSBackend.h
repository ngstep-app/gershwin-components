/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * OSS Backend for FreeBSD
 *
 * Uses the Open Sound System (OSS) API to interact with audio devices.
 * This is the native audio system on FreeBSD.
 */

#import "SoundBackend.h"

@interface OSSBackend : NSObject <SoundBackend>
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

    // Mixer file descriptor for default device
    int mixerFd;

    // Default device unit
    int defaultUnit;

    // Cached volume for mute/unmute
    int cachedOutputVolume;
    int cachedInputVolume;
    BOOL isOutputMutedFlag;
    BOOL isInputMutedFlag;

    // Preferences file path
    NSString *defaultsFilePath;
}

@property (assign) id<SoundBackendDelegate> delegate;

// Initialization
- (BOOL)openMixer;
- (BOOL)openMixerForUnit:(int)unit;
- (void)closeMixer;

// Device enumeration
- (void)enumerateDevices;
- (void)parseSndstat;
- (AudioDeviceType)guessDeviceType:(NSString *)name description:(NSString *)desc;

// Mixer control via ioctl
- (int)getMixerChannel:(int)channel;
- (BOOL)setMixerChannel:(int)channel value:(int)value;
- (int)getMixerChannelForUnit:(int)unit channel:(int)channel;
- (BOOL)setMixerChannelForUnit:(int)unit channel:(int)channel value:(int)value;
- (int)getMixerDevMask;
- (int)getMixerRecMask;
- (BOOL)setMixerRecMask:(int)mask;

// Default device management
- (void)loadDefaultDevices;
- (int)getDefaultUnit;
- (BOOL)setDefaultUnit:(int)unit;
- (BOOL)savePreferences;

// Alert sounds
- (void)loadAlertSounds;
- (NSString *)alertSoundDirectory;
- (NSString *)userAlertSoundDirectory;

// Input level monitoring
- (void)inputLevelTimerFired:(NSTimer *)timer;
- (float)measureInputLevel;

// Sound playback
- (BOOL)playSoundFile:(NSString *)path onUnit:(int)unit;

// Helper methods
- (NSString *)runCommand:(NSString *)command withArguments:(NSArray *)args;
- (void)reportErrorWithMessage:(NSString *)message;

@end
