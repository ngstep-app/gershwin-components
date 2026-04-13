/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// DRIInstaller.m
// Debian Runtime Installer - System Installation
//

#import "DRIInstaller.h"
#import <AppKit/AppKit.h>

@interface DRIInstaller()
@property (nonatomic, assign) BOOL isInstalling;
@property (nonatomic, strong) NSTask *currentTask;
@property (nonatomic, strong) NSString *currentImagePath;
@property (nonatomic, copy) void (^currentCompletion)(BOOL success, NSString *output);
@property (nonatomic, assign) BOOL taskTimedOut;
@end

@implementation DRIInstaller

- (instancetype)init
{
    if (self = [super init]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: init");
        _isInstalling = NO;
    }
    return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)dealloc
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: dealloc");
    [self cancelInstallation];
    if (_currentCompletion) {
        _currentCompletion = nil;
    }
}
#pragma clang diagnostic pop

- (void)installRuntimeFromImagePath:(NSString *)imagePath
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: installRuntimeFromImagePath called");
    NSDebugLLog(@"gwcomp", @"DRIInstaller: imagePath class: %@", [imagePath class]);
    NSDebugLLog(@"gwcomp", @"DRIInstaller: imagePath value: %@", imagePath);
    
    if (_isInstalling) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: installation already in progress");
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:@"Installation already in progress"];
        return;
    }
    
    if (!imagePath || [imagePath length] == 0) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: no image path provided");
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:@"No runtime image path provided"];
        return;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: image file does not exist: %@", imagePath);
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:[NSString stringWithFormat:@"Runtime image file not found: %@", imagePath]];
        return;
    }
    
    // Check if file is readable
    if (![[NSFileManager defaultManager] isReadableFileAtPath:imagePath]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: image file is not readable: %@", imagePath);
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:[NSString stringWithFormat:@"Runtime image file is not readable: %@", imagePath]];
        return;
    }
    
    // Check file size (minimum 50MB, maximum 5GB)
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:imagePath error:nil];
    if (attributes) {
        long long fileSize = [[attributes objectForKey:NSFileSize] longLongValue];
        NSDebugLLog(@"gwcomp", @"DRIInstaller: image file size: %lld bytes", fileSize);
        
        if (fileSize < 50000000) { // Less than 50MB
            NSDebugLLog(@"gwcomp", @"DRIInstaller: image file too small: %lld bytes", fileSize);
            [self.delegate installer:self didCompleteSuccessfully:NO 
                         withMessage:[NSString stringWithFormat:@"Runtime image file appears too small (%lld bytes). Minimum expected size is 50MB.", fileSize]];
            return;
        }
        
        if (fileSize > 5000000000LL) { // More than 5GB
            NSDebugLLog(@"gwcomp", @"DRIInstaller: image file too large: %lld bytes", fileSize);
            [self.delegate installer:self didCompleteSuccessfully:NO 
                         withMessage:[NSString stringWithFormat:@"Runtime image file appears too large (%lld bytes). Maximum supported size is 5GB.", fileSize]];
            return;
        }
    }
    
    _currentImagePath = imagePath;
    _isInstalling = YES;
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Starting installation process for image: %@", imagePath);
    [self.delegate installer:self didStartInstallationWithMessage:@"Starting installation..."];
    
    // Step 1: Check system requirements
    [self checkSystemRequirements];
}

- (void)cancelInstallation
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: cancelInstallation called");
    
    if (_currentTask) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: terminating current task PID %d", [_currentTask processIdentifier]);
        [_currentTask terminate];
        [_currentTask waitUntilExit]; // Wait for clean termination
        _currentTask = nil;
    }
    
    if (_currentCompletion) {
        _currentCompletion = nil;
    }
    
    // Clean up any partial files
    [self cleanupPartialFiles];
    
    _isInstalling = NO;
    _currentImagePath = nil;
    _taskTimedOut = NO;
    
    NSDebugLLog(@"gwcomp", @"DRIInstaller: cancellation complete");
}

