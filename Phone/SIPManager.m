/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SIPManager.h"
#import "PreferencesController.h"
#import <re/re.h>
#define DEBUG_MODULE "Phone"
#define DEBUG_LEVEL 7
#import <re/re_dbg.h>
#import <baresip.h>

enum {
    CMD_UPDATE_SETTINGS,
    CMD_CONNECT,
    CMD_ANSWER,
    CMD_HANGUP,
    CMD_DTMF,
    CMD_REGISTER,
    CMD_MUTE,
    CMD_VOLUME
};

@interface SIPManager () {
@public
    struct ua *_ua;
    struct call *_current_call;
    struct mqueue *_mq;
    NSTimer *_callTimer;
    BOOL _wasAnswered;
    NSInteger _retryCount;
    BOOL _isOutgoing;
}
@property (readwrite) BOOL isRegistered;
@property (readwrite) BOOL isInCall;
@property (assign) struct call *current_call;
- (void)handleError:(NSString *)title message:(NSString *)message;
- (void)callDidTimeout:(NSTimer *)timer;
- (void)retryRegistration:(NSTimer *)timer;
@end

static void bevent_handler(enum bevent_ev ev, struct bevent *event, void *arg);

static void mqueue_handler(int id, void *data, void *arg) {
    SIPManager *self = (__bridge SIPManager *)arg;
    /* Already running in RE thread context */
    switch (id) {
        case CMD_UPDATE_SETTINGS: {
            char *addr = (char *)data;
            if (self->_ua) {
                // If we are calling ua functions from another thread (even via mqueue if it's not the re thread),
                // we should be careful. But mqueue_handler is called by the RE thread.
                mem_deref(self->_ua);
                self->_ua = NULL;
            }
            
            // Re-apply audio config in case it changed
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            struct config *cfg = conf_config();
            NSString *audioIn = [defaults stringForKey:@"AudioInput"] ?: @"alsa";
            NSString *audioOut = [defaults stringForKey:@"AudioOutput"] ?: @"alsa";
            
            // Check if modules were previously loaded or if they need to be loaded
            // Baresip might require modules to be loaded for these to work
            
            strncpy(cfg->audio.src_mod, audioIn.UTF8String, sizeof(cfg->audio.src_mod)-1);
            strncpy(cfg->audio.play_mod, audioOut.UTF8String, sizeof(cfg->audio.play_mod)-1);
            strncpy(cfg->audio.alert_mod, audioOut.UTF8String, sizeof(cfg->audio.alert_mod)-1);

            int err = ua_alloc(&self->_ua, addr);
            if (err) {
                 NSLog(@"SIPManager: ua_alloc failed (%d) for addr: %s", err, addr);
                 [self handleError:@"Initialization Error" message:@"Failed to allocate User Agent."];
            } else {
                 NSLog(@"SIPManager: User agent allocated for %s, registering...", addr);
                 ua_register(self->_ua);
            }
            mem_deref(addr);
            break;
        }
        case CMD_CONNECT: {
            char *uri = (char *)data;
            struct call *call = NULL;
            int err = ua_connect(self->_ua, &call, NULL, uri, VIDMODE_OFF);
            if (err) {
                 [self handleError:@"Call Failed" message:[NSString stringWithFormat:@"Could not connect (Error %d)", err]];
            } else {
                 self->_current_call = call;
            }
            mem_deref(uri);
            break;
        }
        case CMD_ANSWER:
            if (self->_current_call) call_answer(self->_current_call, 200, VIDMODE_OFF);
            break;
        case CMD_HANGUP:
            if (self->_current_call) {
                call_hangup(self->_current_call, 0, NULL);
                self->_current_call = NULL;
            }
            break;
        case CMD_DTMF: {
            uintptr_t digit = (uintptr_t)data;
            if (self->_current_call) call_send_digit(self->_current_call, (char)digit);
            break;
        }
        case CMD_REGISTER:
            if (self->_ua) ua_register(self->_ua);
            break;
        case CMD_VOLUME: {
            // Volume control not found in this Baresip version's audio.h
            break;
        }
        case CMD_MUTE: {
            BOOL mute = (BOOL)(uintptr_t)data;
            if (self->_current_call) {
                struct audio *au = call_audio(self->_current_call);
                if (au) audio_mute(au, mute);
            }
            break;
        }
    }
}

@implementation SIPManager

@synthesize current_call = _current_call;

