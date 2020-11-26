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


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    ABBVegetable *vegetable = [[ABBVegetable alloc] init];
    [vegetable grow];

    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

@end
