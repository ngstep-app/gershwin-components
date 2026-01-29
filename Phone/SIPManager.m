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
#include <pthread.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>

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
    BOOL _hasPromptedRegistrationFailure;
    volatile int _re_thread_ready; // 0 = not ready, 1 = ready
} 
@property (readwrite) BOOL isRegistered;
@property (readwrite) BOOL isInCall;
@property (assign) struct call *current_call;
- (void)handleError:(NSString *)title message:(NSString *)message;
- (void)callDidTimeout:(NSTimer *)timer;
- (void)retryRegistration:(NSTimer *)timer;
// Helper to push to mqueue only when RE thread is ready
- (void)pushCommandWhenREReady:(int)cmd data:(void *)data;
@end

static void bevent_handler(enum bevent_ev ev, struct bevent *event, void *arg);

// Forward-declare the SIP trace handler so it can be referenced from earlier code
static void sip_trace_handler_wr(bool tx, enum sip_transp tp, const struct sa *src, const struct sa *dst, const uint8_t *pkt, size_t len, void *arg);

static void mqueue_handler(int id, void *data, void *arg) {
    SIPManager *self = (__bridge SIPManager *)arg;

    // The handler is called in the RE thread (dedicated thread running re_main), so no need to check re_thread_check
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

            // Set audio path to the app's Resources directory for tone files
            NSString *resourcesPath = [[NSBundle mainBundle] resourcePath];
            if (resourcesPath) {
                strncpy(cfg->audio.audio_path, resourcesPath.UTF8String, sizeof(cfg->audio.audio_path)-1);
            }

            // Load aufile module for tone playback
            module_load("/usr/local/lib/baresip/modules", "aufile");

            int err = ua_alloc(&self->_ua, addr);
            if (err) {
                 NSLog(@"SIPManager: ua_alloc failed (%d) for addr: %s", err, addr);
                 [self handleError:@"Initialization Error" message:@"Failed to allocate User Agent."];
            } else {
                 NSLog(@"SIPManager: User agent allocated for %s, registering...", addr);
                 // Ensure the SIP trace handler is set from RE context so packet dumps are printed immediately
                 sip_set_trace_handler(uag_sip(), sip_trace_handler_wr);
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
            if (self->_ua) {
                ua_register(self->_ua);
            }
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

static pthread_mutex_t sip_log_lock = PTHREAD_MUTEX_INITIALIZER;

static void baresip_log_handler(uint32_t level, const char *msg) {
    if (!msg) return;
    size_t mlen = strlen(msg);

    // Prepare NSString for NSLog (trim trailing newline for readability)
    NSString *s = [[NSString alloc] initWithBytes:msg length:mlen encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithBytes:msg length:mlen encoding:NSASCIIStringEncoding];
    if (s && [s hasSuffix:@"\n"]) {
        s = [s substringToIndex:s.length - 1];
    }

    // Write directly to stderr for immediate terminal output
    const char *prefix = "Baresip: ";
    size_t prefix_len = strlen(prefix);
    size_t out_len = prefix_len + mlen + 1; // +1 for ensured newline
    char *out = malloc(out_len + 1);
    if (out) {
        memcpy(out, prefix, prefix_len);
        memcpy(out + prefix_len, msg, mlen);
        if (mlen == 0 || msg[mlen-1] != '\n') {
            out[prefix_len + mlen] = '\n';
            out[prefix_len + mlen + 1] = '\0';
        } else {
            out[prefix_len + mlen] = '\0';
        }

        pthread_mutex_lock(&sip_log_lock);
        fwrite(out, 1, strlen(out), stderr);
        fflush(stderr);
        pthread_mutex_unlock(&sip_log_lock);

        free(out);
    }

    // Also send to NSLog for consistency with existing logging
    if (s) NSLog(@"Baresip: %@", s);
} 

static struct log baresip_log = {
    .le = { NULL, NULL, NULL, NULL },
    .h = baresip_log_handler
};

static void re_dbg_handler(int level, const char *p, size_t len, void *arg) {
    if (!p || len == 0) return;

    NSString *s = [[NSString alloc] initWithBytes:p length:len encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithBytes:p length:len encoding:NSASCIIStringEncoding];
    if (s && [s hasSuffix:@"\n"]) {
        s = [s substringToIndex:s.length - 1];
    }

    const char *prefix = "Libre: ";
    size_t prefix_len = strlen(prefix);
    size_t out_len = prefix_len + len + 1;
    char *out = malloc(out_len + 1);
    if (out) {
        memcpy(out, prefix, prefix_len);
        memcpy(out + prefix_len, p, len);
        if (p[len-1] != '\n') {
            out[prefix_len + len] = '\n';
            out[prefix_len + len + 1] = '\0';
        } else {
            out[prefix_len + len] = '\0';
        }

        pthread_mutex_lock(&sip_log_lock);
        fwrite(out, 1, strlen(out), stderr);
        fflush(stderr);
        pthread_mutex_unlock(&sip_log_lock);

        free(out);
    }

    if (s) NSLog(@"Libre: %@", s);
}

// Custom SIP trace handler that writes the raw SIP packet to stderr immediately
static void sip_trace_handler_wr(bool tx, enum sip_transp tp, const struct sa *src, const struct sa *dst, const uint8_t *pkt, size_t len, void *arg) {
    (void)tp; (void)src; (void)dst; (void)arg; (void)tx;
    if (!pkt || len == 0) return;

    bool entered = false;
    if (re_thread_check(false) != 0) {
        re_thread_enter();
        entered = true;
    }

    pthread_mutex_lock(&sip_log_lock);
    fwrite("SIPTrace: ", 1, 10, stderr);
    fwrite(pkt, 1, len, stderr);
    if (pkt[len-1] != '\n') fputc('\n', stderr);
    fflush(stderr);
    pthread_mutex_unlock(&sip_log_lock);

    if (entered) {
        re_thread_leave();
    }
}  

- (instancetype)init {
    self = [super init];
    if (self) {
        int err;

        // Make stdout and stderr unbuffered for immediate log output
        setbuf(stdout, NULL);
        setbuf(stderr, NULL);
        
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
        // Override the default trace handler to ensure immediate stderr output
        sip_set_trace_handler(uag_sip(), sip_trace_handler_wr);

        // Load modules - at minimum g711 and alsa
        err = module_load("/usr/local/lib/baresip/modules", "g711");
        err |= module_load("/usr/local/lib/baresip/modules", "alsa");
        err |= module_load("/usr/local/lib/baresip/modules", "ice"); 
        err |= module_load("/usr/local/lib/baresip/modules", "srtp");
        err |= module_load("/usr/local/lib/baresip/modules", "auconv");
        err |= module_load("/usr/local/lib/baresip/modules", "auresamp");
        err |= module_load("/usr/local/lib/baresip/modules", "aufile");

        if (err) {
             NSLog(@"SIPManager: some modules failed to load (ignoring)");
        }

        // Register event handler
        bevent_register(bevent_handler, (__bridge void *)self);
        
        re_thread_leave();
    }
    return self;
}

static void *re_main_thread_func(void *arg) {
    SIPManager *self = (__bridge SIPManager *)arg;
    re_thread_enter();
    // Mark RE thread as ready for mqueue operations
    self->_re_thread_ready = 1;
    re_main(NULL);
    re_thread_leave();
    return NULL;
}

- (void)start {
    // Start baresip loop in a dedicated thread (not GCD) so the RE thread identity is stable
    pthread_t re_thread;
    int err = pthread_create(&re_thread, NULL, re_main_thread_func, (__bridge void *)self);
    if (err == 0) {
        pthread_detach(re_thread);
    } else {
        NSLog(@"SIPManager: Failed to create RE thread (%d)", err);
    }

    // Give the RE thread a short moment to come up, then apply settings that will push work to the RE thread
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self updateSettings];
    });
} 