- (void)cleanupPartialFiles
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: cleaning up partial files");
    
    NSArray *filesToCleanup = @[
        @"/tmp/debian_service_script",
        @"/tmp/debian-runtime.img",
        @"/compat/debian.img.partial",
        @"/tmp/debian_download.tmp"
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *filePath in filesToCleanup) {
        if ([fileManager fileExistsAtPath:filePath]) {
            NSError *error;
            if ([fileManager removeItemAtPath:filePath error:&error]) {
                NSDebugLLog(@"gwcomp", @"DRIInstaller: cleaned up file: %@", filePath);
            } else {
                NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to cleanup file %@: %@", filePath, error.localizedDescription);
            }
        }
    }
}

- (void)checkSystemRequirements
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** checkSystemRequirements starting...");
    [self.delegate installer:self didUpdateProgress:@"Checking system requirements..."];
    
    // Check if running on FreeBSD
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Creating task to check system type with uname");
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/uname"];
    [task setArguments:@[@"-s"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    @try {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Launching uname task...");
        [task launch];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** uname task launched, PID: %d", [task processIdentifier]);
        [task waitUntilExit];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** uname task completed with status: %d", [task terminationStatus]);
        
        if ([task terminationStatus] != 0) {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** ERROR: uname command failed with status %d", [task terminationStatus]);
            [self.delegate installer:self didCompleteSuccessfully:NO 
                         withMessage:@"System check failed: Could not determine operating system"];
            return;
        }
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Raw uname output: [%@]", output);
        
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Trimmed uname output: [%@]", output);
        
        if (![output isEqualToString:@"FreeBSD"]) {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** SYSTEM CHECK FAILED: not running on FreeBSD (detected: %@)", output);
            [self.delegate installer:self didCompleteSuccessfully:NO 
                         withMessage:[NSString stringWithFormat:@"This installer requires FreeBSD (detected: %@)", output]];
            return;
        }
        
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** SYSTEM CHECK PASSED: FreeBSD detected, proceeding to Linux compatibility check");
        [self checkLinuxCompatibilityLayer];
        
    } @catch (NSException *exception) {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** EXCEPTION in checkSystemRequirements: %@ - %@", [exception name], [exception reason]);
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:[NSString stringWithFormat:@"System check failed: %@", [exception reason]]];
    }
}

- (void)checkLinuxCompatibilityLayer
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** checkLinuxCompatibilityLayer starting...");
    [self.delegate installer:self didUpdateProgress:@"Checking Linux compatibility layer..."];
    
    // Check if linux.ko is loaded
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Checking if linux.ko kernel module is loaded...");
    [self executeCommand:@"/sbin/kldstat" 
               withArgs:@[@"-q", @"-n", @"linux"] 
             completion:^(BOOL success, NSString * __attribute__((unused)) output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Linux compatibility layer is already loaded");
            [self createCompatDirectory];
        } else {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Linux compatibility layer not loaded, attempting to load it");
            [self loadLinuxCompatibilityLayer];
        }
    }];
}

- (void)loadLinuxCompatibilityLayer
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** loadLinuxCompatibilityLayer starting...");
    [self.delegate installer:self didUpdateProgress:@"Loading Linux compatibility layer..."];
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Attempting to load linux.ko kernel module...");
    [self executeCommand:@"/sbin/kldload" 
               withArgs:@[@"linux"] 
             completion:^(BOOL success, NSString *output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Successfully loaded Linux compatibility layer");
            [self createCompatDirectory];
        } else {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** FAILED to load Linux compatibility layer: %@", output);
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to execute: kldload linux\n\nError: %@\n\nPlease run 'kldload linux' manually and try again.", output.length > 0 ? output : @"Unknown error"];
            [self.delegate installer:self didCompleteSuccessfully:NO withMessage:errorMessage];
        }
    }];
}

