#import "ZDAgnesSettingsStore.h"
#import <Security/Security.h>

static NSString *const ZDSettingsSuite = @"com.huobao.zdrama.objc";
static NSString *const ZDKeychainService = @"com.huobao.zdrama.objc";
static NSString *const ZDKeychainAccount = @"api_key";

static NSString *ZDNormalizeBaseURL(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return ZDAgnesSettingsDefaults().baseUrl;
    return [trimmed hasSuffix:@"/"] ? trimmed : [trimmed stringByAppendingString:@"/"];
}

static NSString *ZDBlankToDefault(NSString *value, NSString *fallback) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length == 0 ? fallback : trimmed;
}

@implementation ZDAgnesSettingsStore {
    NSUserDefaults *_defaults;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults ?: [[NSUserDefaults alloc] initWithSuiteName:ZDSettingsSuite];
    }
    return self;
}

- (instancetype)init {
    return [self initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:ZDSettingsSuite]];
}

- (NSString *)loadAPIKey {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: ZDKeychainService,
        (__bridge id)kSecAttrAccount: ZDKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || result == NULL) {
        return @"";
    }
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)saveAPIKey:(NSString *)apiKey {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: ZDKeychainService,
        (__bridge id)kSecAttrAccount: ZDKeychainAccount
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    if (apiKey.length == 0) return;
    NSMutableDictionary *add = [query mutableCopy];
    add[(__bridge id)kSecValueData] = [apiKey dataUsingEncoding:NSUTF8StringEncoding];
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

- (ZDAgnesSettings *)load {
    ZDAgnesSettings *defaults = ZDAgnesSettingsDefaults();
    ZDAgnesSettings *settings = [ZDAgnesSettings new];
    settings.apiKey = [self loadAPIKey];
    settings.baseUrl = [_defaults stringForKey:@"baseUrl"] ?: defaults.baseUrl;
    settings.textModel = [_defaults stringForKey:@"textModel"] ?: defaults.textModel;
    settings.imageModel = [_defaults stringForKey:@"imageModel"] ?: defaults.imageModel;
    settings.videoModel = [_defaults stringForKey:@"videoModel"] ?: defaults.videoModel;
    settings.requestTimeoutSeconds = [_defaults objectForKey:@"requestTimeoutSeconds"] ? [_defaults integerForKey:@"requestTimeoutSeconds"] : defaults.requestTimeoutSeconds;
    settings.customScriptCreatePrompt = [_defaults stringForKey:@"customScriptCreatePrompt"];
    settings.customScriptRewritePrompt = [_defaults stringForKey:@"customScriptRewritePrompt"];
    settings.customCharacterExtractPrompt = [_defaults stringForKey:@"customCharacterExtractPrompt"];
    settings.customStoryboardPrompt = [_defaults stringForKey:@"customStoryboardPrompt"];
    return settings;
}

- (void)save:(ZDAgnesSettings *)settings {
    ZDAgnesSettings *defaults = ZDAgnesSettingsDefaults();
    [self saveAPIKey:[settings.apiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @""];
    [_defaults setObject:ZDNormalizeBaseURL(settings.baseUrl) forKey:@"baseUrl"];
    [_defaults setObject:settings.textModel ?: @"" forKey:@"textModel"];
    [_defaults setObject:ZDBlankToDefault(settings.imageModel, defaults.imageModel) forKey:@"imageModel"];
    [_defaults setObject:ZDBlankToDefault(settings.videoModel, defaults.videoModel) forKey:@"videoModel"];
    [_defaults setInteger:settings.requestTimeoutSeconds > 0 ? settings.requestTimeoutSeconds : defaults.requestTimeoutSeconds forKey:@"requestTimeoutSeconds"];
    [_defaults setObject:settings.customScriptCreatePrompt forKey:@"customScriptCreatePrompt"];
    [_defaults setObject:settings.customScriptRewritePrompt forKey:@"customScriptRewritePrompt"];
    [_defaults setObject:settings.customCharacterExtractPrompt forKey:@"customCharacterExtractPrompt"];
    [_defaults setObject:settings.customStoryboardPrompt forKey:@"customStoryboardPrompt"];
}

@end
