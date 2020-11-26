//
//  SampleBoostApp
//  https://github.com/faithfracture/Apple-Boost-BuildScript
//
//  Distributed under the MIT License.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        AppDelegate *appDelegate = [[AppDelegate alloc] init];
        NSApplication.sharedApplication.delegate = appDelegate;
        [NSApplication.sharedApplication run];
    }
    return NSApplicationMain(argc, argv);
}
