/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LoginWindowPAM.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

// Define PAM_XDISPLAY if not provided by system PAM headers (e.g., on FreeBSD)
#ifndef PAM_XDISPLAY
#define PAM_XDISPLAY 14
#endif

// C function for PAM conversation callback
int loginwindow_pam_conv(int num_msg, const struct pam_message **msg,
                        struct pam_response **resp, void *appdata_ptr)
{
    NSLog(@"[PAM] Conversation callback invoked with %d messages", num_msg);
    LoginWindowPAM *pamObj = (__bridge LoginWindowPAM *)appdata_ptr;
    *resp = (struct pam_response *)calloc(num_msg, sizeof(struct pam_response));
    
    if (!*resp) {
        NSLog(@"[PAM] calloc failed for pam_response");
        return PAM_BUF_ERR;
    }
    
    int result = PAM_SUCCESS;
    
    for (int i = 0; i < num_msg; i++) {
        (*resp)[i].resp = NULL;
        (*resp)[i].resp_retcode = 0;
        NSLog(@"[PAM] Message %d: style=%d, msg='%s'", i, msg[i]->msg_style, msg[i]->msg);
        switch (msg[i]->msg_style) {
            case PAM_PROMPT_ECHO_ON:
                NSLog(@"[PAM] Prompt for username");
                if ([pamObj storedUsername]) {
                    (*resp)[i].resp = strdup([[pamObj storedUsername] UTF8String]);
                    NSLog(@"[PAM] Responded with username: %@", [pamObj storedUsername]);
                } else {
                    NSLog(@"[PAM] No username stored");
                }
                break;
            case PAM_PROMPT_ECHO_OFF:
                NSLog(@"[PAM] Prompt for password");
                if ([pamObj storedPassword]) {
                    (*resp)[i].resp = strdup([[pamObj storedPassword] UTF8String]);
                    NSLog(@"[PAM] Responded with password (hidden)");
                } else {
                    NSLog(@"[PAM] No password stored");
                }
                break;
            case PAM_ERROR_MSG:
            case PAM_TEXT_INFO:
                NSLog(@"[PAM] Info/Error: %s", msg[i]->msg);
                break;
            default:
                NSLog(@"[PAM] Unknown message style: %d", msg[i]->msg_style);
                result = PAM_CONV_ERR;
                break;
        }
        if (result != PAM_SUCCESS) {
            NSLog(@"[PAM] Conversation error at message %d", i);
            break;
        }
    }
    if (result != PAM_SUCCESS) {
        for (int i = 0; i < num_msg; i++) {
            if ((*resp)[i].resp) {
                free((*resp)[i].resp);
                (*resp)[i].resp = NULL;
            }
        }
        free(*resp);
        *resp = NULL;
        NSLog(@"[PAM] Conversation failed, responses freed");
    }
    return result;
}

@implementation LoginWindowPAM

@synthesize storedUsername = _storedUsername;
@synthesize storedPassword = _storedPassword;
@synthesize lastErrorMessage = _lastErrorMessage;

- (id)init
{
    self = [super init];
    if (self) {
        pam_handle = NULL;
        pam_conversation.conv = loginwindow_pam_conv;
        pam_conversation.appdata_ptr = (__bridge void *)self;
        _storedUsername = nil;
        _storedPassword = nil;
        _lastErrorMessage = nil;
        authenticationInProgress = NO;
        NSLog(@"[PAM] LoginWindowPAM initialized");
    }
    return self;
}

- (void)dealloc
{
    NSLog(@"[PAM] Dealloc called");
    if (pam_handle) {
        pam_end(pam_handle, PAM_SUCCESS);
        pam_handle = NULL;
        NSLog(@"[PAM] pam_end called in dealloc");
    }
    [_storedUsername release];
    [_storedPassword release];
    [_lastErrorMessage release];
    [super dealloc];
}

