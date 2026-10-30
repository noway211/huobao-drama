#import "ZDExtractCharactersUseCase.h"
#import "ZDAgnesTextRepository.h"
#import "ZDPromptDefaults.h"
#import "ZDPromptResolver.h"

static BOOL ZDExtractBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDExtractError(NSString *message) {
    return [NSError errorWithDomain:@"ZDExtractCharactersUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *ZDKept(id incoming, NSString *previous) {
    NSString *value = [incoming isKindOfClass:NSString.class] ? incoming : @"";
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length == 0 ? (previous ?: @"") : trimmed;
}

@implementation ZDExtractCharactersUseCase {
    ZDDramaRepository *_repository;
    ZDAgnesTextRepository *_text;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session {
    self = [super init];
    if (self) {
        _repository = repository;
        _text = [[ZDAgnesTextRepository alloc] initWithSession:session];
    }
    return self;
}

- (NSString *)userPromptScript:(NSString *)script existing:(NSArray<ZDCharacter *> *)existing {
    NSString *existingIdLine = @"";
    NSString *hint = @"";
    if (existing.count > 0) {
        NSMutableArray *names = [NSMutableArray array];
        for (ZDCharacter *character in existing) [names addObject:character.name ?: @""];
        hint = [NSString stringWithFormat:@"\n\n项目中已存在角色：%@。若剧本中同名角色已存在，请合并更新其信息；若为新角色则创建。", [names componentsJoinedByString:@"、"]];
        existingIdLine = @"若角色已存在（名字匹配），请在条目中加 existing_id 字段标记已有角色的 id。\n";
    }
    return [NSString stringWithFormat:@"请从以下剧本中提取所有角色信息，返回 JSON 数组。\n每个条目包含：name（角色名）、role（主角/配角/龙套）、description（角色描述）、appearance（外貌特征，用于生成角色立绘）、personality（性格特征）。\n%@只返回 JSON 数组。\n\n剧本：\n%@%@", existingIdLine, script, hint];
}

- (NSArray<ZDCharacter *> *)parseContent:(NSString *)content projectId:(int64_t)projectId episodeId:(int64_t)episodeId existing:(NSArray<ZDCharacter *> *)existing error:(NSError **)error {
    NSRange start = [content rangeOfString:@"["];
    NSRange end = [content rangeOfString:@"]" options:NSBackwardsSearch];
    if (start.location == NSNotFound || end.location == NSNotFound || start.location >= end.location) {
        if (error) *error = ZDExtractError(@"无法解析角色提取结果");
        return nil;
    }
    NSString *slice = [content substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
    id json = [NSJSONSerialization JSONObjectWithData:[slice dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![json isKindOfClass:NSArray.class]) {
        if (error) *error = ZDExtractError(@"无法解析角色提取结果");
        return nil;
    }
    NSMutableDictionary<NSString *, ZDCharacter *> *byName = [NSMutableDictionary dictionary];
    for (ZDCharacter *character in existing) {
        NSString *name = [character.name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length) byName[name] = character;
    }
    NSMutableArray *characters = [NSMutableArray array];
    for (NSDictionary *item in json) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *name = ZDKept(item[@"name"], @"");
        if (name.length == 0) continue;
        ZDCharacter *prior = byName[name];
        ZDCharacter *character = [ZDCharacter new];
        character.id = prior.id;
        character.projectId = projectId;
        character.episodeId = episodeId;
        character.name = name;
        character.role = ZDKept(item[@"role"], prior.role);
        character.characterDescription = ZDKept(item[@"description"], prior.characterDescription);
        character.appearance = ZDKept(item[@"appearance"], prior.appearance);
        character.personality = ZDKept(item[@"personality"], prior.personality);
        character.imageStatus = prior.imageStatus.length ? prior.imageStatus : @"PENDING";
        character.imageUrl = prior.imageUrl;
        character.imageLocalPath = prior.imageLocalPath;
        character.imageErrorMessage = prior.imageErrorMessage;
        [characters addObject:character];
    }
    if (characters.count == 0) {
        if (error) *error = ZDExtractError(@"未从剧本中提取到角色");
        return nil;
    }
    return characters;
}

- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSInteger, NSError *))completion {
    if (![_repository getProject:projectId]) { completion(0, ZDExtractError(@"Project not found")); return; }
    ZDEpisode *episode = [_repository getEpisodeForProject:projectId];
    if (!episode || episode.id != episodeId) { completion(0, ZDExtractError(@"Episode not found")); return; }
    NSString *script = [episode.scriptContent stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (ZDExtractBlank(script)) { completion(0, ZDExtractError(@"请先为本集创作或改写脚本")); return; }

    NSArray<ZDCharacter *> *existing = [_repository getCharactersForProject:projectId];
    NSArray *messages = @[
        @{@"role": @"system", @"content": ZDResolvePrompt(settings.customCharacterExtractPrompt, ZDPromptDefaults.characterExtractPrompt)},
        @{@"role": @"user", @"content": [self userPromptScript:script existing:existing]}
    ];
    [_text completeSettings:settings messages:messages temperature:0.3 maxTokens:4000 completion:^(NSString *text, NSError *error) {
        if (error) { completion(0, error); return; }
        NSError *parseError = nil;
        NSArray<ZDCharacter *> *characters = [self parseContent:text projectId:projectId episodeId:episodeId existing:existing error:&parseError];
        if (parseError) { completion(0, parseError); return; }
        [self->_repository upsertCharacters:characters projectId:projectId];
        completion((NSInteger)characters.count, nil);
    }];
}

@end
