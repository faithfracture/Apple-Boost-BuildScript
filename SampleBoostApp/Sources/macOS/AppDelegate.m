//
//  SampleBoostApp
//  https://github.com/faithfracture/Apple-Boost-BuildScript
//
//  Distributed under the MIT License.
//

#import "AppDelegate.h"
#import "ABBVegetable.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    ABBVegetable *vegetable = [[ABBVegetable alloc] init];
    [vegetable grow];
}

@end