- (BOOL)authenticateUser:(NSString *)username password:(NSString *)password
{
    NSLog(@"[PAM] Starting authentication for user: %@", username);
    if (authenticationInProgress) {
        NSLog(@"[PAM] Authentication already in progress");
        return NO;
    }
    authenticationInProgress = YES;
    [_storedUsername release];
    [_storedPassword release];
    _storedUsername = [username copy];
    _storedPassword = [password copy];
    NSLog(@"[PAM] Credentials stored: username=%@ password=%@", _storedUsername, _storedPassword ? @"(hidden)" : @"(nil)");
    
    // Check if PAM configuration file exists
    NSLog(@"[PAM] Checking for PAM configuration file at /etc/pam.d/LoginWindow-pam");
    if (access("/etc/pam.d/LoginWindow-pam", R_OK) != 0) {
        NSLog(@"[PAM] ERROR: /etc/pam.d/LoginWindow-pam is not readable or does not exist (errno=%d: %s)", errno, strerror(errno));
    } else {
        NSLog(@"[PAM] PAM configuration file exists and is readable");
    }
    
    // "LoginWindow-pam" is the service name used for PAM authentication, there is a file in /etc/pam.d/ that defines the service
    NSLog(@"[PAM] Calling pam_start with service='LoginWindow-pam', user='%s'", [username UTF8String]);
    int result = pam_start("LoginWindow-pam", [username UTF8String], &pam_conversation, &pam_handle);
    NSLog(@"[PAM] pam_start returned: %d", result);
    if (pam_handle != NULL) {
        NSLog(@"[PAM] pam_start error message: %s", pam_strerror(pam_handle, result));
    } else {
        NSLog(@"[PAM] pam_start failed and pam_handle is NULL");
    }
    if (result != PAM_SUCCESS) {
        const char *error = pam_handle ? pam_strerror(pam_handle, result) : "unknown error";
        NSLog(@"[PAM] pam_start FAILED with code %d: %s (errno=%d: %s)", result, error, errno, strerror(errno));
        NSLog(@"[PAM] Common causes: 1) /etc/pam.d/LoginWindow-pam missing, 2) PAM modules not found, 3) permission denied");
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"PAM initialization failed: %s\nCheck /etc/pam.d/LoginWindow-pam exists and PAM modules are installed.", error] retain];
        authenticationInProgress = NO;
        return NO;
    }
    result = pam_set_item(pam_handle, PAM_TTY, ttyname(STDIN_FILENO));
    NSLog(@"[PAM] pam_set_item PAM_TTY result: %d (%s)", result, pam_strerror(pam_handle, result));
    
    // Set DISPLAY for X11 authorization (required for pam_xauth to work)
    const char *display = getenv("DISPLAY");
    if (display) {
        result = pam_set_item(pam_handle, PAM_XDISPLAY, display);
        NSLog(@"[PAM] pam_set_item PAM_XDISPLAY result: %d (%s), DISPLAY=%s", result, pam_strerror(pam_handle, result), display);
    } else {
        NSLog(@"[PAM] Warning: DISPLAY environment variable not set");
    }
    
    char hostname[256];
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        pam_set_item(pam_handle, PAM_RHOST, hostname);
        NSLog(@"[PAM] pam_set_item PAM_RHOST: %s", hostname);
    } else {
        NSLog(@"[PAM] gethostname failed");
    }
    result = pam_authenticate(pam_handle, 0);
    NSLog(@"[PAM] pam_authenticate result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_authenticate failed: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Authentication failed: %s", error] retain];
        pam_end(pam_handle, result);
        pam_handle = NULL;
        authenticationInProgress = NO;
        [_storedPassword release];
        _storedPassword = nil;
        return NO;
    }
    result = pam_acct_mgmt(pam_handle, PAM_SILENT);
    NSLog(@"[PAM] pam_acct_mgmt result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_acct_mgmt failed: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Account management failed: %s", error] retain];
        pam_end(pam_handle, result);
        pam_handle = NULL;
        authenticationInProgress = NO;
        [_storedPassword release];
        _storedPassword = nil;
        return NO;
    }
    authenticationInProgress = NO;
    [_storedPassword release];
    _storedPassword = nil;
    NSLog(@"[PAM] Authentication succeeded for user: %@", username);
    return YES;
}

- (BOOL)openSession
{
    NSLog(@"[PAM] openSession called");
    if (!pam_handle) {
        NSLog(@"[PAM] openSession failed: pam_handle is NULL");
        return NO;
    }
    int result = pam_setcred(pam_handle, PAM_ESTABLISH_CRED);
    NSLog(@"[PAM] pam_setcred result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_setcred failed: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Failed to establish credentials: %s", error] retain];
        return NO;
    }
    result = pam_open_session(pam_handle, 0);
    NSLog(@"[PAM] pam_open_session result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_open_session failed: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Failed to open session: %s", error] retain];
        pam_setcred(pam_handle, PAM_DELETE_CRED);
        return NO;
    }
    NSLog(@"[PAM] Session opened successfully");
    return YES;
}

- (void)closeSession
{
    NSLog(@"[PAM] closeSession called");
    if (!pam_handle) {
        NSLog(@"[PAM] closeSession: pam_handle is NULL");
        return;
    }
    int result = pam_close_session(pam_handle, 0);
    NSLog(@"[PAM] pam_close_session result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        NSLog(@"[PAM] pam_close_session failed: %s", pam_strerror(pam_handle, result));
    }
    result = pam_setcred(pam_handle, PAM_DELETE_CRED);
    NSLog(@"[PAM] pam_setcred (delete) result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        NSLog(@"[PAM] pam_setcred (delete) failed: %s", pam_strerror(pam_handle, result));
    }
    pam_end(pam_handle, PAM_SUCCESS);
    pam_handle = NULL;
    NSLog(@"[PAM] PAM transaction ended");
}

- (char **)getEnvironmentList
{
    NSLog(@"[PAM] getEnvironmentList called");
    if (!pam_handle) {
        NSLog(@"[PAM] getEnvironmentList: pam_handle is NULL");
        return NULL;
    }
    return pam_getenvlist(pam_handle);
}