- (void)stop {
    NSLog(@"SIPManager: Stopping...");

    // Perform cleanup on a background thread and wait for completion to avoid use-after-free
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        re_thread_enter();
        bevent_unregister(bevent_handler);
        ua_close();
        module_app_unload();

        // Stop the loop
        re_cancel();

        baresip_close();
        libre_close();

        // Free the mqueue inside a RE context
        if (_mq) {
            mem_deref(_mq);
            _mq = NULL;
        }

        re_thread_leave();
        NSLog(@"SIPManager: Stopped");

        dispatch_semaphore_signal(sem);
    });

    // Wait synchronously for cleanup to finish. Safe to call from main thread.
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

- (void)dealloc {
    [self stop];
}

- (void)updateSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *username = [defaults stringForKey:@"SIPUsername"];
    NSString *password = [defaults stringForKey:@"SIPPassword"];
    NSString *server = [defaults stringForKey:@"SIPServer"];
    
    NSLog(@"SIPManager: Updating settings: user=%@ server=%@", username, server);
    
    // Determine local address for the server
    NSString *laddr = nil;
    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) == 0) {
        struct in_addr server_addr;
        if (inet_pton(AF_INET, server.UTF8String, &server_addr) == 1) {
            uint32_t server_net = ntohl(server_addr.s_addr) & 0xFFFFFF00; // assume /24 subnet
            for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
                if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_INET) {
                    struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
                    uint32_t local_net = ntohl(sa->sin_addr.s_addr) & 0xFFFFFF00;
                    if (local_net == server_net) {
                        char ip[INET_ADDRSTRLEN];
                        inet_ntop(AF_INET, &sa->sin_addr, ip, INET_ADDRSTRLEN);
                        laddr = [NSString stringWithUTF8String:ip];
                        break;
                    }
                }
            }
        }
        freeifaddrs(ifaddr);
    }
    if (!laddr) {
        // Fallback to a default if no matching interface found
        laddr = @"192.168.0.187";
    }
    
    if (username.length > 0 && server.length > 0) {
        NSString *addr;
        if (password.length > 0) {
            addr = [NSString stringWithFormat:@"<sip:%@@%@>;laddr=%@;auth_pass=%@", username, server, laddr, password];
        } else {
            addr = [NSString stringWithFormat:@"<sip:%@@%@>;laddr=%@", username, server, laddr];
        }
        
        char *c_addr = mem_alloc(addr.length + 1, NULL);
        if (c_addr) {
            strcpy(c_addr, addr.UTF8String);
            if (_mq) {
                [self pushCommandWhenREReady:CMD_UPDATE_SETTINGS data:c_addr];
            } else {
                mem_deref(c_addr);
                NSLog(@"SIPManager: mqueue not available, cannot update settings");
                [self handleError:@"Internal Error" message:@"SIP queue unavailable."];
            }
        }
    } else {
        self.isRegistered = NO;
        if ([self.delegate respondsToSelector:@selector(registrationStateChanged:)]) {
            [self.delegate registrationStateChanged:@"Not Configured"];
        }
    }
} 

