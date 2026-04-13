/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// DRIDownloader.m
// Debian Runtime Installer - File Downloader
//

#import "DRIDownloader.h"

@interface DRIDownloader() <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *downloadedData;
@property (nonatomic, strong) NSString *destinationPath;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) long long bytesDownloaded;
@property (nonatomic, assign) long long expectedBytes;
@end

@implementation DRIDownloader

- (instancetype)init
{
    if (self = [super init]) {
        NSDebugLLog(@"gwcomp", @"DRIDownloader: init");
        
        _isDownloading = NO;
        _progress = 0.0;
        _bytesDownloaded = 0;
        _expectedBytes = 0;
        _downloadedData = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc
{
    NSDebugLLog(@"gwcomp", @"DRIDownloader: dealloc");
    [self cancelDownload];
    [_downloadedData release];
    [super dealloc];
}

- (void)downloadFileFromURL:(NSString *)urlString toPath:(NSString *)destinationPath
{
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** downloadFileFromURL: %@ to: %@", urlString, destinationPath);
    
    if (_isDownloading) {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Download already in progress, canceling previous download");
        [self cancelDownload];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** ERROR: Invalid URL: %@", urlString);
        NSError *error = [NSError errorWithDomain:@"DRIDownloader" 
                                             code:1001 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid download URL"}];
        [self.delegate downloader:self didFailWithError:error];
        return;
    }
    
    // Ensure destination directory exists
    NSString *destinationDir = [destinationPath stringByDeletingLastPathComponent];
    NSError *dirError;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:destinationDir 
                                   withIntermediateDirectories:YES 
                                                    attributes:nil 
                                                         error:&dirError]) {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** ERROR: Failed to create destination directory: %@", dirError.localizedDescription);
        [self.delegate downloader:self didFailWithError:dirError];
        return;
    }
    
    // Store destination path
    _destinationPath = [destinationPath copy];
    
    // Reset progress tracking
    _bytesDownloaded = 0;
    _expectedBytes = 0;
    _progress = 0.0;
    [_downloadedData setLength:0];
    
    // Create URL request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"DebianRuntimeInstaller/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:3600.0]; // 1 hour timeout
    
    // Start connection-based download (more reliable than NSURLDownload in GNUstep)
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Starting NSURLConnection download");
    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    
    if (_connection) {
        _isDownloading = YES;
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** NSURLConnection started successfully");
    } else {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** ERROR: Failed to create NSURLConnection");
        NSError *error = [NSError errorWithDomain:@"DRIDownloader" 
                                             code:1002 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create connection"}];
        [self.delegate downloader:self didFailWithError:error];
    }
}

- (void)cancelDownload
{
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Canceling download");
    
    if (_connection) {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Canceling NSURLConnection");
        [_connection cancel];
        [_connection release];
        _connection = nil;
    }
    
    // Clean up any partial download files
    if (_destinationPath && [[NSFileManager defaultManager] fileExistsAtPath:_destinationPath]) {
        NSError *error;
        if ([[NSFileManager defaultManager] removeItemAtPath:_destinationPath error:&error]) {
            NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Cleaned up partial download file: %@", _destinationPath);
        } else {
            NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Failed to cleanup partial download: %@", error.localizedDescription);
        }
    }
    
    if (_destinationPath) {
        [_destinationPath release];
        _destinationPath = nil;
    }
    
    [_downloadedData setLength:0];
    _isDownloading = NO;
    _progress = 0.0;
    _bytesDownloaded = 0;
    _expectedBytes = 0;
    
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Download cancellation complete");
}

#pragma mark - NSURLConnection Delegate Methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** didReceiveResponse called! Response: %@", response);
    _expectedBytes = [response expectedContentLength];
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** expected length: %lld", _expectedBytes);
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** HTTP Status: %ld", (long)[httpResponse statusCode]);
        
        // Check for HTTP errors
        if ([httpResponse statusCode] >= 400) {
            NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** HTTP Error: %ld", (long)[httpResponse statusCode]);
            [_connection cancel];
            NSError *error = [NSError errorWithDomain:@"DRIDownloader" 
                                                 code:[httpResponse statusCode] 
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP Error %ld", (long)[httpResponse statusCode]]}];
            [self.delegate downloader:self didFailWithError:error];
            return;
        }
    }
    
    if (_expectedBytes > 0) {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Calling delegate didStartDownloadWithExpectedSize");
        [self.delegate downloader:self didStartDownloadWithExpectedSize:_expectedBytes];
    } else {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Expected size is 0 or unknown");
        [self.delegate downloader:self didStartDownloadWithExpectedSize:0];
    }
    
    // Reset downloaded data for this new response
    [_downloadedData setLength:0];
    _bytesDownloaded = 0;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    NSUInteger length = [data length];
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** didReceiveData: %lu bytes", (unsigned long)length);
    
    // Append data to our buffer
    [_downloadedData appendData:data];
    _bytesDownloaded += length;
    
    if (_expectedBytes > 0) {
        _progress = (double)_bytesDownloaded / (double)_expectedBytes;
    } else {
        _progress = 0.0;
    }
    
    NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** progress: %.1f%% (%lld / %lld bytes)", 
          _progress * 100.0, _bytesDownloaded, _expectedBytes);
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(downloader:didUpdateProgress:bytesDownloaded:)]) {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** Calling delegate didUpdateProgress");
        [self.delegate downloader:self didUpdateProgress:_progress bytesDownloaded:_bytesDownloaded];
    } else {
        NSDebugLLog(@"gwcomp", @"[DRIDownloader] *** ERROR: No delegate or delegate doesn't respond to didUpdateProgress");
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSDebugLLog(@"gwcomp", @"DRIDownloader: download completed, writing to: %@", _destinationPath);
    
    // Write the downloaded data to file
    NSError *writeError;
    if ([_downloadedData writeToFile:_destinationPath options:NSDataWritingAtomic error:&writeError]) {
        // Verify file exists and has correct size
        if ([[NSFileManager defaultManager] fileExistsAtPath:_destinationPath]) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:_destinationPath error:nil];
            long long fileSize = [[attributes objectForKey:NSFileSize] longLongValue];
            NSDebugLLog(@"gwcomp", @"DRIDownloader: final file size: %lld bytes", fileSize);
            
            _isDownloading = NO;
            [self.delegate downloader:self didCompleteWithFilePath:_destinationPath];
        } else {
            NSDebugLLog(@"gwcomp", @"DRIDownloader: written file not found at expected location");
            _isDownloading = NO;
            NSError *error = [NSError errorWithDomain:@"DRIDownloader" 
                                                 code:1003 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Downloaded file not found after writing"}];
            [self.delegate downloader:self didFailWithError:error];
        }
    } else {
        NSDebugLLog(@"gwcomp", @"DRIDownloader: failed to write downloaded data: %@", writeError.localizedDescription);
        _isDownloading = NO;
        [self.delegate downloader:self didFailWithError:writeError];
    }
    
    [_connection release];
    _connection = nil;
    [_destinationPath release];
    _destinationPath = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSDebugLLog(@"gwcomp", @"DRIDownloader: download failed with error: %@", error.localizedDescription);
    _isDownloading = NO;
    
    [self.delegate downloader:self didFailWithError:error];
    
    [_connection release];
    _connection = nil;
    [_destinationPath release];
    _destinationPath = nil;
}

@end