- (void)createCompatDirectory
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** createCompatDirectory starting...");
    [self.delegate installer:self didUpdateProgress:@"Creating compatibility directory..."];
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Creating /compat directory...");
    [self executeCommand:@"/bin/mkdir" 
               withArgs:@[@"-p", @"/compat"] 
             completion:^(BOOL success, NSString *output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Successfully created/verified /compat directory");
            [self removeExistingRuntime];
        } else {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** FAILED to create /compat directory: %@", output);
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to execute: mkdir -p /compat\n\nError: %@\n\nPlease ensure the application has root privileges and try again.", output.length > 0 ? output : @"Unknown error"];
            [self.delegate installer:self didCompleteSuccessfully:NO withMessage:errorMessage];
        }
    }];
}

- (void)removeExistingRuntime
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: removeExistingRuntime");
    [self.delegate installer:self didUpdateProgress:@"Checking for existing runtime..."];
    
    // Check if debian.img already exists
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/compat/debian.img"]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: removing existing debian.img");
        [self.delegate installer:self didUpdateProgress:@"Removing existing runtime..."];
        
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Removing existing debian.img...");
        [self executeCommand:@"/bin/rm" 
                   withArgs:@[@"-f", @"/compat/debian.img"] 
                 completion:^(BOOL success, NSString *output) {
            if (success) {
                NSDebugLLog(@"gwcomp", @"DRIInstaller: existing runtime removed");
                [self copyRuntimeImage];
            } else {
                NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to remove existing runtime: %@", output);
                NSString *errorMessage = [NSString stringWithFormat:@"Failed to execute: rm -f /compat/debian.img\n\nError: %@\n\nPlease manually remove the existing runtime and try again.", output.length > 0 ? output : @"Unknown error"];
                [self.delegate installer:self didCompleteSuccessfully:NO withMessage:errorMessage];
            }
        }];
    } else {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: no existing runtime found");
        [self copyRuntimeImage];
    }
}

- (void)copyRuntimeImage
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: copyRuntimeImage from %@", _currentImagePath);
    [self.delegate installer:self didUpdateProgress:@"Installing runtime image..."];
    
    // Check if source file exists and is readable
    if (![[NSFileManager defaultManager] fileExistsAtPath:_currentImagePath]) {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** ERROR: Source image file does not exist: %@", _currentImagePath);
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:[NSString stringWithFormat:@"Source image file not found: %@", _currentImagePath]];
        return;
    }
    
    // Check available disk space
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:_currentImagePath error:nil];
    if (attributes) {
        long long sourceSize = [[attributes objectForKey:NSFileSize] longLongValue];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Source image size: %lld bytes", sourceSize);
        
        // Check free space in /compat
        NSDictionary *compatAttrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/compat" error:nil];
        if (compatAttrs) {
            long long freeSpace = [[compatAttrs objectForKey:NSFileSystemFreeSize] longLongValue];
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Available space in /compat: %lld bytes", freeSpace);
            
            if (freeSpace < sourceSize + 100000000) { // Need 100MB extra space
                NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** ERROR: Insufficient disk space");
                [self.delegate installer:self didCompleteSuccessfully:NO 
                             withMessage:@"Insufficient disk space in /compat directory"];
                return;
            }
        }
    }
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Copying runtime image...");
    [self executeCommand:@"/bin/cp" 
               withArgs:@[_currentImagePath, @"/compat/debian.img"] 
             completion:^(BOOL success, NSString *output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: runtime image copied successfully");
            
            // Verify the copied file
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/compat/debian.img"]) {
                NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Copied file verified successfully");
                [self setPermissions];
            } else {
                NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** ERROR: Copied file verification failed");
                [self.delegate installer:self didCompleteSuccessfully:NO 
                             withMessage:@"File copy verification failed - copied file not found"];
            }
        } else {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to copy runtime image: %@", output);
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to copy runtime image\n\nError: %@\n\nPlease check:\n• Disk space availability\n• File permissions\n• Source file integrity", output.length > 0 ? output : @"Unknown error"];
            [self.delegate installer:self didCompleteSuccessfully:NO withMessage:errorMessage];
        }
    }];
}

