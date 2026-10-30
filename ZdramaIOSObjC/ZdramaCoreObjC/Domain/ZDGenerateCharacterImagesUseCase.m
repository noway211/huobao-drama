#import "ZDGenerateCharacterImagesUseCase.h"
#import "ZDAgnesImageRepository.h"
#import "ZDMediaDownloadRepository.h"
#import "ZDCharacterPortrait.h"

static NSError *ZDCharacterImageError(NSString *message) {
    return [NSError errorWithDomain:@"ZDGenerateCharacterImagesUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDGenerateCharacterImagesUseCase {
    ZDDramaRepository *_repository;
    ZDAgnesImageRepository *_images;
    ZDMediaDownloadRepository *_downloads;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session filesRoot:(NSString *)filesRoot {
    self = [super init];
    if (self) {
        _repository = repository;
        _images = [[ZDAgnesImageRepository alloc] initWithSession:session];
        _downloads = [[ZDMediaDownloadRepository alloc] initWithSession:session filesRoot:filesRoot];
    }
    return self;
}

- (BOOL)fileExists:(NSString *)path {
    return path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:path];
}

- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId settings:(ZDAgnesSettings *)settings forceRegenerate:(BOOL)forceRegenerate completion:(void (^)(NSInteger, NSError *))completion {
    (void)episodeId;
    if (![_repository getProject:projectId]) { completion(0, ZDCharacterImageError(@"Project not found")); return; }
    NSArray<ZDCharacter *> *characters = [_repository getCharactersForProject:projectId];
    if (characters.count == 0) { completion(0, ZDCharacterImageError(@"请先提取角色")); return; }
    [self generateCharacters:characters index:0 projectId:projectId settings:settings forceRegenerate:forceRegenerate completed:0 generated:0 firstError:nil completion:completion];
}

- (void)generateCharacters:(NSArray<ZDCharacter *> *)characters
                     index:(NSUInteger)index
                 projectId:(int64_t)projectId
                  settings:(ZDAgnesSettings *)settings
           forceRegenerate:(BOOL)forceRegenerate
                 completed:(NSInteger)completed
                 generated:(NSInteger)generated
                firstError:(NSError *)firstError
                completion:(void (^)(NSInteger, NSError *))completion {
    if (index >= characters.count) {
        if (completed == (NSInteger)characters.count || generated > 0) completion(generated, nil);
        else completion(0, firstError ?: ZDCharacterImageError(@"角色图生成失败"));
        return;
    }
    ZDCharacter *character = characters[index];
    if (!forceRegenerate && [character.imageStatus isEqualToString:@"COMPLETED"] && [self fileExists:character.imageLocalPath]) {
        [self generateCharacters:characters index:index + 1 projectId:projectId settings:settings forceRegenerate:forceRegenerate completed:completed + 1 generated:generated firstError:firstError completion:completion];
        return;
    }
    [_repository updateCharacterImageId:character.id status:@"PROCESSING" localPath:character.imageLocalPath url:character.imageUrl errorMessage:nil];
    [_images generateImageSettings:settings prompt:ZDCharacterPortraitPrompt(character) size:ZDCharacterTurnaroundSize completion:^(NSString *url, NSError *error) {
        if (error) {
            [self->_repository updateCharacterImageId:character.id status:@"FAILED" localPath:character.imageLocalPath url:character.imageUrl errorMessage:error.localizedDescription];
            [self generateCharacters:characters index:index + 1 projectId:projectId settings:settings forceRegenerate:forceRegenerate completed:completed generated:generated firstError:firstError ?: error completion:completion];
            return;
        }
        [self->_downloads downloadCharacterImageProjectId:projectId characterId:character.id url:url completion:^(NSString *path, NSError *downloadError) {
            if (downloadError) {
                [self->_repository updateCharacterImageId:character.id status:@"FAILED" localPath:character.imageLocalPath url:character.imageUrl errorMessage:downloadError.localizedDescription];
                [self generateCharacters:characters index:index + 1 projectId:projectId settings:settings forceRegenerate:forceRegenerate completed:completed generated:generated firstError:firstError ?: downloadError completion:completion];
                return;
            }
            [self->_repository updateCharacterImageId:character.id status:@"COMPLETED" localPath:path url:url errorMessage:nil];
            [self generateCharacters:characters index:index + 1 projectId:projectId settings:settings forceRegenerate:forceRegenerate completed:completed + 1 generated:generated + 1 firstError:firstError completion:completion];
        }];
    }];
}

@end
