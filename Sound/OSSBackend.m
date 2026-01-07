/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * OSS Backend Implementation (Stub for FreeBSD support)
 *
 * This is a placeholder for future FreeBSD OSS support.
 * On FreeBSD, OSS provides audio device control through:
 *   - /dev/mixer for volume control
 *   - /dev/dsp for audio playback/capture
 *   - sysctl for device enumeration
 *
 * Key ioctls for mixer control:
 *   - SOUND_MIXER_READ_VOLUME
 *   - SOUND_MIXER_WRITE_VOLUME
 *   - SOUND_MIXER_READ_DEVMASK
 *   - SOUND_MIXER_READ_RECMASK
 */

#import "OSSBackend.h"
#import <AppKit/AppKit.h>

// OSS mixer device channels (from sys/soundcard.h on FreeBSD)
// These would be used when implementing the actual backend
/*
#define SOUND_MIXER_VOLUME      0
#define SOUND_MIXER_BASS        1
#define SOUND_MIXER_TREBLE      2
#define SOUND_MIXER_SYNTH       3
#define SOUND_MIXER_PCM         4
#define SOUND_MIXER_SPEAKER     5
#define SOUND_MIXER_LINE        6
#define SOUND_MIXER_MIC         7
#define SOUND_MIXER_CD          8
#define SOUND_MIXER_IMIX        9
#define SOUND_MIXER_ALTPCM      10
#define SOUND_MIXER_RECLEV      11
#define SOUND_MIXER_IGAIN       12
#define SOUND_MIXER_OGAIN       13
*/

@implementation OSSBackend

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
        cachedAlertVolume = 1.0;
        playUIEffects = YES;
        playVolumeChangeFeedback = YES;
        mixerFd = -1;
        mixerDevice = @"/dev/mixer";
    }
    return self;
}

- (void)dealloc
{
    [cachedOutputDevices release];
    [cachedInputDevices release];
    [cachedAlertSounds release];
    [defaultOutput release];
    [defaultInput release];
    [currentAlert release];
    [super dealloc];
}

#pragma mark - SoundBackend Protocol - Identification

- (NSString *)backendName
{
    return @"OSS";
}

- (NSString *)backendVersion
{
    // Would query OSS version via ioctl
    return @"4.0";
}

- (BOOL)isAvailable
{
    // Check if /dev/mixer exists (FreeBSD OSS)
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/dev/mixer"];
}

#pragma mark - Output Device Management

- (NSArray *)outputDevices
{
    // TODO: Enumerate OSS output devices
    // On FreeBSD, use sysctl hw.snd.default_unit and dev.pcm.X
    return [[cachedOutputDevices copy] autorelease];
}

- (AudioDevice *)defaultOutputDevice
{
    return [[defaultOutput retain] autorelease];
}

- (BOOL)setDefaultOutputDevice:(AudioDevice *)device
{
    // TODO: Set via sysctl hw.snd.default_unit
    return NO;
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
    return NO;
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

#pragma mark - Volume Control

- (float)outputVolume
{
    // TODO: Read from /dev/mixer using SOUND_MIXER_READ_VOLUME
    return 0.0;
}

- (BOOL)setOutputVolume:(float)volume
{
    // TODO: Write to /dev/mixer using SOUND_MIXER_WRITE_VOLUME
    return NO;
}

- (BOOL)isOutputMuted
{
    return NO;
}

- (BOOL)setOutputMuted:(BOOL)muted
{
    return NO;
}

- (float)outputBalance
{
    return 0.5;
}

- (BOOL)setOutputBalance:(float)balance
{
    return NO;
}

- (float)inputVolume
{
    return 0.0;
}

- (BOOL)setInputVolume:(float)volume
{
    return NO;
}

- (BOOL)isInputMuted
{
    return NO;
}

- (BOOL)setInputMuted:(BOOL)muted
{
    return NO;
}

#pragma mark - Input Level Monitoring

- (float)inputLevel
{
    return 0.0;
}

- (BOOL)startInputLevelMonitoring
{
    return NO;
}

- (BOOL)stopInputLevelMonitoring
{
    return YES;
}

#pragma mark - Device-Specific Volume

- (float)volumeForDevice:(AudioDevice *)device
{
    return 0.0;
}

- (BOOL)setVolume:(float)volume forDevice:(AudioDevice *)device
{
    return NO;
}

- (BOOL)isMutedForDevice:(AudioDevice *)device
{
    return NO;
}

- (BOOL)setMuted:(BOOL)muted forDevice:(AudioDevice *)device
{
    return NO;
}

#pragma mark - Port Selection

- (BOOL)setActivePort:(AudioPort *)port forDevice:(AudioDevice *)device
{
    return NO;
}

#pragma mark - Alert Sounds

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
    return NO;
}

- (float)alertVolume
{
    return cachedAlertVolume;
}

- (BOOL)setAlertVolume:(float)volume
{
    cachedAlertVolume = volume;
    return YES;
}

- (BOOL)playAlertSound:(AlertSound *)sound
{
    NSBeep();
    return YES;
}

- (AudioDevice *)alertSoundDevice
{
    return defaultOutput;
}

- (BOOL)setAlertSoundDevice:(AudioDevice *)device
{
    return NO;
}

#pragma mark - Sound Effects Settings

- (BOOL)playUserInterfaceSoundEffects
{
    return playUIEffects;
}

- (BOOL)setPlayUserInterfaceSoundEffects:(BOOL)play
{
    playUIEffects = play;
    return YES;
}

- (BOOL)playFeedbackWhenVolumeIsChanged
{
    return playVolumeChangeFeedback;
}

- (BOOL)setPlayFeedbackWhenVolumeIsChanged:(BOOL)play
{
    playVolumeChangeFeedback = play;
    return YES;
}

#pragma mark - Refresh

- (void)refresh
{
    // TODO: Re-enumerate devices
}

#pragma mark - Immediate Device Switching

- (BOOL)forceImmediateOutputDeviceSwitch:(AudioDevice *)device
{
    // TODO: Implement for OSS on FreeBSD
    return NO;
}

- (BOOL)forceImmediateInputDeviceSwitch:(AudioDevice *)device
{
    // TODO: Implement for OSS on FreeBSD
    return NO;
}

@end