- (void)setPermissions
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: setPermissions");
    [self.delegate installer:self didUpdateProgress:@"Setting permissions..."];
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Setting permissions...");
    [self executeCommand:@"/bin/chmod" 
               withArgs:@[@"644", @"/compat/debian.img"] 
             completion:^(BOOL success, NSString *output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: permissions set successfully");
            [self installServiceScript];
        } else {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to set permissions: %@", output);
            // Continue anyway, permissions are not critical
            [self installServiceScript];
        }
    }];
}

- (void)installServiceScript
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: installServiceScript");
    [self.delegate installer:self didUpdateProgress:@"Installing service script..."];
    
    // Create a basic service script for debian runtime
    NSString *serviceScript = @"#!/bin/sh\n"
                             @"#\n"
                             @"# PROVIDE: debian\n"
                             @"# REQUIRE: FILESYSTEMS\n"
                             @"# KEYWORD: nojail\n"
                             @"\n"
                             @". /etc/rc.subr\n"
                             @"\n"
                             @"name=\"debian\"\n"
                             @"rcvar=\"debian_enable\"\n"
                             @"command=\"mount\"\n"
                             @"command_args=\"-t linuxfs /compat/debian.img /compat/debian\"\n"
                             @"start_precmd=\"debian_prestart\"\n"
                             @"stop_cmd=\"debian_stop\"\n"
                             @"\n"
                             @"debian_prestart() {\n"
                             @"    if [ ! -d /compat/debian ]; then\n"
                             @"        mkdir -p /compat/debian\n"
                             @"    fi\n"
                             @"}\n"
                             @"\n"
                             @"debian_stop() {\n"
                             @"    umount /compat/debian 2>/dev/null || true\n"
                             @"}\n"
                             @"\n"
                             @"load_rc_config $name\n"
                             @"run_rc_command \"$1\"\n";
    
    // Write service script to temporary location first
    NSString *tempScript = @"/tmp/debian_service_script";
    NSError *writeError;
    if (![serviceScript writeToFile:tempScript 
                         atomically:YES 
                           encoding:NSUTF8StringEncoding 
                              error:&writeError]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to write temporary service script: %@", writeError.localizedDescription);
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:[NSString stringWithFormat:@"Could not create service script: %@", writeError.localizedDescription]];
        return;
    }
    
    // Verify the temporary file was written correctly
    if (![[NSFileManager defaultManager] fileExistsAtPath:tempScript]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: temporary service script file not found after writing");
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:@"Could not create temporary service script file"];
        return;
    }
    
    // Check if target directory exists
    NSString *targetDir = @"/usr/local/etc/rc.d";
    if (![[NSFileManager defaultManager] fileExistsAtPath:targetDir]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: target directory does not exist: %@", targetDir);
        [self.delegate installer:self didCompleteSuccessfully:NO 
                     withMessage:[NSString stringWithFormat:@"Target directory not found: %@\n\nThis may indicate that the FreeBSD base system is incomplete.", targetDir]];
        // Clean up temp file
        [[NSFileManager defaultManager] removeItemAtPath:tempScript error:nil];
        return;
    }
    
    // Copy to system location
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Installing service script...");
    [self executeCommand:@"/bin/cp" 
               withArgs:@[tempScript, @"/usr/local/etc/rc.d/debian"] 
             completion:^(BOOL success, NSString *output) {
        // Clean up temp file
        NSError *cleanupError;
        if (![[NSFileManager defaultManager] removeItemAtPath:tempScript error:&cleanupError]) {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to cleanup temporary file: %@", cleanupError.localizedDescription);
        }
        
        if (success) {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: service script installed");
            
            // Verify the file was copied correctly
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/local/etc/rc.d/debian"]) {
                NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Service script verification successful");
                [self makeServiceExecutable];
            } else {
                NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** ERROR: Service script verification failed");
                [self.delegate installer:self didCompleteSuccessfully:NO 
                             withMessage:@"Service script copy verification failed"];
            }
        } else {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to install service script: %@", output);
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to install service script\n\nError: %@\n\nThe runtime image was installed but the service script could not be created.\n\nYou may need to manually configure the service startup.", output.length > 0 ? output : @"Unknown error"];
            [self.delegate installer:self didCompleteSuccessfully:NO withMessage:errorMessage];
        }
    }];
}