static void baresip_log_handler(uint32_t level, const char *msg) {
    if (!msg) return;
    // Trim newline if present
    NSString *s = [[NSString alloc] initWithBytes:msg length:strlen(msg) encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithBytes:msg length:strlen(msg) encoding:NSASCIIStringEncoding];
    if (s && [s hasSuffix:@"\n"]) {
        s = [s substringToIndex:s.length - 1];
    }
    if (s) NSLog(@"Baresip: %@", s);
    fflush(stderr);
}

static struct log baresip_log = {
    .le = { NULL, NULL, NULL, NULL },
    .h = baresip_log_handler
};

static void re_dbg_handler(int level, const char *p, size_t len, void *arg) {
    if (!p) return;
    NSString *s = [[NSString alloc] initWithBytes:p length:len encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithBytes:p length:len encoding:NSASCIIStringEncoding];
    if (s && [s hasSuffix:@"\n"]) {
        s = [s substringToIndex:s.length - 1];
    }
    if (s) NSLog(@"Libre: %@", s);
    fflush(stderr);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        int err;
        
        // Initialize debugging
        dbg_init(DBG_DEBUG, DBG_ALL);
        dbg_handler_set(re_dbg_handler, NULL);
        
        // Initialize libre
        err = libre_init();
        if (err) {
            NSLog(@"SIPManager: libre_init failed (%d)", err);
            return nil;
        }

        // Register this thread
        re_thread_enter();

        // Initialize mqueue for thread-safe operations
        err = mqueue_alloc(&_mq, mqueue_handler, (__bridge void *)self);
        if (err) {
            NSLog(@"SIPManager: mqueue_alloc failed (%d)", err);
        }

        // Load configuration
        err = conf_configure();
        if (err) {
            NSLog(@"SIPManager: conf_configure failed (%d) - ignoring", err);
        }
        
        // Initialize baresip core
        err = baresip_init(conf_config());
        if (err) {
            NSLog(@"SIPManager: baresip_init failed (%d)", err);
        }
        
        // Register log handler to redirect baresip logs to NSLog
        log_register_handler(&baresip_log);
        
        // Set baresip log level to debug
        log_level_set(LEVEL_DEBUG);
        log_enable_debug(true);
        
        // Update audio config from preferences
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        struct config *cfg = conf_config();
        NSString *audioIn = [defaults stringForKey:@"AudioInput"] ?: @"alsa";
        NSString *audioOut = [defaults stringForKey:@"AudioOutput"] ?: @"alsa";
        strncpy(cfg->audio.src_mod, audioIn.UTF8String, sizeof(cfg->audio.src_mod)-1);
        strncpy(cfg->audio.play_mod, audioOut.UTF8String, sizeof(cfg->audio.play_mod)-1);
        strncpy(cfg->audio.alert_mod, audioOut.UTF8String, sizeof(cfg->audio.alert_mod)-1);

        // Initialize baresip unit agent
        err = ua_init("Phone", YES, YES, YES);
        if (err) {
            NSLog(@"SIPManager: ua_init failed (%d)", err);
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(sipManagerDidReceiveError:message:)]) {
                    [self.delegate sipManagerDidReceiveError:@"SIP Initialization Failed" 
                                                   message:[NSString stringWithFormat:@"Baresip UA failed to initialize (Error %d). Check network components.", err]];
                }
            });
        }
        
        // Enable SIP trace for network debugging
        uag_enable_sip_trace(true);

        // Load modules - at minimum g711 and alsa
        err = module_load("/usr/local/lib/baresip/modules", "g711");
        err |= module_load("/usr/local/lib/baresip/modules", "alsa");
        err |= module_load("/usr/local/lib/baresip/modules", "ice"); 
        err |= module_load("/usr/local/lib/baresip/modules", "srtp");
        err |= module_load("/usr/local/lib/baresip/modules", "auconv");
        err |= module_load("/usr/local/lib/baresip/modules", "auresamp");

        if (err) {
             NSLog(@"SIPManager: some modules failed to load (ignoring)");
        }

        // Register event handler
        bevent_register(bevent_handler, (__bridge void *)self);
        
        re_thread_leave();
    }
    return self;
}

- (void)start {
    // Make stdout and stderr unbuffered for immediate log output
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);
    
    [self updateSettings];
    
    // Start baresip loop in a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Set this thread as the RE thread
        re_thread_enter();
        re_main(NULL);
        re_thread_leave();
    });
}

