#import "ZDAppDelegate.h"
#import "ZDAppContainer.h"
#import "ZDHomeViewController.h"

@implementation ZDAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)ZDAppContainer.shared;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[ZDHomeViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
