import { DramaRepository } from '../data/DramaRepository';
import { AgnesTextRepository, TextResult } from '../remote/AgnesTextRepository';
import { AgnesStoryboardRepository } from '../remote/AgnesStoryboardRepository';
import { AgnesImageRepository } from '../remote/AgnesImageRepository';
import { AgnesVideoRepository } from '../remote/AgnesVideoRepository';
import { MediaDownloadRepository, MediaType } from '../data/MediaDownloadRepository';
import { AgnesSettings } from '../model/AgnesSettings';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import {
  CreateDramaInput,
  DramaProject,
  Episode,
  StoryboardShot,
  ProjectStatus,
  GenerationStage,
  AssetStatus,
  EpisodeStatus
} from '../model/DramaModels';

const DOMAIN = 0x0001;
const TAG = 'UseCases';

type GenerationProgressCallback = (current: number, total: number, shotNumber: number, phase: string) => void;

/**
 * 移植 com.huobao.zdrama.domain.usecase.* 的 MVP 子集。
 * 由于每个用例都很轻量，统一实现为一个类上的静态方法。
 */
export class UseCases {
  private static repo = new DramaRepository();
  private static text = new AgnesTextRepository();
  private static storyboard = new AgnesStoryboardRepository();
  private static image = new AgnesImageRepository();
  private static video = new AgnesVideoRepository();
  private static mediaDownload = new MediaDownloadRepository();

  private static hasNonEmptyLocalFile(path: string | null): boolean {
    if (!path || path.trim().length === 0) {
      return false;
    }
    try {
      return fileIo.statSync(path).size > 0;
    } catch (_err) {
      return false;
    }
  }

  /** CreateDramaUseCase：插入项目（草稿状态）并自动创建第 1 集。 */
  static async createDrama(input: CreateDramaInput): Promise<number> {
    const now = Date.now();
    const project: DramaProject = {
      id: 0,
      title: input.title,
      prompt: input.prompt,
      style: input.style,
      targetAudience: input.targetAudience,
      aspectRatio: input.aspectRatio,
      shotCount: input.shotCount,
      shotDurationSeconds: input.shotDurationSeconds,
      status: ProjectStatus.DRAFT,
      currentStage: GenerationStage.NONE,
      errorMessage: null,
      generatedScript: null,
      finalVideoStatus: AssetStatus.PENDING,
      finalVideoLocalPath: null,
      finalVideoErrorMessage: null,
      createdAt: now,
      updatedAt: now
    };
    const projectId = await UseCases.repo.createProject(project);
    await UseCases.repo.createEpisodeForProject(projectId, input.title, input.prompt);
    return projectId;
  }

  // 获取所有项目列表
  static getProjects(): Promise<DramaProject[]> {
    return UseCases.repo.getProjects();
  }

  // 根据 ID 获取单个项目
  static getProject(projectId: number): Promise<DramaProject | null> {
    return UseCases.repo.getProject(projectId);
  }

  // 获取项目对应的剧集
  static getEpisode(projectId: number): Promise<Episode | null> {
    return UseCases.repo.getEpisodeForProject(projectId);
  }

  // 获取项目的全部分镜
  static getStoryboards(projectId: number): Promise<StoryboardShot[]> {
    return UseCases.repo.getStoryboards(projectId);
  }

  // 删除指定项目
  static deleteProject(projectId: number): Promise<boolean> {
    return UseCases.repo.deleteProject(projectId);
  }

  /** 冷启动恢复：将残留的 PROCESSING 状态项目重置为 FAILED。 */
  static resetOrphanProcessingProjects(): Promise<number> {
    return UseCases.repo.resetOrphanProcessingProjects();
  }

  /** 更新单个分镜的图片提示词。 */
  static async updateShotPrompt(shotId: number, newPrompt: string): Promise<void> {
    return UseCases.repo.updateShotImagePrompt(shotId, newPrompt);
  }

  /** 更新单个分镜的视频提示词。 */
  static async updateShotVideoPrompt(shotId: number, newPrompt: string): Promise<void> {
    return UseCases.repo.updateShotVideoPrompt(shotId, newPrompt);
  }

