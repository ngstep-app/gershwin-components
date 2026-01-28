/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@protocol SIPManagerDelegate <NSObject>
@optional
- (void)callStateChanged:(NSString *)state;
- (void)registrationStateChanged:(NSString *)state;
- (void)incomingCallFrom:(NSString *)number;
- (void)sipManagerDidReceiveError:(NSString *)title message:(NSString *)message;
@end

@interface SIPManager : NSObject

@property (weak) id<SIPManagerDelegate> delegate;
@property (readonly) BOOL isRegistered;
@property (readonly) BOOL isInCall;

- (void)start;
- (void)stop;
- (void)makeCall:(NSString *)number;
- (void)hangup;
- (void)answer;
- (void)sendDTMF:(char)digit;
- (void)updateSettings;

- (void)setVolume:(double)level;
- (void)setMuted:(BOOL)muted;

- (NSArray *)availableAudioInputs;
- (NSArray *)availableAudioOutputs;

@end
