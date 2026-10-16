#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ZDProjectStatusFromPersisted(NSString *_Nullable value);
FOUNDATION_EXPORT NSString *ZDGenerationStageFromPersisted(NSString *_Nullable value);
FOUNDATION_EXPORT NSString *ZDAssetStatusFromPersisted(NSString *_Nullable value);
FOUNDATION_EXPORT NSString *ZDEpisodeStatusFromPersisted(NSString *_Nullable value);

@interface ZDCreateDramaInput : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, copy) NSString *style;
@property (nonatomic, copy) NSString *targetAudience;
@property (nonatomic, copy) NSString *aspectRatio;
@property (nonatomic) NSInteger shotCount;
@property (nonatomic) NSInteger shotDurationSeconds;
+ (instancetype)inputWithTitle:(NSString *)title
                        prompt:(NSString *)prompt
                         style:(NSString *)style
                targetAudience:(NSString *)targetAudience
                   aspectRatio:(NSString *)aspectRatio
                     shotCount:(NSInteger)shotCount
           shotDurationSeconds:(NSInteger)shotDurationSeconds;
@end

@interface ZDDramaProject : NSObject
@property (nonatomic) int64_t id;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, copy) NSString *style;
@property (nonatomic, copy) NSString *targetAudience;
@property (nonatomic, copy) NSString *aspectRatio;
@property (nonatomic) NSInteger shotCount;
@property (nonatomic) NSInteger shotDurationSeconds;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *currentStage;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, copy, nullable) NSString *generatedScript;
@property (nonatomic, copy) NSString *finalVideoStatus;
@property (nonatomic, copy, nullable) NSString *finalVideoLocalPath;
@property (nonatomic, copy, nullable) NSString *finalVideoErrorMessage;
@property (nonatomic) int64_t createdAt;
@property (nonatomic) int64_t updatedAt;
@end

@interface ZDEpisode : NSObject
@property (nonatomic) int64_t id;
@property (nonatomic) int64_t projectId;
@property (nonatomic) NSInteger episodeNumber;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *content;
@property (nonatomic, copy, nullable) NSString *scriptContent;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *finalVideoStatus;
@property (nonatomic, copy, nullable) NSString *finalVideoLocalPath;
@property (nonatomic, copy, nullable) NSString *finalVideoErrorMessage;
@property (nonatomic) int64_t createdAt;
@property (nonatomic) int64_t updatedAt;
@end

@interface ZDStoryboardShot : NSObject
@property (nonatomic) int64_t id;
@property (nonatomic) int64_t projectId;
@property (nonatomic) int64_t episodeId;
@property (nonatomic) BOOL episodeIdIsNull;
@property (nonatomic) NSInteger shotNumber;
@property (nonatomic, copy) NSString *scene;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *dialogue;
@property (nonatomic, copy) NSString *camera;
@property (nonatomic, copy) NSString *imagePrompt;
@property (nonatomic, copy) NSString *videoPrompt;
@property (nonatomic) NSInteger durationSeconds;
@property (nonatomic, copy) NSArray<NSString *> *characterNames;
@property (nonatomic, copy, nullable) NSString *characterIds;
@property (nonatomic, copy) NSString *imageStatus;
@property (nonatomic, copy, nullable) NSString *imageUrl;
@property (nonatomic, copy, nullable) NSString *imageLocalPath;
@property (nonatomic, copy, nullable) NSString *imageErrorMessage;
@property (nonatomic, copy) NSString *videoStatus;
@property (nonatomic, copy, nullable) NSString *videoTaskId;
@property (nonatomic, copy, nullable) NSString *videoUrl;
@property (nonatomic, copy, nullable) NSString *videoLocalPath;
@property (nonatomic, copy, nullable) NSString *videoErrorMessage;
@property (nonatomic) int64_t createdAt;
@property (nonatomic) int64_t updatedAt;
@end

@interface ZDCharacter : NSObject
@property (nonatomic) int64_t id;
@property (nonatomic) int64_t projectId;
@property (nonatomic) int64_t episodeId;
@property (nonatomic) BOOL episodeIdIsNull;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *role;
@property (nonatomic, copy) NSString *characterDescription;
@property (nonatomic, copy) NSString *appearance;
@property (nonatomic, copy) NSString *personality;
@property (nonatomic, copy) NSString *imageStatus;
@property (nonatomic, copy, nullable) NSString *imageUrl;
@property (nonatomic, copy, nullable) NSString *imageLocalPath;
@property (nonatomic, copy, nullable) NSString *imageErrorMessage;
@property (nonatomic) int64_t createdAt;
@property (nonatomic) int64_t updatedAt;
@end

NS_ASSUME_NONNULL_END
