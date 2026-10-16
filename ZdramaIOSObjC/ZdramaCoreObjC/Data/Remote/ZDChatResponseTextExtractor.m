#import "ZDChatResponseTextExtractor.h"

static BOOL ZDIsBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSString *ZDTrimmed(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSDictionary *ZDObject(id json) {
    if ([json isKindOfClass:NSDictionary.class]) {
        return json;
    }
    if ([json isKindOfClass:NSData.class]) {
        id parsed = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
        return [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
    }
    return nil;
}

static NSArray *ZDArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *ZDString(NSDictionary *object, NSString *key) {
    id value = object[key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *ZDExtractContentText(id value);

static NSString *ZDExtractArrayText(NSArray *array) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id item in array) {
        NSString *text = ZDExtractContentText(item);
        if (!ZDIsBlank(text)) {
            [parts addObject:text];
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

static NSString *ZDExtractObjectText(NSDictionary *object) {
    NSString *text = ZDString(object, @"text");
    if (text) return text;
    text = ZDString(object, @"output_text");
    if (text) return text;
    text = ZDString(object, @"content");
    if (text) return text;
    NSArray *content = ZDArray(object[@"content"]);
    if (content) return ZDExtractArrayText(content);
    return @"";
}

static NSString *ZDExtractContentText(id value) {
    if (value == nil || value == NSNull.null) return @"";
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSArray.class]) return ZDExtractArrayText(value);
    if ([value isKindOfClass:NSDictionary.class]) return ZDExtractObjectText(value);
    return @"";
}

static NSString *ZDFirstNonBlank(NSArray<NSString *> *values) {
    for (NSString *value in values) {
        if (!ZDIsBlank(value)) {
            return ZDTrimmed(value);
        }
    }
    return @"";
}

NSString *ZDChatFinishReason(id json) {
    NSDictionary *root = ZDObject(json);
    NSArray *choices = ZDArray(root[@"choices"]);
    NSDictionary *first = [choices.firstObject isKindOfClass:NSDictionary.class] ? choices.firstObject : nil;
    return ZDString(first, @"finish_reason") ?: @"";
}

NSString *ZDExtractFinalChatContent(id json) {
    NSDictionary *root = ZDObject(json);
    if (!root) return @"";
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *outputText = ZDString(root, @"output_text");
    if (outputText) [candidates addObject:outputText];
    for (id choice in ZDArray(root[@"choices"]) ?: @[]) {
        if (![choice isKindOfClass:NSDictionary.class]) continue;
        NSString *choiceText = ZDString(choice, @"text");
        if (choiceText) [candidates addObject:choiceText];
        NSDictionary *message = [choice[@"message"] isKindOfClass:NSDictionary.class] ? choice[@"message"] : nil;
        if (message) {
            if (message[@"content"]) [candidates addObject:ZDExtractContentText(message[@"content"])];
            NSString *messageText = ZDString(message, @"text");
            if (messageText) [candidates addObject:messageText];
        }
        NSDictionary *delta = [choice[@"delta"] isKindOfClass:NSDictionary.class] ? choice[@"delta"] : nil;
        if (delta[@"content"]) [candidates addObject:ZDExtractContentText(delta[@"content"])];
    }
    for (id item in ZDArray(root[@"output"]) ?: @[]) {
        [candidates addObject:ZDExtractContentText(item)];
    }
    return ZDFirstNonBlank(candidates);
}

NSString *ZDExtractChatContent(id json) {
    NSString *finalContent = ZDExtractFinalChatContent(json);
    if (!ZDIsBlank(finalContent)) return finalContent;
    NSDictionary *root = ZDObject(json);
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (id choice in ZDArray(root[@"choices"]) ?: @[]) {
        if (![choice isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *message = [choice[@"message"] isKindOfClass:NSDictionary.class] ? choice[@"message"] : nil;
        if (message[@"reasoning_content"]) {
            [candidates addObject:ZDExtractContentText(message[@"reasoning_content"])];
        }
    }
    return ZDFirstNonBlank(candidates);
}