- (void)makeCall:(NSString *)number {
    if (!_ua || number.length == 0) return;

    if (!self.isRegistered) {
        [self handleError:@"Not Registered" message:@"Cannot make call: SIP registration failed."];
        return;
    }

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
        if (_mq) {
            [self pushCommandWhenREReady:CMD_CONNECT data:c_uri];
        } else {
            mem_deref(c_uri);
            NSLog(@"SIPManager: mqueue not available, cannot make call");
            [self handleError:@"Internal Error" message:@"SIP queue unavailable."];
        }
    }

    // Start a 60-second timeout for the call to be established
    _callTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 
                                                 target:self 
                                               selector:@selector(callDidTimeout:) 
                                               userInfo:nil 
                                                repeats:NO];
} 

- (void)callDidTimeout:(NSTimer *)timer {
    if (self.current_call && !self.isInCall) {
        NSLog(@"SIPManager: Call timeout - hanging up");
        [self hangup];
        [self handleError:@"Call Timeout" message:@"The call could not be established within 60 seconds."];
    }
}

- (void)setVolume:(double)level {
    if (_mq) {
        mqueue_push(_mq, CMD_VOLUME, (void *)(uintptr_t)(int)level);
    } else {
        NSLog(@"SIPManager: mqueue not available, cannot set volume");
    }
}  