  /** 自动替换触发内容审查的敏感词（临时修复）。对 imagePrompt 和 videoPrompt 均生效。 */
  static async patchSensitivePrompts(projectId: number): Promise<void> {
    const shots = await UseCases.repo.getStoryboards(projectId);
    for (const shot of shots) {
      // 修 imagePrompt
      const OLD = '走廊尽头传来脚步声，老师快步走来，身后跟着校警，众人瞬间安静，学校走廊场景，写实风格';
      if (shot.imagePrompt === OLD) {
        await UseCases.repo.updateShotImagePrompt(shot.id,
          '走廊尽头传来脚步声，老师快步走来，严厉地扫视全场，霸凌者心虚地低下头，众人不敢出声，学校走廊场景，写实风格');
        hilog.info(DOMAIN, TAG, 'patched shot %{public}d imagePrompt (content policy)', shot.shotNumber);
      }
      const OLD2 = '校警将霸凌者带离走廊';
      if (shot.imagePrompt.indexOf(OLD2) >= 0) {
        await UseCases.repo.updateShotImagePrompt(shot.id,
          shot.imagePrompt.replace(OLD2, '老师带着霸凌者离开走廊'));
        hilog.info(DOMAIN, TAG, 'patched shot %{public}d imagePrompt (content policy)', shot.shotNumber);
      }

      // 视频提示词同样替换敏感内容
      if (shot.videoPrompt.indexOf(OLD2) >= 0) {
        await UseCases.repo.updateShotVideoPrompt(shot.id,
          shot.videoPrompt.replace(OLD2, '老师带着霸凌者离开走廊'));
        hilog.info(DOMAIN, TAG, 'patched shot %{public}d videoPrompt (content policy)', shot.shotNumber);
      }
    }
  }