- (void)makeServiceExecutable
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** makeServiceExecutable starting...");
    [self.delegate installer:self didUpdateProgress:@"Making service script executable..."];
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Setting executable permissions...");
    [self executeCommand:@"/bin/chmod" 
               withArgs:@[@"755", @"/usr/local/etc/rc.d/debian"] 
             completion:^(BOOL success, NSString *output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: service script made executable");
            [self enableServiceInRC];
        } else {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to make service executable: %@", output);
            // Continue anyway
            [self enableServiceInRC];
        }
    }];
}

- (void)enableServiceInRC
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: enableServiceInRC");
    [self.delegate installer:self didUpdateProgress:@"Enabling service in rc.conf..."];
    
    // Add debian_enable="YES" to rc.conf if not already present
    [self executeCommand:@"/usr/bin/grep" 
               withArgs:@[@"debian_enable", @"/etc/rc.conf"] 
             completion:^(BOOL success, NSString * __attribute__((unused)) output) {
        if (success) {
            NSDebugLLog(@"gwcomp", @"DRIInstaller: debian service already configured in rc.conf");
            [self completedSuccessfully];
        } else {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Adding debian_enable to rc.conf...");
            [self executeCommand:@"/bin/sh" 
                       withArgs:@[@"-c", @"echo 'debian_enable=\"YES\"' >> /etc/rc.conf"] 
                     completion:^(BOOL success, NSString *output) {
                if (success) {
                    NSDebugLLog(@"gwcomp", @"DRIInstaller: debian service enabled in rc.conf");
                } else {
                    NSDebugLLog(@"gwcomp", @"DRIInstaller: failed to enable service in rc.conf: %@", output);
                }
                // Complete regardless of rc.conf result
                [self completedSuccessfully];
            }];
        }
    }];
}

- (void)completedSuccessfully
{
    NSDebugLLog(@"gwcomp", @"DRIInstaller: completedSuccessfully");
    [self.delegate installer:self didUpdateProgress:@"Installation completed successfully!"];
    
    _isInstalling = NO;
    _currentImagePath = nil;
    
    // Notify completion immediately - no timer needed
    [self notifyInstallationSuccess];
}

- (void)notifyInstallationSuccess
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Notifying installation success...");
    // Check if delegate responds to the method before calling
    if ([self.delegate respondsToSelector:@selector(installer:didCompleteSuccessfully:withMessage:)]) {
        [self.delegate installer:self didCompleteSuccessfully:YES 
                     withMessage:@"Debian runtime has been installed successfully. You can now run Linux applications."];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Delegate notified successfully");
    } else {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** WARNING: Delegate does not respond to installer:didCompleteSuccessfully:withMessage:");
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Installation completed successfully, but cannot notify delegate");
    }
}

