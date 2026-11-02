#import "ZDAppDelegate.h"
#import "ZDAppContainer.h"
#import "ZDHomeViewController.h"

@implementation ZDAppDelegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"[ZDAppDelegate] willFinishLaunching launchOptions=%@", launchOptions);
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"[ZDAppDelegate] didFinishLaunchingWithOptions launchOptions=%@", launchOptions);
    (void)ZDAppContainer.shared;
    [self application:application willFinishLaunchingWithOptions:launchOptions];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[ZDHomeViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