- (BOOL)openSessionForUser:(NSString *)username
{
    NSLog(@"[PAM] openSessionForUser called for user: %@", username);
    if (authenticationInProgress) {
        NSLog(@"[PAM] Authentication already in progress");
        return NO;
    }
    authenticationInProgress = YES;
    
    [_storedUsername release];
    [_storedPassword release];
    _storedUsername = [username copy];
    _storedPassword = nil; // No password for auto-login
    
    NSLog(@"[PAM] Starting PAM session for auto-login user: %@", username);
    
    // Check if PAM configuration file exists
    NSLog(@"[PAM] Checking for PAM configuration file at /etc/pam.d/LoginWindow-pam");
    if (access("/etc/pam.d/LoginWindow-pam", R_OK) != 0) {
        NSLog(@"[PAM] ERROR: /etc/pam.d/LoginWindow-pam is not readable or does not exist (errno=%d: %s)", errno, strerror(errno));
    } else {
        NSLog(@"[PAM] PAM configuration file exists and is readable");
    }
    
    // "LoginWindow-pam" is the service name used for PAM authentication
    NSLog(@"[PAM] Calling pam_start with service='LoginWindow-pam', user='%s'", [username UTF8String]);
    int result = pam_start("LoginWindow-pam", [username UTF8String], &pam_conversation, &pam_handle);
    NSLog(@"[PAM] pam_start returned: %d", result);
    if (pam_handle != NULL) {
        NSLog(@"[PAM] pam_start error message: %s", pam_strerror(pam_handle, result));
    } else {
        NSLog(@"[PAM] pam_start failed and pam_handle is NULL");
    }
    if (result != PAM_SUCCESS) {
        const char *error = pam_handle ? pam_strerror(pam_handle, result) : "unknown error";
        NSLog(@"[PAM] pam_start FAILED for auto-login with code %d: %s (errno=%d: %s)", result, error, errno, strerror(errno));
        NSLog(@"[PAM] Common causes: 1) /etc/pam.d/LoginWindow-pam missing, 2) PAM modules not found, 3) permission denied");
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"PAM initialization failed for auto-login: %s\nCheck /etc/pam.d/LoginWindow-pam exists and PAM modules are installed.", error] retain];
        authenticationInProgress = NO;
        return NO;
    }
    
    result = pam_set_item(pam_handle, PAM_TTY, ttyname(STDIN_FILENO));
    NSLog(@"[PAM] pam_set_item PAM_TTY result for auto-login: %d (%s)", result, pam_strerror(pam_handle, result));
    
    // Set DISPLAY for X11 authorization (required for pam_xauth to work)
    const char *display = getenv("DISPLAY");
    if (display) {
        result = pam_set_item(pam_handle, PAM_XDISPLAY, display);
        NSLog(@"[PAM] pam_set_item PAM_XDISPLAY result for auto-login: %d (%s), DISPLAY=%s", result, pam_strerror(pam_handle, result), display);
    } else {
        NSLog(@"[PAM] Warning: DISPLAY environment variable not set for auto-login");
    }
    
    char hostname[256];
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        pam_set_item(pam_handle, PAM_RHOST, hostname);
        NSLog(@"[PAM] pam_set_item PAM_RHOST for auto-login: %s", hostname);
    } else {
        NSLog(@"[PAM] gethostname failed for auto-login");
    }
    
    // For auto-login, skip authentication but still do account management
    NSLog(@"[PAM] Skipping authentication for auto-login, proceeding to account management");
    
    result = pam_acct_mgmt(pam_handle, PAM_SILENT);
    NSLog(@"[PAM] pam_acct_mgmt result for auto-login: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_acct_mgmt failed for auto-login: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Account management failed for auto-login: %s", error] retain];
        pam_end(pam_handle, result);
        pam_handle = NULL;
        authenticationInProgress = NO;
        return NO;
    }
    
    // Open the session directly
    result = pam_setcred(pam_handle, PAM_ESTABLISH_CRED);
    NSLog(@"[PAM] pam_setcred result for auto-login: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_setcred failed for auto-login: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Failed to establish credentials for auto-login: %s", error] retain];
        pam_end(pam_handle, result);
        pam_handle = NULL;
        authenticationInProgress = NO;
        return NO;
    }
    
    result = pam_open_session(pam_handle, 0);
    NSLog(@"[PAM] pam_open_session result for auto-login: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_open_session failed for auto-login: %s", error);
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"Failed to open session for auto-login: %s", error] retain];
        pam_setcred(pam_handle, PAM_DELETE_CRED);
        pam_end(pam_handle, result);
        pam_handle = NULL;
        authenticationInProgress = NO;
        return NO;
    }
    
    authenticationInProgress = NO;
    NSLog(@"[PAM] Auto-login session opened successfully for user: %@", username);
    return YES;
}

- (NSString *)getLastError
{
    if (_lastErrorMessage) {
        return [[_lastErrorMessage copy] autorelease];
    }
    return @"Unknown PAM error";
}

@end