- (void)executeCommand:(NSString *)command withArgs:(NSArray *)args completion:(void (^)(BOOL success, NSString *output))completion
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** EXECUTING COMMAND: %@ with args: %@", command, args);
    
    if (_currentTask) {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** WARNING: Previous task still running, terminating it");
        [_currentTask terminate];
        _currentTask = nil;
    }
    
    // Reset timeout flag
    _taskTimedOut = NO;
    
    // Store completion block for timeout handling
    if (completion) {
        _currentCompletion = [completion copy];
    }
    
    // Check if command exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:command]) {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** ERROR: Command not found: %@", command);
        NSString *errorMessage = [NSString stringWithFormat:@"Command not found: %@\n\nThis may indicate that the required software is not installed or the path is incorrect.", command];
        if (completion) {
            completion(NO, errorMessage);
        }
        _currentCompletion = nil;
        return;
    }
    
    _currentTask = [[NSTask alloc] init];
    [_currentTask setLaunchPath:command];
    [_currentTask setArguments:args];
    
    NSPipe *pipe = [NSPipe pipe];
    [_currentTask setStandardOutput:pipe];
    [_currentTask setStandardError:pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Task configured, about to launch...");
    
    @try {
        [_currentTask launch];
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Task launched successfully, PID: %d", [_currentTask processIdentifier]);
        
        // Use timeout to prevent hanging
        NSTimer *timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                                  target:self
                                                                selector:@selector(timeoutTask:)
                                                                userInfo:_currentTask
                                                                 repeats:NO];
        
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Waiting for task to complete...");
        [_currentTask waitUntilExit];
        [timeoutTimer invalidate];
        
        // Check if task was terminated due to timeout
        if (_taskTimedOut) {
            NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Task was terminated due to timeout");
            NSString *timeoutMessage = [NSString stringWithFormat:@"Command timed out after 30 seconds: %@ %@\n\nThis may indicate that:\n• The command is waiting for user input\n• The system is under heavy load\n• There is a network connectivity issue\n• The command has hung\n\nPlease try again or run the command manually to diagnose the issue.", 
                                      command, [args componentsJoinedByString:@" "]];
            
            if (_currentCompletion) {
                _currentCompletion(NO, timeoutMessage);
                _currentCompletion = nil;
            }
            return;
        }
        
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Task completed");
        
        NSData *data = [file readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        int terminationStatus = [_currentTask terminationStatus];
        BOOL success = (terminationStatus == 0);
        
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Command termination status: %d (success: %@)", terminationStatus, success ? @"YES" : @"NO");
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Command output: [%@]", output ?: @"<empty>");
        
        // Enhance error messages for common sudo failures
        if (!success && [command containsString:@"sudo"]) {
            NSString *enhancedOutput = [self enhanceSudoErrorMessage:output withCommand:command args:args terminationStatus:terminationStatus];
            
            if (completion) {
                completion(success, enhancedOutput ?: @"");
            }
        } else if (!success) {
            // Enhanced error messages for non-sudo commands
            NSString *enhancedOutput = [self enhanceGeneralErrorMessage:output withCommand:command args:args terminationStatus:terminationStatus];
            
            if (completion) {
                completion(success, enhancedOutput ?: @"");
            }
        } else {
            if (completion) {
                completion(success, output ?: @"");
            }
        }
        
        
    } @catch (NSException *exception) {
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** EXCEPTION during command execution: %@", [exception reason]);
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Exception name: %@", [exception name]);
        NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Exception userInfo: %@", [exception userInfo]);
        
        NSString *errorMessage = [NSString stringWithFormat:@"Exception while executing: %@ %@\n\nException: %@\n\nThis may indicate a system-level problem or permission issue.", 
                                 command, [args componentsJoinedByString:@" "], [exception reason]];
        
        if (completion) {
            completion(NO, errorMessage);
        }
    } @finally {
        if (_currentTask) {
            _currentTask = nil;
        }
        if (_currentCompletion) {
            _currentCompletion = nil;
        }
    }
}

