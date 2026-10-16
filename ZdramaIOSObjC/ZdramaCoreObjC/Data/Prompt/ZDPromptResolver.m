#import "ZDPromptResolver.h"

NSString *ZDResolvePrompt(NSString *custom, NSString *fallback) {
    NSString *trimmed = [custom stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length == 0 ? (fallback ?: @"") : trimmed;
}
