#import <Foundation/Foundation.h>
#import "ZDDramaModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^ZDFileExistsBlock)(NSString *path);

FOUNDATION_EXPORT NSError *_Nullable ZDPreflightStage(NSString *stage,
                                                      NSString *_Nullable apiKey,
                                                      NSString *_Nullable episodeContent,
                                                      NSString *_Nullable scriptContent,
                                                      NSArray<ZDStoryboardShot *> *shots,
                                                      ZDFileExistsBlock fileExists);

NS_ASSUME_NONNULL_END