- (NSString *)enhanceSudoErrorMessage:(NSString *)output withCommand:(NSString *)command args:(NSArray *)args terminationStatus:(int)status
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Enhancing sudo error message for status %d", status);
    
    NSString *baseCommand = [NSString stringWithFormat:@"sudo %@", [args componentsJoinedByString:@" "]];
    
    if ([output containsString:@"sudo: no tty present"] || [output containsString:@"sudo: a terminal is required"]) {
        return [NSString stringWithFormat:@"%@\n\nThis error occurs when sudo requires a password but no terminal is available. Please configure sudo to allow passwordless access for the required commands, or run the installer from a terminal.\n\nCommand attempted: %@", output, baseCommand];
    } else if ([output containsString:@"is not in the sudoers file"]) {
        return [NSString stringWithFormat:@"%@\n\nYour user account is not configured to use sudo. Please add your user to the sudoers file or wheel group.\n\nCommand attempted: %@", output, baseCommand];
    } else if ([output containsString:@"incorrect password"] || [output containsString:@"authentication failure"]) {
        return [NSString stringWithFormat:@"%@\n\nIncorrect sudo password. Please ensure your sudo password is correct.\n\nCommand attempted: %@", output, baseCommand];
    } else if ([output containsString:@"Operation not permitted"] || status == 1) {
        return [NSString stringWithFormat:@"%@\n\nPermission denied. This may indicate:\n• Insufficient privileges\n• File system protection\n• System integrity protection\n• Missing sudo configuration\n\nCommand attempted: %@", output.length > 0 ? output : @"Operation not permitted", baseCommand];
    } else if ([output containsString:@"command not found"] || status == 127) {
        return [NSString stringWithFormat:@"%@\n\nThe requested command was not found. This may indicate:\n• Missing system utilities\n• Incorrect PATH configuration\n• Required software not installed\n\nCommand attempted: %@", output.length > 0 ? output : @"Command not found", baseCommand];
    } else if (output.length == 0 && status != 0) {
        return [NSString stringWithFormat:@"Sudo command failed with no output (exit code: %d). This may indicate a permission or configuration issue.\n\nCommand attempted: %@", status, baseCommand];
    } else if (output.length == 0) {
        return [NSString stringWithFormat:@"Sudo command failed with no output. This may indicate a permission or configuration issue.\n\nCommand attempted: %@", baseCommand];
    }
    
    // Default enhanced message
    return [NSString stringWithFormat:@"%@\n\nSudo command failed (exit code: %d).\n\nCommand attempted: %@", output, status, baseCommand];
}

- (NSString *)enhanceGeneralErrorMessage:(NSString *)output withCommand:(NSString *)command args:(NSArray *)args terminationStatus:(int)status
{
    NSDebugLLog(@"gwcomp", @"[DRIInstaller] *** Enhancing general error message for status %d", status);
    
    NSString *fullCommand = [NSString stringWithFormat:@"%@ %@", command, [args componentsJoinedByString:@" "]];
    
    if ([output containsString:@"No such file or directory"] || status == 2) {
        return [NSString stringWithFormat:@"%@\n\nFile or directory not found. This may indicate:\n• Missing files or directories\n• Incorrect path specification\n• File system not mounted\n\nCommand attempted: %@", output.length > 0 ? output : @"No such file or directory", fullCommand];
    } else if ([output containsString:@"Permission denied"] || status == 13) {
        return [NSString stringWithFormat:@"%@\n\nPermission denied. This may indicate:\n• Insufficient file permissions\n• Need to run with sudo\n• File system protection\n\nCommand attempted: %@", output.length > 0 ? output : @"Permission denied", fullCommand];
    } else if ([output containsString:@"command not found"] || status == 127) {
        return [NSString stringWithFormat:@"%@\n\nCommand not found. This may indicate:\n• Missing system utilities\n• Incorrect PATH configuration\n• Required software not installed\n\nCommand attempted: %@", output.length > 0 ? output : @"Command not found", fullCommand];
    } else if ([output containsString:@"No space left on device"] || status == 28) {
        return [NSString stringWithFormat:@"%@\n\nNo space left on device. Please free up disk space and try again.\n\nCommand attempted: %@", output.length > 0 ? output : @"No space left on device", fullCommand];
    } else if (output.length == 0 && status != 0) {
        return [NSString stringWithFormat:@"Command failed with no output (exit code: %d).\n\nCommand attempted: %@", status, fullCommand];
    }
    
    // Default enhanced message
    return [NSString stringWithFormat:@"%@\n\nCommand failed (exit code: %d).\n\nCommand attempted: %@", output, status, fullCommand];
}

- (void)timeoutTask:(NSTimer *)timer
{
    NSTask *task = [timer userInfo];
    if (task && [task isRunning]) {
        NSDebugLLog(@"gwcomp", @"DRIInstaller: command timed out, terminating task PID %d", [task processIdentifier]);
        _taskTimedOut = YES;
        [task terminate];
    }
}

@end
