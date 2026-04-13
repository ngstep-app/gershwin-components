/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


//
// test_zfs.m
// Test program for ZFS utility functions
//

#import <Foundation/Foundation.h>
#import "BAZFSUtility.h"

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSDebugLLog(@"gwcomp", @"=================================================================");
    NSDebugLLog(@"gwcomp", @"=== ZFS UTILITY TEST PROGRAM ===");
    NSDebugLLog(@"gwcomp", @"=================================================================");
    
    // Test 1: Check ZFS availability
    NSDebugLLog(@"gwcomp", @"\n--- TEST 1: ZFS Availability ---");
    BOOL zfsAvailable = [BAZFSUtility isZFSAvailable];
    NSDebugLLog(@"gwcomp", @"ZFS Available: %@", zfsAvailable ? @"YES" : @"NO");
    
    if (!zfsAvailable) {
        NSDebugLLog(@"gwcomp", @"ERROR: ZFS not available, cannot continue tests");
        [pool release];
        return 1;
    }
    
    // Test 2: Check if disk has ZFS pool
    NSDebugLLog(@"gwcomp", @"\n--- TEST 2: Disk ZFS Pool Check ---");
    NSString *testDisk = @"da0";
    BOOL hasPool = [BAZFSUtility diskHasZFSPool:testDisk];
    NSDebugLLog(@"gwcomp", @"Disk %@ has ZFS pool: %@", testDisk, hasPool ? @"YES" : @"NO");
    
    if (hasPool) {
        NSString *poolName = [BAZFSUtility getPoolNameFromDisk:testDisk];
        NSDebugLLog(@"gwcomp", @"Pool name on disk: %@", poolName ?: @"(unknown)");
        
        if (poolName) {
            // Test 3: Check if pool is imported
            NSDebugLLog(@"gwcomp", @"\n--- TEST 3: Pool Import Status ---");
            BOOL poolExists = [BAZFSUtility poolExists:poolName];
            NSDebugLLog(@"gwcomp", @"Pool '%@' is imported: %@", poolName, poolExists ? @"YES" : @"NO");
            
            // Test 4: Test destroy pool workflow (the critical test!)
            NSDebugLLog(@"gwcomp", @"\n--- TEST 4: Destroy Pool Workflow ---");
            NSDebugLLog(@"gwcomp", @"Testing the exact scenario that was failing...");
            
            if (poolExists) {
                NSDebugLLog(@"gwcomp", @"Pool is imported, testing export first...");
                BOOL exported = [BAZFSUtility exportPool:poolName];
                NSDebugLLog(@"gwcomp", @"Export result: %@", exported ? @"SUCCESS" : @"FAILURE");
            } else {
                NSDebugLLog(@"gwcomp", @"Pool is not imported (exported state)");
            }
            
            NSDebugLLog(@"gwcomp", @"Now testing destroy on exported pool...");
            BOOL destroyed = [BAZFSUtility destroyPool:poolName];
            NSDebugLLog(@"gwcomp", @"Destroy result: %@", destroyed ? @"SUCCESS" : @"FAILURE");
            
            if (destroyed) {
                NSDebugLLog(@"gwcomp", @"✅ SUCCESS: Destroy pool workflow completed successfully!");
                
                // Verify pool is really gone
                BOOL stillExists = [BAZFSUtility poolExists:poolName];
                NSDebugLLog(@"gwcomp", @"Pool still exists after destroy: %@", stillExists ? @"YES" : @"NO");
                
                // Check disk labels to see if pool data is gone
                BOOL diskStillHasPool = [BAZFSUtility diskHasZFSPool:testDisk];
                NSDebugLLog(@"gwcomp", @"Disk still has ZFS pool data: %@", diskStillHasPool ? @"YES" : @"NO");
            } else {
                NSDebugLLog(@"gwcomp", @"❌ FAILURE: Destroy pool workflow failed!");
            }
        }
    }
    
    // Test 5: Test creating a new pool
    NSDebugLLog(@"gwcomp", @"\n--- TEST 5: Create New Pool ---");
    NSString *newPoolName = @"test_backup_pool";
    NSDebugLLog(@"gwcomp", @"Testing pool creation: %@", newPoolName);
    
    BOOL created = [BAZFSUtility createPool:newPoolName onDisk:testDisk];
    NSDebugLLog(@"gwcomp", @"Pool creation result: %@", created ? @"SUCCESS" : @"FAILURE");
    
    if (created) {
        NSDebugLLog(@"gwcomp", @"✅ SUCCESS: Pool creation completed!");
        
        // Clean up - destroy the test pool
        NSDebugLLog(@"gwcomp", @"Cleaning up test pool...");
        BOOL cleanedUp = [BAZFSUtility destroyPool:newPoolName];
        NSDebugLLog(@"gwcomp", @"Cleanup result: %@", cleanedUp ? @"SUCCESS" : @"FAILURE");
    }
    
    NSDebugLLog(@"gwcomp", @"\n=================================================================");
    NSDebugLLog(@"gwcomp", @"=== ZFS UTILITY TEST COMPLETE ===");
    NSDebugLLog(@"gwcomp", @"=================================================================");
    
    [pool release];
    return 0;
}
