/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "MBTransport.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>

@implementation MBTransport

+ (int)createUnixServerSocket:(NSString *)path
{
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to create socket: %s", strerror(errno));
        return -1;
    }
    
    // Remove existing socket file
    unlink([path UTF8String]);
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [path UTF8String], sizeof(addr.sun_path) - 1);
    
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to bind socket to %@: %s", path, strerror(errno));
        close(sock);
        return -1;
    }
    
    if (listen(sock, 10) < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to listen on socket: %s", strerror(errno));
        close(sock);
        return -1;
    }
    
    // Set non-blocking
    [self setSocketNonBlocking:sock];
    
    NSDebugLLog(@"gwcomp", @"Created Unix domain server socket at %@", path);
    return sock;
}

+ (int)connectToUnixSocket:(NSString *)path
{
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to create client socket: %s", strerror(errno));
        return -1;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [path UTF8String], sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to connect to socket %@: %s", path, strerror(errno));
        close(sock);
        return -1;
    }
    
    NSDebugLLog(@"gwcomp", @"Connected to Unix domain socket at %@", path);
    return sock;
}

+ (int)acceptConnection:(int)serverSocket
{
    struct sockaddr_un clientAddr;
    socklen_t clientLen = sizeof(clientAddr);
    
    int clientSocket = accept(serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
    if (clientSocket < 0) {
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            NSDebugLLog(@"gwcomp", @"Failed to accept connection: %s", strerror(errno));
        }
        return -1;
    }
    
    // Set client socket non-blocking
    [self setSocketNonBlocking:clientSocket];
    
    NSDebugLLog(@"gwcomp", @"Accepted new connection on socket %d", clientSocket);
    return clientSocket;
}

+ (BOOL)sendData:(NSData *)data onSocket:(int)socket
{
    if (!data || [data length] == 0) {
        return YES;
    }
    
    const uint8_t *bytes = [data bytes];
    size_t totalLength = [data length];
    size_t sentBytes = 0;
    
    while (sentBytes < totalLength) {
        ssize_t result = send(socket, bytes + sentBytes, totalLength - sentBytes, MSG_NOSIGNAL);
        if (result < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // Would block - try again later
                usleep(1000); // 1ms
                continue;
            }
            NSDebugLLog(@"gwcomp", @"Failed to send data on socket %d: %s", socket, strerror(errno));
            return NO;
        }
        sentBytes += result;
    }
    
    return YES;
}

+ (NSData *)receiveDataFromSocket:(int)socket
{
    uint8_t buffer[4096];
    ssize_t bytesRead = recv(socket, buffer, sizeof(buffer), 0);
    
    if (bytesRead < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            // No data available right now, but socket is still open
            return [NSData data]; // Return empty data, not nil
        }
        NSDebugLLog(@"gwcomp", @"Failed to receive data from socket %d: %s", socket, strerror(errno));
        return nil; // Real error
    }
    
    if (bytesRead == 0) {
        // Connection closed by peer
        NSDebugLLog(@"gwcomp", @"Connection closed by peer on socket %d", socket);
        return nil; // Connection closed
    }
    
    NSDebugLLog(@"gwcomp", @"Received %ld bytes on socket %d", bytesRead, socket);
    return [NSData dataWithBytes:buffer length:bytesRead];
}

+ (void)closeSocket:(int)socket
{
    if (socket >= 0) {
        close(socket);
        NSDebugLLog(@"gwcomp", @"Closed socket %d", socket);
    }
}

+ (BOOL)setSocketNonBlocking:(int)socket
{
    int flags = fcntl(socket, F_GETFL, 0);
    if (flags < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to get socket flags: %s", strerror(errno));
        return NO;
    }
    
    if (fcntl(socket, F_SETFL, flags | O_NONBLOCK) < 0) {
        NSDebugLLog(@"gwcomp", @"Failed to set socket non-blocking: %s", strerror(errno));
        return NO;
    }
    
    return YES;
}

@end
