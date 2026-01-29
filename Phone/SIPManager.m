/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SIPManager.h"
#import "PreferencesController.h"

/* Workaround: On FreeBSD the system <libutil.h> declares a different hexdump
   signature which conflicts with libre's re_fmt.h declaration.
   Rename the symbol locally while including the re headers to avoid the
   conflicting prototype during compilation. */
#ifdef __FreeBSD__
#define hexdump libre_hexdump_for_freebsd_build
#endif
#import <re/re.h>
#ifdef __FreeBSD__
#undef hexdump
#endif
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
    dispatch_semaphore_t _exitSem;
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
    
    // Explicitly enter RE thread context to satisfy Libre thread checks
    re_thread_enter();

    // The handler is called in the RE thread (dedicated thread running re_main)
    switch (id) {
        case CMD_UPDATE_SETTINGS: {
            char *addr = (char *)data;

            // If the core hasn't been initialized yet, initialize it here in the RE context.
            // This avoids blocking the main thread during app startup.
            static int coreInitialized = 0;
            if (!coreInitialized) {
                // Configure SIP to use a non-privileged port to avoid EPERM
                struct config *cfg = conf_config();

                cfg->sip.local[0] = '\0'; // Let baresip pick a random high port
                
                // Initialize UA with UDP only first to narrow down EPERM issue
                // Use software name "Phone"
                int err = ua_init("Phone", YES, NO, NO);
                
                if (err == 0) {
                    coreInitialized = 1;
                    // Enable SIP trace and install handler within RE context
                    uag_enable_sip_trace(true);
                    sip_set_trace_handler(uag_sip(), sip_trace_handler_wr);
                } else {
                     NSLog(@"SIPManager: ua_init FATAL error (%d). Continuing anyway.", err);
                }

                // Load essential modules (non-blocking within RE thread)
                const char *modpath = "/usr/lib/baresip/modules";
                if (access(modpath, F_OK) == -1) modpath = "/usr/local/lib/baresip/modules";
                
                err = 0;
                err |= module_load(modpath, "g711");
                err |= module_load(modpath, "alsa");
                err |= module_load(modpath, "ice");
                err |= module_load(modpath, "srtp");
                err |= module_load(modpath, "auconv");
                err |= module_load(modpath, "auresamp");
                err |= module_load(modpath, "aufile"); 
                if (err) {
                    NSLog(@"SIPManager: some modules failed to load (path: %s)", modpath);
                }

                // Register event handler
                bevent_register(bevent_handler, (__bridge void *)self);
            }

            if (self->_ua) {
                mem_deref(self->_ua);
                self->_ua = NULL;
            }

            // Re-apply audio config in case it changed
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            struct config *cfg = conf_config();
            NSString *audioIn = [defaults stringForKey:@"AudioInput"] ?: @"alsa";
            NSString *audioOut = [defaults stringForKey:@"AudioOutput"] ?: @"alsa";

            strncpy(cfg->audio.src_mod, audioIn.UTF8String, sizeof(cfg->audio.src_mod)-1);
            strncpy(cfg->audio.play_mod, audioOut.UTF8String, sizeof(cfg->audio.play_mod)-1);
            strncpy(cfg->audio.alert_mod, audioOut.UTF8String, sizeof(cfg->audio.alert_mod)-1);

            // Set audio path to the app's Resources directory for tone files
            NSString *resourcesPath = [[NSBundle mainBundle] resourcePath];
            if (resourcesPath) {
                strncpy(cfg->audio.audio_path, resourcesPath.UTF8String, sizeof(cfg->audio.audio_path)-1);
            }

            int err2 = ua_alloc(&self->_ua, addr);
            if (err2) {
                 NSLog(@"SIPManager: ua_alloc failed (%d) for addr: %s", err2, addr);
                 [self handleError:@"Initialization Error" message:@"Failed to allocate User Agent."];
            } else {
                 self->_current_call = NULL;
                 NSLog(@"SIPManager: User agent allocated for %s, registering...", addr);

                 // Update UI that we are working on it
                 [self performSelectorOnMainThread:@selector(_notifyRegistrationStateChanged:) withObject:@"Registering..." waitUntilDone:NO];
                 
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
    
    re_thread_leave();
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

        _exitSem = dispatch_semaphore_create(0);
        
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

        // Configure SIP to use a non-privileged port to avoid EPERM
        struct config *cfg = conf_config();
        cfg->sip.local[0] = '\0'; // Let baresip pick a random high port
        
        // Initialize baresip core
        err = baresip_init(cfg);
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
        NSString *audioIn = [defaults stringForKey:@"AudioInput"] ?: @"alsa";
        NSString *audioOut = [defaults stringForKey:@"AudioOutput"] ?: @"alsa";
        strncpy(cfg->audio.src_mod, audioIn.UTF8String, sizeof(cfg->audio.src_mod)-1);
        strncpy(cfg->audio.play_mod, audioOut.UTF8String, sizeof(cfg->audio.play_mod)-1);
        strncpy(cfg->audio.alert_mod, audioOut.UTF8String, sizeof(cfg->audio.alert_mod)-1);

        // Note: baresip core initialization (ua_init and module loading)
        // may perform blocking operations; we defer core initialization
        // until the RE thread is running and execute it in a RE-safe context
        // (handled in CMD_UPDATE_SETTINGS via mqueue_handler) to avoid
        // blocking the main GUI thread.
        
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
    
    // Cleanup in RE context
    bevent_unregister(bevent_handler);
    ua_close();
    module_app_unload();
    baresip_close();
    libre_close();

    if (self->_mq) {
        mem_deref(self->_mq);
        self->_mq = NULL;
    }
    
    re_thread_leave();
    if (self->_exitSem) dispatch_semaphore_signal(self->_exitSem);
    
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
} 

- (void)stop {
    NSLog(@"SIPManager: Stopping...");

    if (self->_re_thread_ready) {
        re_thread_enter();
        re_cancel();
        re_thread_leave();
        
        // Wait for cleanup to finish in the RE thread
        if (self->_exitSem) {
            dispatch_semaphore_wait(self->_exitSem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        }
    }
    NSLog(@"SIPManager: Stopped");
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
    
    if (username.length > 0 && server.length > 0) {
        NSString *addr;
        
        // Use standard Baresip account string format with explicit parameters and display name.
        // Some servers like Asterisk prefer auth_user and password as parameters.
        if (password.length > 0) {
            addr = [NSString stringWithFormat:@"\"%@\" <sip:%@@%@>;auth_user=%@;password=%@;transport=udp", username, username, server, username, password];
        } else {
            addr = [NSString stringWithFormat:@"<sip:%@@%@>;transport=udp", username, server];
        }
        
        if (laddr) {
            addr = [addr stringByAppendingFormat:@";laddr=%@", laddr];
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
    NSDictionary *info = @{@"title": title ?: @"Error", @"message": message ?: @""};
    [self performSelectorOnMainThread:@selector(_dispatchError:) withObject:info waitUntilDone:NO];
}

- (void)_dispatchError:(NSDictionary *)info {
    NSString *title = info[@"title"];
    NSString *message = info[@"message"];
    if ([self.delegate respondsToSelector:@selector(sipManagerDidReceiveError:message:)]) {
        [self.delegate sipManagerDidReceiveError:title message:message];
    }
}

- (void)_notifyRegistrationStateChanged:(NSString *)state {
    if ([self.delegate respondsToSelector:@selector(registrationStateChanged:)]) {
        [self.delegate registrationStateChanged:state];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SIPRegistrationStateChanged" object:state];
}

- (void)_notifyCallStateChanged:(NSString *)state {
    if ([self.delegate respondsToSelector:@selector(callStateChanged:)]) {
        [self.delegate callStateChanged:state];
    }
}

- (void)_notifyIncomingCall:(NSString *)number {
    if ([self.delegate respondsToSelector:@selector(incomingCallFrom:)]) {
        [self.delegate incomingCallFrom:number];
    }
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

    NSString *stateStr = nil;
    
    switch (ev) {
        case BEVENT_REGISTERING:
            stateStr = @"Registering...";
            break;
        case BEVENT_REGISTER_OK:
            stateStr = @"Registered";
            self.isRegistered = YES;
            self->_retryCount = 0;
            self->_hasPromptedRegistrationFailure = NO;
            break;
        case BEVENT_REGISTER_FAIL: {
            stateStr = @"Registration Failed";
            self.isRegistered = NO;
            
            NSString *errorDetail = @"";
            if (reason) {
                errorDetail = [NSString stringWithFormat:@"%d %@", scode, reason];
            } else if (text) {
                errorDetail = text;
            }

            if (!self->_hasPromptedRegistrationFailure) {
                self->_hasPromptedRegistrationFailure = YES;
                NSString *msg = [NSString stringWithFormat:@"Failed to register. Check your credentials and server address. (Error: %@)", errorDetail];
                [self handleError:@"Registration Failed" message:msg];

                [self performSelectorOnMainThread:@selector(_openPreferences) withObject:nil waitUntilDone:NO];
            }

            if (self->_retryCount < 3) {
                self->_retryCount++;
                // I'll just use performSelector:withObject:afterDelay: which is safer and works on main thread if called from there.
                [self performSelectorOnMainThread:@selector(_scheduleRetry) withObject:nil waitUntilDone:NO];
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
            [self performSelectorOnMainThread:@selector(_notifyIncomingCall:) withObject:caller waitUntilDone:NO];
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
            // Need to invalidate timer on main thread
            [self performSelectorOnMainThread:@selector(_invalidateCallTimer) withObject:nil waitUntilDone:NO];
            stateStr = @"Connected";
            self.isInCall = YES;
            self.current_call = call;
            break;
        case BEVENT_CALL_CLOSED: {
            [self performSelectorOnMainThread:@selector(_invalidateCallTimer) withObject:nil waitUntilDone:NO];
            
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

    if (stateStr) {
        if (ev == BEVENT_REGISTER_OK || ev == BEVENT_REGISTER_FAIL || ev == BEVENT_REGISTERING || ev == BEVENT_UNREGISTERING) {
            [self performSelectorOnMainThread:@selector(_notifyRegistrationStateChanged:) withObject:stateStr waitUntilDone:NO];
        } else {
            [self performSelectorOnMainThread:@selector(_notifyCallStateChanged:) withObject:stateStr waitUntilDone:NO];
        }
    }
}

- (void)_openPreferences {
    [[PreferencesController sharedController] showWindow:nil];
}

- (void)_scheduleRetry {
    [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(retryRegistration:) userInfo:nil repeats:NO];
}

- (void)_invalidateCallTimer {
    [self->_callTimer invalidate];
    self->_callTimer = nil;
}

@end
