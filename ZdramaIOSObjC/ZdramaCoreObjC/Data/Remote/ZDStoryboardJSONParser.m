#import "ZDStoryboardJSONParser.h"

static NSString *const ZDStoryboardDomain = @"ZDStoryboardJSONParser";

static NSString *ZDStringField(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *ZDOptionalString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

NSArray<NSDictionary *> *ZDParseStoryboardJSON(NSString *content, NSError **error) {
    NSRange start = [content rangeOfString:@"["];
    NSRange end = [content rangeOfString:@"]" options:NSBackwardsSearch];
    if (start.location == NSNotFound || end.location == NSNotFound || start.location >= end.location) {
        if (error) {
            *error = [NSError errorWithDomain:ZDStoryboardDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Agnes storyboard response is not JSON"}];
        }
        return nil;
    }
    NSString *json = [content substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
    id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
    if (![parsed isKindOfClass:NSArray.class]) {
        if (error && *error == nil) {
            *error = [NSError errorWithDomain:ZDStoryboardDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Agnes storyboard response is not JSON"}];
        }
        return nil;
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (id raw in parsed) {
        NSDictionary *item = [raw isKindOfClass:NSDictionary.class] ? raw : @{};
        NSMutableDictionary *normalized = [@{
            @"scene": ZDStringField(item[@"scene"]),
            @"action": ZDStringField(item[@"action"]),
            @"dialogue": ZDStringField(item[@"dialogue"]),
            @"camera": ZDStringField(item[@"camera"]),
            @"image_prompt": ZDStringField(item[@"image_prompt"]),
            @"video_prompt": ZDStringField(item[@"video_prompt"])
        } mutableCopy];
        NSString *shot = ZDOptionalString(item[@"shot_number"]);
        if (shot) normalized[@"shot_number"] = shot;
        NSString *duration = ZDOptionalString(item[@"duration_seconds"]);
        if (duration) normalized[@"duration_seconds"] = duration;
        if ([item[@"character_names"] isKindOfClass:NSArray.class]) {
            normalized[@"character_names"] = item[@"character_names"];
        }
        [items addObject:normalized];
    }
    return items;
}

NSInteger ZDCountSceneHeaders(NSString *script) {
    if (script.length == 0) return 0;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^##\\s*S\\d+\\b" options:NSRegularExpressionAnchorsMatchLines error:nil];
    return [regex numberOfMatchesInString:script options:0 range:NSMakeRange(0, script.length)];
}
