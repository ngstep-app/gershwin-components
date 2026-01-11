/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LoginWindowPAM.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

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
        
        // Ensure PAM configuration exists (X11 authorization is now handled by libXau)
        [self ensurePAMConfiguration];
    }
    return self;
}

- (void)ensurePAMConfiguration
{
    const char *pam_config_path = "/etc/pam.d/LoginWindow-pam";
    
    NSLog(@"[PAM] Checking if %s exists...", pam_config_path);
    
    // Check if it already exists
    if (access(pam_config_path, R_OK) == 0) {
        NSLog(@"[PAM] %s already exists", pam_config_path);
        return;
    }
    
    NSLog(@"[PAM] Creating %s...", pam_config_path);
    
    FILE *config = fopen(pam_config_path, "w");
    if (!config) {
        NSLog(@"[PAM] ERROR: Cannot create %s (errno=%d: %s)", pam_config_path, errno, strerror(errno));
        NSLog(@"[PAM] LoginWindow must run as root to create PAM configuration");
        return;
    }
    
    // Create config that includes login service
    // Note: X11 authorization is handled directly via libXau, not PAM
    fprintf(config, "# PAM configuration for Gershwin LoginWindow\n");
    fprintf(config, "# Includes the system login configuration\n");
    fprintf(config, "# X11 authorization is handled via libXau, not pam_xauth\n");
    fprintf(config, "#\n\n");
    
    fprintf(config, "# Authentication - use login service\n");
    fprintf(config, "auth\t\tinclude\t\tlogin\n\n");
    
    fprintf(config, "# Account management - use login service\n");
    fprintf(config, "account\t\tinclude\t\tlogin\n\n");
    
    fprintf(config, "# Session management - use login service\n");
    fprintf(config, "session\t\tinclude\t\tlogin\n");
    
    fprintf(config, "\n# Password management - use login service\n");
    fprintf(config, "password\tinclude\t\tlogin\n");
    
    fclose(config);
    chmod(pam_config_path, 0644);
    
    NSLog(@"[PAM] PAM configuration created successfully at %s", pam_config_path);
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
    
    // Check if PAM configuration file exists and log its contents
    NSLog(@"[PAM] Checking for PAM configuration file at /etc/pam.d/LoginWindow-pam");
    if (access("/etc/pam.d/LoginWindow-pam", R_OK) != 0) {
        NSLog(@"[PAM] ERROR: /etc/pam.d/LoginWindow-pam is not readable or does not exist (errno=%d: %s)", errno, strerror(errno));
    } else {
        NSLog(@"[PAM] PAM configuration file exists and is readable");
        // Read and log the PAM configuration file contents
        FILE *pam_config = fopen("/etc/pam.d/LoginWindow-pam", "r");
        if (pam_config) {
            NSLog(@"[PAM] Contents of /etc/pam.d/LoginWindow-pam:");
            char line[256];
            int line_num = 1;
            while (fgets(line, sizeof(line), pam_config)) {
                // Remove newline
                line[strcspn(line, "\n")] = 0;
                NSLog(@"[PAM]   Line %d: %s", line_num++, line);
            }
            fclose(pam_config);
        }
    }
    
    // Check common PAM module locations on FreeBSD
    const char *pam_module_paths[] = {
        "/usr/lib/pam_unix.so",
        "/usr/local/lib/pam_unix.so",
        "/lib/security/pam_unix.so",
        "/usr/lib/security/pam_unix.so",
        NULL
    };
    NSLog(@"[PAM] Checking for pam_unix.so module:");
    for (int i = 0; pam_module_paths[i] != NULL; i++) {
        if (access(pam_module_paths[i], R_OK) == 0) {
            NSLog(@"[PAM]   FOUND: %s", pam_module_paths[i]);
        } else {
            NSLog(@"[PAM]   NOT FOUND: %s (errno=%d: %s)", pam_module_paths[i], errno, strerror(errno));
        }
    }
    
    // Check for standard PAM service file to see format
    NSLog(@"[PAM] Checking system PAM service file for comparison:");
    if (access("/etc/pam.d/system", R_OK) == 0) {
        NSLog(@"[PAM] /etc/pam.d/system exists");
        FILE *sys_config = fopen("/etc/pam.d/system", "r");
        if (sys_config) {
            NSLog(@"[PAM] First few lines of /etc/pam.d/system:");
            char line[256];
            int count = 0;
            while (fgets(line, sizeof(line), sys_config) && count < 5) {
                line[strcspn(line, "\n")] = 0;
                if (line[0] && line[0] != '#') {
                    NSLog(@"[PAM]   %s", line);
                    count++;
                }
            }
            fclose(sys_config);
        }
    }
    
    // "LoginWindow-pam" is the service name that includes login config plus X11 support
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
        NSLog(@"[PAM] Common causes: 1) /etc/pam.d/LoginWindow-pam missing or not readable, 2) PAM modules not found, 3) permission denied");
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"PAM initialization failed: %s\nCheck /etc/pam.d/LoginWindow-pam exists and PAM modules are installed.", error] retain];
        authenticationInProgress = NO;
        return NO;
    }
    result = pam_set_item(pam_handle, PAM_TTY, ttyname(STDIN_FILENO));
    NSLog(@"[PAM] pam_set_item PAM_TTY result: %d (%s)", result, pam_strerror(pam_handle, result));
    
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
    NSLog(@"[PAM] openSession called (as root - DEPRECATED, should use openSessionAsUser after setuid)");
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

- (BOOL)openSessionAsUser
{
    NSLog(@"[PAM] openSessionAsUser called (after setuid)");
    if (!pam_handle) {
        NSLog(@"[PAM] openSessionAsUser failed: pam_handle is NULL");
        return NO;
    }
    
    uid_t uid = getuid();
    NSLog(@"[PAM] Current uid: %d", uid);
    
    int result = pam_setcred(pam_handle, PAM_ESTABLISH_CRED);
    NSLog(@"[PAM] pam_setcred (ESTABLISH) result: %d (%s)", result, pam_strerror(pam_handle, result));
    if (result != PAM_SUCCESS) {
        const char *error = pam_strerror(pam_handle, result);
        NSLog(@"[PAM] pam_setcred (ESTABLISH) failed: %s", error);
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
    
    NSLog(@"[PAM] Session opened successfully as user %d", uid);
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
    
    // "LoginWindow-pam" is the service name that includes login config plus X11 support
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
        NSLog(@"[PAM] Common causes: 1) /etc/pam.d/LoginWindow-pam missing or not readable, 2) PAM modules not found, 3) permission denied");
        [_lastErrorMessage release];
        _lastErrorMessage = [[NSString stringWithFormat:@"PAM initialization failed for auto-login: %s\nCheck /etc/pam.d/LoginWindow-pam exists and PAM modules are installed.", error] retain];
        authenticationInProgress = NO;
        return NO;
    }
    
    result = pam_set_item(pam_handle, PAM_TTY, ttyname(STDIN_FILENO));
    NSLog(@"[PAM] pam_set_item PAM_TTY result for auto-login: %d (%s)", result, pam_strerror(pam_handle, result));
    
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