- (void)setMuted:(BOOL)muted {
    if (_mq) {
        mqueue_push(_mq, CMD_MUTE, (void *)(uintptr_t)(muted ? 1 : 0));
    } else {
        NSLog(@"SIPManager: mqueue not available, cannot set mute");
    }
}  

- (void)retryRegistration:(NSTimer *)timer {
    if (!self.isRegistered) {
        NSLog(@"SIPManager: Retrying registration...");
        if (_mq) [self pushCommandWhenREReady:CMD_REGISTER data:NULL];
        else NSLog(@"SIPManager: mqueue not available, cannot retry registration");
    }
}

- (void)pushCommandWhenREReady:(int)cmd data:(void *)data {
    if (self->_re_thread_ready && _mq) {
        mqueue_push(_mq, cmd, data);
        return;
    }

    // Otherwise, schedule to retry in a short while. Ownership of `data` remains with caller; if we end up
    // not being able to push it later, we'll free it with mem_deref to avoid leaks.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (self->_re_thread_ready && self->_mq) {
            mqueue_push(self->_mq, cmd, data);
        } else {
            if (data) mem_deref(data);
        }
    });
}

- (void)handleError:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(sipManagerDidReceiveError:message:)]) {
            [self.delegate sipManagerDidReceiveError:title message:message];
        }
    });
}

- (void)hangup {
    if (_mq) mqueue_push(_mq, CMD_HANGUP, NULL);
    else NSLog(@"SIPManager: mqueue not available, cannot hangup");
}  

- (void)answer {
    _wasAnswered = YES;
    if (_mq) mqueue_push(_mq, CMD_ANSWER, NULL);
    else NSLog(@"SIPManager: mqueue not available, cannot answer");
}

- (void)sendDTMF:(char)digit {
    if (_mq) mqueue_push(_mq, CMD_DTMF, (void *)(uintptr_t)digit);
    else NSLog(@"SIPManager: mqueue not available, cannot send DTMF");
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

    bool entered = false;
    if (re_thread_check(false) != 0) {
        re_thread_enter();
        entered = true;
    }

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

    if (entered) {
        re_thread_leave();
    }

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
                // Reset the first-failure prompt so user will be notified again on future failures
                self->_hasPromptedRegistrationFailure = NO;
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

                // If we haven't already notified the user, do it immediately on the FIRST failure
                if (!self->_hasPromptedRegistrationFailure) {
                    self->_hasPromptedRegistrationFailure = YES;
                    NSString *msg = [NSString stringWithFormat:@"Failed to register. Check your credentials and server address. (Error: %@)", errorDetail];
                    [self handleError:@"Registration Failed" message:msg];

                    // Open Preferences to let the user fix configuration
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                        NSLog(@"SIPManager: Opening Preferences due to registration failure (first attempt)");
                        [[PreferencesController sharedController] showWindow:nil];
                    });
                }

                // Still attempt retries a few times in background
                if (self->_retryCount < 3) {
                    self->_retryCount++;
                    [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(retryRegistration:) userInfo:nil repeats:NO];
                    stateStr = [NSString stringWithFormat:@"Registration failed (%@), retrying (%ld)...", errorDetail, (long)self->_retryCount];
                } else {
                    NSString *msg = [NSString stringWithFormat:@"Failed to register after multiple attempts. Check your credentials and server address. (Error: %@)", errorDetail];
                    [self handleError:@"Registration Failed" message:msg];
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
