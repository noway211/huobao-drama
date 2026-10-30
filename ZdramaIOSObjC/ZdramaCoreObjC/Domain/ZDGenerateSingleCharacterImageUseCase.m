#import "ZDGenerateSingleCharacterImageUseCase.h"
#import "ZDAgnesImageRepository.h"
#import "ZDMediaDownloadRepository.h"
#import "ZDCharacterPortrait.h"

static NSError *ZDSingleCharacterError(NSString *message) {
    return [NSError errorWithDomain:@"ZDGenerateSingleCharacterImageUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDGenerateSingleCharacterImageUseCase {
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

- (void)executeProjectId:(int64_t)projectId characterId:(int64_t)characterId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSString *, NSError *))completion {
    ZDCharacter *character = nil;
    for (ZDCharacter *row in [_repository getCharactersForProject:projectId]) {
        if (row.id == characterId) { character = row; break; }
    }
    if (!character) { completion(nil, ZDSingleCharacterError(@"角色不存在")); return; }
    [_repository updateCharacterImageId:character.id status:@"PROCESSING" localPath:character.imageLocalPath url:character.imageUrl errorMessage:nil];
    [_images generateImageSettings:settings prompt:ZDCharacterPortraitPrompt(character) size:ZDCharacterTurnaroundSize completion:^(NSString *url, NSError *error) {
        if (error) {
            [self->_repository updateCharacterImageId:character.id status:@"FAILED" localPath:character.imageLocalPath url:character.imageUrl errorMessage:error.localizedDescription];
            completion(nil, error);
            return;
        }
        [self->_downloads downloadCharacterImageProjectId:projectId characterId:character.id url:url completion:^(NSString *path, NSError *downloadError) {
            if (downloadError) {
                [self->_repository updateCharacterImageId:character.id status:@"FAILED" localPath:character.imageLocalPath url:character.imageUrl errorMessage:downloadError.localizedDescription];
                completion(nil, downloadError);
                return;
            }
            [self->_repository updateCharacterImageId:character.id status:@"COMPLETED" localPath:path url:url errorMessage:nil];
            completion(path, nil);
        }];
    }];
}

@end