- (void)stop {
    NSLog(@"SIPManager: Stopping...");
    // Run stop logic in a background thread if it's called from main
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        re_thread_enter();
        bevent_unregister(bevent_handler);
        ua_close();
        module_app_unload();
        
        // Stop the loop
        re_cancel();
        
        baresip_close();
        libre_close();
        re_thread_leave();
        NSLog(@"SIPManager: Stopped");
    });
    
    if (_mq) {
        re_thread_enter();
        mem_deref(_mq);
        _mq = NULL;
        re_thread_leave();
    }
}

- (void)dealloc {
    [self stop];
}

- (void)updateSettings {
    re_thread_enter();
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *username = [defaults stringForKey:@"SIPUsername"];
    NSString *password = [defaults stringForKey:@"SIPPassword"];
    NSString *server = [defaults stringForKey:@"SIPServer"];
    
    NSLog(@"SIPManager: Updating settings: user=%@ server=%@", username, server);
    
    if (username.length > 0 && server.length > 0) {
        NSString *addr;
        if (password.length > 0) {
            addr = [NSString stringWithFormat:@"<sip:%@@%@>;auth_pass=%@", username, server, password];
        } else {
            addr = [NSString stringWithFormat:@"<sip:%@@%@>", username, server];
        }
        
        char *c_addr = mem_alloc(addr.length + 1, NULL);
        if (c_addr) {
            strcpy(c_addr, addr.UTF8String);
            mqueue_push(_mq, CMD_UPDATE_SETTINGS, c_addr);
        }
    } else {
        self.isRegistered = NO;
        if ([self.delegate respondsToSelector:@selector(registrationStateChanged:)]) {
            [self.delegate registrationStateChanged:@"Not Configured"];
        }
    }
    re_thread_leave();
}

- (void)makeCall:(NSString *)number {
    if (!_ua || number.length == 0) return;
    
    re_thread_enter();
    
    // Ensure number is in sip: format
    NSString *uri = number;
    if (![number hasPrefix:@"sip:"]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *server = [defaults stringForKey:@"SIPServer"];
        uri = [NSString stringWithFormat:@"sip:%@@%@", number, server];
    }
    
    // Cancel any existing call timer
    [_callTimer invalidate];
    
    _isOutgoing = YES;
    _wasAnswered = NO;

    char *c_uri = mem_alloc(uri.length + 1, NULL);
    if (c_uri) {
        strcpy(c_uri, uri.UTF8String);
        mqueue_push(_mq, CMD_CONNECT, c_uri);
    }

    // Start a 60-second timeout for the call to be established
    _callTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 
                                                 target:self 
                                               selector:@selector(callDidTimeout:) 
                                               userInfo:nil 
                                                repeats:NO];
    re_thread_leave();
}

- (void)callDidTimeout:(NSTimer *)timer {
    if (self.current_call && !self.isInCall) {
        NSLog(@"SIPManager: Call timeout - hanging up");
        [self hangup];
        [self handleError:@"Call Timeout" message:@"The call could not be established within 60 seconds."];
    }
}

- (void)setVolume:(double)level {
    re_thread_enter();
    mqueue_push(_mq, CMD_VOLUME, (void *)(uintptr_t)(int)level);
    re_thread_leave();
}

- (void)setMuted:(BOOL)muted {
    re_thread_enter();
    mqueue_push(_mq, CMD_MUTE, (void *)(uintptr_t)(muted ? 1 : 0));
    re_thread_leave();
}

- (void)retryRegistration:(NSTimer *)timer {
    if (!self.isRegistered) {
        NSLog(@"SIPManager: Retrying registration...");
        re_thread_enter();
        mqueue_push(_mq, CMD_REGISTER, NULL);
        re_thread_leave();
    }
}

- (void)handleError:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(sipManagerDidReceiveError:message:)]) {
            [self.delegate sipManagerDidReceiveError:title message:message];
        }
    });
}

- (void)hangup {
    re_thread_enter();
    mqueue_push(_mq, CMD_HANGUP, NULL);
    re_thread_leave();
}

- (void)answer {
    _wasAnswered = YES;
    re_thread_enter();
    mqueue_push(_mq, CMD_ANSWER, NULL);
    re_thread_leave();
}

- (void)sendDTMF:(char)digit {
    re_thread_enter();
    mqueue_push(_mq, CMD_DTMF, (void *)(uintptr_t)digit);
    re_thread_leave();
}

- (NSArray *)availableAudioInputs {
    // Return common drivers on Linux. 
    // In a full implementation we'd scan Baresip loaded modules.
    return @[@"alsa", @"pulse", @"jack", @"portaudio", @"nullaudio"];
}

