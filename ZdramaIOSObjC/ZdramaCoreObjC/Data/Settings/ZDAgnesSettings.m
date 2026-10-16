#import "ZDAgnesSettings.h"

ZDAgnesSettings *ZDAgnesSettingsDefaults(void) {
    ZDAgnesSettings *settings = [ZDAgnesSettings new];
    settings.apiKey = @"";
    settings.baseUrl = @"https://apihub.agnes-ai.com/";
    settings.textModel = @"agnes-2.0-flash";
    settings.imageModel = @"agnes-image-2.0-flash";
    settings.videoModel = @"agnes-video-v2.0";
    settings.requestTimeoutSeconds = 120;
    return settings;
}

@implementation ZDAgnesSettings
@end
