/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GSAssistantFramework.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSDebugLLog(@"gwcomp", @"=== Testing Localized Content Manager ===");
        
        // Test content availability
        NSDebugLLog(@"gwcomp", @"\n--- Content Availability Tests ---");
        BOOL hasWelcome = [GSLocalizedContentManager hasWelcomeContent];
        BOOL hasReadMe = [GSLocalizedContentManager hasReadMeContent];
        BOOL hasLicense = [GSLocalizedContentManager hasLicenseContent];
        
        NSDebugLLog(@"gwcomp", @"Welcome content available: %@", hasWelcome ? @"YES" : @"NO");
        NSDebugLLog(@"gwcomp", @"ReadMe content available: %@", hasReadMe ? @"YES" : @"NO");
        NSDebugLLog(@"gwcomp", @"License content available: %@", hasLicense ? @"YES" : @"NO");
        
        // Test content retrieval
        NSDebugLLog(@"gwcomp", @"\n--- Content Retrieval Tests ---");
        if (hasWelcome) {
            NSString *welcomeContent = [GSLocalizedContentManager welcomeContent];
            NSDebugLLog(@"gwcomp", @"Welcome content preview: %@...", 
                  [welcomeContent substringToIndex:MIN(80, welcomeContent.length)]);
        }
        
        if (hasReadMe) {
            NSString *readMeContent = [GSLocalizedContentManager readMeContent];
            NSDebugLLog(@"gwcomp", @"ReadMe content preview: %@...", 
                  [readMeContent substringToIndex:MIN(80, readMeContent.length)]);
        }
        
        if (hasLicense) {
            NSString *licenseContent = [GSLocalizedContentManager licenseContent];
            NSDebugLLog(@"gwcomp", @"License content preview: %@...", 
                  [licenseContent substringToIndex:MIN(80, licenseContent.length)]);
        }
        
        // Test step creation
        NSDebugLLog(@"gwcomp", @"\n--- Step Creation Tests ---");
        id<GSAssistantStepProtocol> welcomeStep = [GSLocalizedContentManager createWelcomeStep];
        id<GSAssistantStepProtocol> readMeStep = [GSLocalizedContentManager createReadMeStep];
        id<GSAssistantStepProtocol> licenseStep = [GSLocalizedContentManager createLicenseStep];
        
        NSDebugLLog(@"gwcomp", @"Welcome step created: %@", welcomeStep ? @"SUCCESS" : @"FAILED");
        NSDebugLLog(@"gwcomp", @"ReadMe step created: %@", readMeStep ? @"SUCCESS" : @"FAILED");
        NSDebugLLog(@"gwcomp", @"License step created: %@", licenseStep ? @"SUCCESS" : @"FAILED");
        
        if (welcomeStep) {
            NSDebugLLog(@"gwcomp", @"  Welcome step title: '%@'", [welcomeStep stepTitle]);
            NSDebugLLog(@"gwcomp", @"  Welcome step description: '%@'", [welcomeStep stepDescription]);
        }
        
        if (readMeStep) {
            NSDebugLLog(@"gwcomp", @"  ReadMe step title: '%@'", [readMeStep stepTitle]);
            NSDebugLLog(@"gwcomp", @"  ReadMe step description: '%@'", [readMeStep stepDescription]);
        }
        
        if (licenseStep) {
            NSDebugLLog(@"gwcomp", @"  License step title: '%@'", [licenseStep stepTitle]);
            NSDebugLLog(@"gwcomp", @"  License step description: '%@'", [licenseStep stepDescription]);
        }
        
        NSDebugLLog(@"gwcomp", @"\n=== Test Completed ===");
    }
    return 0;
}