- (NSArray *)availableAudioOutputs {
    return @[@"alsa", @"pulse", @"jack", @"portaudio", @"nullaudio"];
}

// Callbacks

static void bevent_handler(enum bevent_ev ev, struct bevent *event, void *arg) {
    SIPManager *self = (__bridge SIPManager *)arg;
    struct call *call = bevent_get_call(event);
    
    // Capture data needed from event before dispatching to main thread
    int scode = 0;
    NSString *reason = nil;
    NSString *text = nil;
    const char *peer = NULL;
    
    if (ev == BEVENT_REGISTER_FAIL) {
        const struct sip_msg *msg = bevent_get_msg(event);
        if (msg) {
            scode = msg->scode;
            reason = [[NSString alloc] initWithBytes:msg->reason.p length:msg->reason.l encoding:NSUTF8StringEncoding];
        } else {
            const char *rtxt = bevent_get_text(event);
            if (rtxt) text = [NSString stringWithUTF8String:rtxt];
        }
    } else if (ev == BEVENT_CALL_INCOMING) {
        peer = call_peeruri(call);
    }
    
    NSString *capturedPeer = peer ? [NSString stringWithUTF8String:peer] : nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *stateStr = nil;
        
        switch (ev) {
            case BEVENT_REGISTERING:
                stateStr = @"Registering...";
                break;
            case BEVENT_REGISTER_OK:
                stateStr = @"Registered";
                self.isRegistered = YES;
                self->_retryCount = 0;
                break;
            case BEVENT_REGISTER_FAIL: {
                stateStr = @"Registration Failed";
                self.isRegistered = NO;
                
                NSString *errorDetail = @"";
                if (reason) {
                    NSLog(@"SIPManager: Registration failed with status %d (%@)", scode, reason);
                    errorDetail = [NSString stringWithFormat:@"%d %@", scode, reason];
                } else if (text) {
                    errorDetail = text;
                }

                if (self->_retryCount < 3) {
                    self->_retryCount++;
                    [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(retryRegistration:) userInfo:nil repeats:NO];
                    stateStr = [NSString stringWithFormat:@"Registration failed (%@), retrying (%ld)...", errorDetail, (long)self->_retryCount];
                } else {
                    NSString *msg = [NSString stringWithFormat:@"Failed to register after multiple attempts. Check your credentials and server address. (Error: %@)", errorDetail];
                    [self handleError:@"Registration Failed" message:msg];

                    // Open Preferences to let the user fix configuration
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"SIPManager: Opening Preferences due to registration failure");
                        [[PreferencesController sharedController] showWindow:nil];
                    });
                }
                break;
            }
            case BEVENT_UNREGISTERING:
                stateStr = @"Unregistering...";
                break;
                
            case BEVENT_CALL_INCOMING: {
                self.current_call = call;
                self->_wasAnswered = NO;
                self->_isOutgoing = NO;
                stateStr = @"Incoming Call";
                NSString *caller = capturedPeer ?: @"Unknown";
                if ([self.delegate respondsToSelector:@selector(incomingCallFrom:)]) {
                    [self.delegate incomingCallFrom:caller];
                }
                break;
            }
            case BEVENT_CALL_RINGING:
                stateStr = @"Ringing...";
                break;
            case BEVENT_CALL_PROGRESS:
                stateStr = @"Calling...";
                break;
            case BEVENT_CALL_ESTABLISHED:
                self->_wasAnswered = YES;
                [self->_callTimer invalidate];
                self->_callTimer = nil;
                stateStr = @"Connected";
                self.isInCall = YES;
                self.current_call = call;
                break;
            case BEVENT_CALL_CLOSED: {
                [self->_callTimer invalidate];
                self->_callTimer = nil;
                
                if (!self->_isOutgoing && !self->_wasAnswered) {
                     [self handleError:@"Missed Call" message:@"You had an incoming call that was not answered."];
                }
                
                stateStr = @"Call Ended";
                self.isInCall = NO;
                self.current_call = NULL;
                break;
            }
            default:
                break;
        }
        
        if (stateStr && [self.delegate respondsToSelector:@selector(callStateChanged:)]) {
            [self.delegate callStateChanged:stateStr];
        }
        
        if (ev == BEVENT_REGISTER_OK || ev == BEVENT_REGISTER_FAIL) {
             if ([self.delegate respondsToSelector:@selector(registrationStateChanged:)]) {
                [self.delegate registrationStateChanged:stateStr];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SIPRegistrationStateChanged" object:stateStr];
        }
    });
}

@end