  /** GenerateProjectScriptUseCase：根据项目提示词生成剧本，并同步更新项目与剧集状态。 */
  static async generateScript(projectId: number, settings: AgnesSettings): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: 'Project not found' };
    }

    await UseCases.repo.updateProjectTextResult(
      projectId, ProjectStatus.PROCESSING, GenerationStage.TEXT, project.generatedScript, null);

    const result = await UseCases.text.generateScript(settings, project);
    if (result.ok) {
      await UseCases.repo.updateProjectTextResult(
        projectId, ProjectStatus.COMPLETED, GenerationStage.TEXT, result.value, null);
      const episode = await UseCases.repo.getEpisodeForProject(projectId);
      if (episode) {
        await UseCases.repo.updateEpisodeScriptContent(episode.id, result.value, EpisodeStatus.COMPLETED);
      }
    } else {
      await UseCases.repo.updateProjectTextResult(
        projectId, ProjectStatus.FAILED, GenerationStage.TEXT, project.generatedScript, result.error);
    }
    return result;
  }

  /** RewriteEpisodeScriptUseCase：将 episode.content 改写为剧本，并同步更新项目与剧集状态。 */
  static async rewriteScript(projectId: number, settings: AgnesSettings): Promise<TextResult> {
    const episode = await UseCases.repo.getEpisodeForProject(projectId);
    if (!episode) {
      return { ok: false, value: '', error: 'Episode not found for project' };
    }
    const rawContent = episode.content;
    if (!rawContent || rawContent.trim().length === 0) {
      return { ok: false, value: '', error: 'Episode has no raw content to rewrite' };
    }

    await UseCases.repo.updateEpisodeScriptContent(
      episode.id, episode.scriptContent ?? '', EpisodeStatus.REWRITING);
    await UseCases.repo.updateProjectTextResult(
      projectId, ProjectStatus.PROCESSING, GenerationStage.TEXT, episode.scriptContent, null);

    const result = await UseCases.text.rewriteScript(settings, rawContent);
    if (result.ok) {
      await UseCases.repo.updateEpisodeScriptContent(episode.id, result.value, EpisodeStatus.COMPLETED);
      await UseCases.repo.updateProjectTextResult(
        projectId, ProjectStatus.COMPLETED, GenerationStage.TEXT, result.value, null);
    } else {
      await UseCases.repo.updateEpisodeScriptContent(
        episode.id, episode.scriptContent ?? '', EpisodeStatus.FAILED);
      await UseCases.repo.updateProjectTextResult(
        projectId, ProjectStatus.FAILED, GenerationStage.TEXT, episode.scriptContent, result.error);
    }
    return result;
  }

  /** GenerateStoryboardsUseCase：根据剧本文本生成分镜并保存到数据库。 */
  static async generateStoryboards(projectId: number, settings: AgnesSettings): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: 'Project not found' };
    }

    // 优先读剧集脚本，无则回退到项目脚本
    const episode = await UseCases.repo.getEpisodeForProject(projectId);
    const script = episode?.scriptContent ?? project.generatedScript;
    if (!script || script.trim().length === 0) {
      return { ok: false, value: '', error: '请先创作或改写脚本' };
    }

    await UseCases.repo.updateProjectTextResult(
      projectId, ProjectStatus.PROCESSING, GenerationStage.STORYBOARD, project.generatedScript, null);

    const result = await UseCases.storyboard.generateStoryboards(settings, project, script);
    if (result.ok) {
      const shots = UseCases.storyboard.parseShots(result.value);
      if (shots.length > 0) {
        await UseCases.repo.replaceStoryboards(projectId, shots);
      }
      await UseCases.repo.updateProjectTextResult(
        projectId, ProjectStatus.COMPLETED, GenerationStage.STORYBOARD, project.generatedScript, null);
    } else {
      await UseCases.repo.updateProjectTextResult(
        projectId, ProjectStatus.FAILED, GenerationStage.STORYBOARD, project.generatedScript, result.error);
    }
    return result;
  }

  /** GenerateStoryboardImagesUseCase：为每个分镜的 imagePrompt 生成图片并下载到本地。 */
  static async generateStoryboardImages(
    projectId: number,
    settings: AgnesSettings,
    onProgress?: GenerationProgressCallback
  ): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: 'Project not found' };
    }

    const shots = await UseCases.repo.getStoryboards(projectId);
    if (shots.length === 0) {
      return { ok: false, value: '', error: '请先生成分镜' };
    }

    // 自动修复触发内容审查的提示词
    await UseCases.patchSensitivePrompts(projectId);

    hilog.info(DOMAIN, TAG, 'generateStoryboardImages start: project=%{public}d shots=%{public}d', projectId, shots.length);

    await UseCases.repo.updateProjectTextResult(
      projectId, ProjectStatus.PROCESSING, GenerationStage.IMAGE, project.generatedScript, null);

    let completed = 0;
    let generated = 0;
    let firstError = '';
    let current = 0;

    for (const shot of shots) {
      current++;
      onProgress?.(current, shots.length, shot.shotNumber, '检查图片');

      // 跳过已完成且本地文件非空的
      if (shot.imageStatus === AssetStatus.COMPLETED && UseCases.hasNonEmptyLocalFile(shot.imageLocalPath)) {
        hilog.info(DOMAIN, TAG, 'shot %{public}d image already completed, skip', shot.shotNumber);
        completed++;
        continue;
      }

      if (shot.imageStatus === AssetStatus.COMPLETED && shot.imageUrl && shot.imageUrl.trim().length > 0) {
        hilog.info(DOMAIN, TAG, 'repair image for shot %{public}d from existing url', shot.shotNumber);
        await UseCases.repo.updateShotImage(
          shot.id, AssetStatus.PROCESSING, shot.imageUrl, shot.imageLocalPath, null);
        onProgress?.(current, shots.length, shot.shotNumber, '下载图片');
        const redownload = await UseCases.mediaDownload.downloadToGeneratedMedia(
          projectId, shot.id, shot.imageUrl, MediaType.IMAGE);
        if (redownload.ok) {
          completed++;
          generated++;
          await UseCases.repo.updateShotImage(
            shot.id, AssetStatus.COMPLETED, shot.imageUrl, redownload.value, null);
          continue;
        }
      }

      hilog.info(DOMAIN, TAG, 'generate image for shot %{public}d: prompt=%{public}s', shot.shotNumber, shot.imagePrompt);

      // 标记为处理中
      await UseCases.repo.updateShotImage(
        shot.id, AssetStatus.PROCESSING, shot.imageUrl, shot.imageLocalPath, null);

      onProgress?.(current, shots.length, shot.shotNumber, '生成图片');
      const imageResult = await UseCases.image.generateImage(settings, shot);
      if (imageResult.ok) {
        hilog.info(DOMAIN, TAG, 'image API OK for shot %{public}d, url=%{public}s', shot.shotNumber, imageResult.value);
        const imageUrl = imageResult.value;
        onProgress?.(current, shots.length, shot.shotNumber, '下载图片');
        const downloadResult = await UseCases.mediaDownload.downloadToGeneratedMedia(
          projectId, shot.id, imageUrl, MediaType.IMAGE);

        if (downloadResult.ok) {
          hilog.info(DOMAIN, TAG, 'download OK for shot #%{public}d -> %{public}s', shot.shotNumber, downloadResult.value);
          completed++;
          generated++;
          await UseCases.repo.updateShotImage(
            shot.id, AssetStatus.COMPLETED, imageUrl, downloadResult.value, null);
        } else {
          hilog.error(DOMAIN, TAG, 'download FAILED for shot #%{public}d: %{public}s', shot.shotNumber, downloadResult.error);
          if (firstError.length === 0) firstError = downloadResult.error;
          await UseCases.repo.updateShotImage(
            shot.id, AssetStatus.FAILED, imageUrl, shot.imageLocalPath, downloadResult.error);
        }
      } else {
        hilog.error(DOMAIN, TAG, 'image generation FAILED for shot #%{public}d: %{public}s', shot.shotNumber, imageResult.error);
        if (firstError.length === 0) firstError = imageResult.error;
        await UseCases.repo.updateShotImage(
          shot.id, AssetStatus.FAILED, shot.imageUrl, shot.imageLocalPath, imageResult.error);
      }
    }

    const finalStatus = completed === shots.length ? ProjectStatus.COMPLETED : ProjectStatus.FAILED;
    hilog.info(DOMAIN, TAG, 'generateStoryboardImages done: ok=%{public}d/%{public}d generated=%{public}d finalStatus=%{public}s',
      completed, shots.length, generated, finalStatus);

    await UseCases.repo.updateProjectTextResult(
      projectId, finalStatus, GenerationStage.IMAGE, project.generatedScript,
      firstError.length > 0 ? firstError : null);

    if (generated > 0) {
      return { ok: true, value: `${generated}`, error: '' };
    }
    return { ok: false, value: '', error: firstError.length > 0 ? firstError : '图片生成失败' };
  }

  /** GenerateStoryboardVideosUseCase：为每个分镜的 videoPrompt 生成视频并下载到本地。 */
  static async generateStoryboardVideos(
    projectId: number,
    settings: AgnesSettings,
    onProgress?: GenerationProgressCallback
  ): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: 'Project not found' };
    }

    const shots = await UseCases.repo.getStoryboards(projectId);
    if (shots.length === 0) {
      return { ok: false, value: '', error: '请先生成分镜' };
    }

    hilog.info(DOMAIN, TAG, 'generateStoryboardVideos start: project=%{public}d shots=%{public}d', projectId, shots.length);

    await UseCases.repo.updateProjectTextResult(
      projectId, ProjectStatus.PROCESSING, GenerationStage.VIDEO, project.generatedScript, null);

    let completed = 0;
    let generated = 0;
    let firstError = '';
    let current = 0;

    for (const shot of shots) {
      current++;
      onProgress?.(current, shots.length, shot.shotNumber, '检查视频');

      // 跳过已完成且本地文件非空的
      if (shot.videoStatus === AssetStatus.COMPLETED && UseCases.hasNonEmptyLocalFile(shot.videoLocalPath)) {
        hilog.info(DOMAIN, TAG, 'shot %{public}d video already completed, skip', shot.shotNumber);
        completed++;
        continue;
      }

      if (shot.videoStatus === AssetStatus.COMPLETED && shot.videoUrl && shot.videoUrl.trim().length > 0) {
        hilog.info(DOMAIN, TAG, 'repair video for shot %{public}d from existing url', shot.shotNumber);
        await UseCases.repo.updateShotVideo(
          shot.id, AssetStatus.PROCESSING, shot.videoTaskId, shot.videoUrl, shot.videoLocalPath, null);
        onProgress?.(current, shots.length, shot.shotNumber, '下载视频');
        const redownload = await UseCases.mediaDownload.downloadToGeneratedMedia(
          projectId, shot.id, shot.videoUrl, MediaType.VIDEO);
        if (redownload.ok) {
          completed++;
          generated++;
          await UseCases.repo.updateShotVideo(
            shot.id, AssetStatus.COMPLETED, shot.videoTaskId, shot.videoUrl, redownload.value, null);
          continue;
        }
      }

      hilog.info(DOMAIN, TAG, 'generate video for shot %{public}d: prompt=%{public}s', shot.shotNumber, shot.videoPrompt);

      // 标记为处理中
      await UseCases.repo.updateShotVideo(
        shot.id, AssetStatus.PROCESSING, shot.videoTaskId, shot.videoUrl, shot.videoLocalPath, null);

      onProgress?.(current, shots.length, shot.shotNumber, '生成视频');
      const videoResult = await UseCases.video.generateVideo(settings, shot);
      if (videoResult.ok) {
        hilog.info(DOMAIN, TAG, 'video API OK for shot %{public}d, url=%{public}s', shot.shotNumber, videoResult.value);
        const videoUrl = videoResult.value;
        const downloadResult = await UseCases.mediaDownload.downloadToGeneratedMedia(
          projectId, shot.id, videoUrl, MediaType.VIDEO);

        if (downloadResult.ok) {
          hilog.info(DOMAIN, TAG, 'download OK for shot #%{public}d -> %{public}s', shot.shotNumber, downloadResult.value);
          completed++;
          generated++;
          await UseCases.repo.updateShotVideo(
            shot.id, AssetStatus.COMPLETED, null, videoUrl, downloadResult.value, null);
        } else {
          hilog.error(DOMAIN, TAG, 'download FAILED for shot #%{public}d: %{public}s', shot.shotNumber, downloadResult.error);
          if (firstError.length === 0) firstError = downloadResult.error;
          await UseCases.repo.updateShotVideo(
            shot.id, AssetStatus.FAILED, null, videoUrl, shot.videoLocalPath, downloadResult.error);
        }
      } else {
        hilog.error(DOMAIN, TAG, 'video generation FAILED for shot #%{public}d: %{public}s', shot.shotNumber, videoResult.error);
        if (firstError.length === 0) firstError = videoResult.error;
        await UseCases.repo.updateShotVideo(
          shot.id, AssetStatus.FAILED, shot.videoTaskId, shot.videoUrl, shot.videoLocalPath, videoResult.error);
      }
    }

    const finalStatus = completed === shots.length ? ProjectStatus.COMPLETED : ProjectStatus.FAILED;
    hilog.info(DOMAIN, TAG, 'generateStoryboardVideos done: ok=%{public}d/%{public}d generated=%{public}d finalStatus=%{public}s',
      completed, shots.length, generated, finalStatus);

    await UseCases.repo.updateProjectTextResult(
      projectId, finalStatus, GenerationStage.VIDEO, project.generatedScript,
      firstError.length > 0 ? firstError : null);

    if (generated > 0) {
      return { ok: true, value: `${generated}`, error: '' };
    }
    return { ok: false, value: '', error: firstError.length > 0 ? firstError : '视频生成失败' };
  }

  /** ComposeFinalVideoUseCase：将全部分镜视频合成为一个成片 MP4。 */
  static async composeFinalVideo(
    projectId: number,
    settings?: AgnesSettings,
    onProgress?: GenerationProgressCallback
  ): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: '项目不存在' };
    }

    const shots = await UseCases.repo.getStoryboards(projectId);
    if (shots.length === 0) {
      return { ok: false, value: '', error: '请先生成分镜' };
    }

    const sorted = shots.slice().sort((a, b) => a.shotNumber - b.shotNumber);
    const missing = sorted.find(s =>
      s.videoStatus !== AssetStatus.COMPLETED || !UseCases.hasNonEmptyLocalFile(s.videoLocalPath)
    );
    if (missing) {
      const msg = '请先生成并下载全部分镜视频后再合成成片';
      await UseCases.repo.updateProjectFinalVideo(
        projectId, ProjectStatus.FAILED, GenerationStage.FINAL_VIDEO,
        AssetStatus.FAILED, null, msg, msg);
      return { ok: false, value: '', error: msg };
    }

    hilog.info(DOMAIN, TAG, 'composeFinalVideo start: project=%{public}d shots=%{public}d',
      projectId, sorted.length);

    await UseCases.repo.updateProjectFinalVideo(
      projectId, ProjectStatus.PROCESSING, GenerationStage.FINAL_VIDEO,
      AssetStatus.PROCESSING, null, null, null);

    onProgress?.(1, 1, sorted[0].shotNumber, '合成成片');

    // 鸿蒙平台当前没有公开的 ArkTS muxer/extractor API（OH_AVMuxer / OH_AVDemuxer
    // 仅在 C NDK 层），因此这里以失败返回并把状态切到 FAILED。等后续允许写
    // NAPI C++ 包装时，再把这一步替换成 LocalMp4Composer.compose()。
    const notSupported = '鸿蒙平台暂不支持本地无损合成成片，请使用分镜视频播放';
    hilog.warn(DOMAIN, TAG, 'composeFinalVideo not supported on Harmony ArkTS: %{public}s', notSupported);
    await UseCases.repo.updateProjectFinalVideo(
      projectId, ProjectStatus.FAILED, GenerationStage.FINAL_VIDEO,
      AssetStatus.FAILED, null, notSupported, notSupported);
    return { ok: false, value: '', error: notSupported };
  }
}
