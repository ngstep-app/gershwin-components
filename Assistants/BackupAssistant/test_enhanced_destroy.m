/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// test_enhanced_destroy.m
// Test program for enhanced destroyPool method with dataset unmounting
//

#import <Foundation/Foundation.h>
#import "BAZFSUtility.h"

int main(int argc, const char * argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSDebugLLog(@"gwcomp", @"Testing enhanced destroyPool method on backup_pool...");
    
    // Check if pool exists first
    if ([BAZFSUtility poolExists:@"backup_pool"]) {
        NSDebugLLog(@"gwcomp", @"Pool 'backup_pool' exists, testing enhanced destroy...");
        
        // Test the enhanced destroy method
        BOOL result = [BAZFSUtility destroyPool:@"backup_pool"];
        
        if (result) {
            NSDebugLLog(@"gwcomp", @"SUCCESS: Enhanced destroyPool method succeeded");
        } else {
            NSDebugLLog(@"gwcomp", @"FAILURE: Enhanced destroyPool method failed");
        }
        
        // Verify pool is gone
        if (![BAZFSUtility poolExists:@"backup_pool"]) {
            NSDebugLLog(@"gwcomp", @"VERIFICATION: Pool 'backup_pool' no longer exists");
        } else {
            NSDebugLLog(@"gwcomp", @"VERIFICATION FAILED: Pool 'backup_pool' still exists");
        }
    } else {
        NSDebugLLog(@"gwcomp", @"Pool 'backup_pool' does not exist - nothing to test");
    }
    
    [pool release];
    return 0;
}
