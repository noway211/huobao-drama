import { DramaRepository } from '../data/DramaRepository';
import { AgnesTextRepository, TextResult } from '../remote/AgnesTextRepository';
import { ChatResponseTextExtractor, ChatResponse } from '../remote/ChatResponseTextExtractor';
import { AgnesStoryboardRepository } from '../remote/AgnesStoryboardRepository';
import { AgnesImageRepository } from '../remote/AgnesImageRepository';
import { AgnesVideoRepository } from '../remote/AgnesVideoRepository';
import { MediaDownloadRepository, MediaType } from '../data/MediaDownloadRepository';
import { LocalMp4Composer } from '../data/media/LocalMp4Composer';
import { AppContext } from '../common/AppContext';
import { AgnesSettings } from '../model/AgnesSettings';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import {
  CreateDramaInput,
  DramaProject,
  Episode,
  Character,
  StoryboardShot,
  ProjectStatus,
  GenerationStage,
  AssetStatus,
  EpisodeStatus
} from '../model/DramaModels';

const DOMAIN = 0x0001;
const TAG = 'UseCases';

type GenerationProgressCallback = (current: number, total: number, shotNumber: number, phase: string) => void;

// 角色参考信息（buildCharacterReferences 返回值）
interface CharacterRefInfo {
  referenceUrls: string[];
  characterText: string;
}

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
  private static mp4Composer = new LocalMp4Composer();

  // 当前正在生成图片/视频的项目 ID 集合。
  // EntryAbility.onBackground 据此判断是否需要申请长时任务。
  private static activeGeneratingProjects: Set<number> = new Set();

  /** 是否存在正在生成图片/视频的项目（用于 EntryAbility 决定是否申请长时任务） */
  static hasActiveGenerating(): boolean {
    return UseCases.activeGeneratingProjects.size > 0;
  }

  private static markGenerating(projectId: number): void {
    UseCases.activeGeneratingProjects.add(projectId);
  }

  private static unmarkGenerating(projectId: number): void {
    UseCases.activeGeneratingProjects.delete(projectId);
  }

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

  // 获取项目的所有角色
  static getCharacters(projectId: number): Promise<Character[]> {
    return UseCases.repo.getCharacters(projectId);
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

  /** 更新单个角色的外貌提示词（即图片生成 prompt）。 */
  static async updateCharacterAppearance(characterId: number, appearance: string): Promise<void> {
    return UseCases.repo.updateCharacterAppearance(characterId, appearance);
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
    UseCases.markGenerating(projectId);
    try {
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

        // 收集角色参考图并增强 prompt
        const charRef: CharacterRefInfo = await UseCases.buildCharacterReferences(projectId, shot);
        const enrichedPrompt = charRef.characterText.length > 0
          ? `${charRef.characterText}${shot.imagePrompt}`
          : shot.imagePrompt;

        hilog.info(DOMAIN, TAG, 'generate image for shot %{public}d: prompt=%{public}s refs=%{public}d',
          shot.shotNumber, enrichedPrompt, charRef.referenceUrls.length);

        // 标记为处理中
        await UseCases.repo.updateShotImage(
          shot.id, AssetStatus.PROCESSING, shot.imageUrl, shot.imageLocalPath, null);

        onProgress?.(current, shots.length, shot.shotNumber, '生成图片');
        const imageResult = await UseCases.image.generateImage(
          settings, enrichedPrompt,
          charRef.referenceUrls.length > 0 ? charRef.referenceUrls : undefined);
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

      if (completed === shots.length) {
        // 全部成功（含已存在跳过）即视为成功
        return { ok: true, value: `${generated}`, error: '' };
      }
      if (generated > 0) {
        return { ok: true, value: `${generated}`, error: '' };
      }
      return { ok: false, value: '', error: firstError.length > 0 ? firstError : '图片生成失败' };
    } finally {
      UseCases.unmarkGenerating(projectId);
    }
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

    if (completed === shots.length) {
      // 全部成功（含已存在跳过）即视为成功
      return { ok: true, value: `${generated}`, error: '' };
    }
    if (generated > 0) {
      return { ok: true, value: `${generated}`, error: '' };
    }
    return { ok: false, value: '', error: firstError.length > 0 ? firstError : '视频生成失败' };
  }

  /** ExtractCharactersUseCase：从剧本文本中提取角色信息。参照 Web 版 extractor agent 流程。 */
  static async extractCharacters(projectId: number, settings: AgnesSettings): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: 'Project not found' };
    }

    const episode = await UseCases.repo.getEpisodeForProject(projectId);
    const script = episode?.scriptContent ?? project.generatedScript;
    if (!script || script.trim().length === 0) {
      return { ok: false, value: '', error: '请先创作或改写脚本' };
    }

    // 读取已有角色，传给 LLM 做去重参考
    const existingChars = await UseCases.repo.getCharacters(projectId);
    let existingHint = '';
    if (existingChars.length > 0) {
      const names = existingChars.map(c => c.name).join('、');
      existingHint = `\n\n项目中已存在角色：${names}。若剧本中同名角色已存在，请合并更新其信息（保留已有角色 id，用 existing_id 字段标记）；若为新角色则创建。`;
    }

    const systemPrompt = `你是制片助理，擅长从剧本中提取角色信息。

提取规范：
- 姓名：角色全名
- 角色定位：主角/配角/龙套
- 外貌描写：性别、年龄、体型、面部特征、发型、着装（50-100字）
- 性格特点：核心性格标签
- 角色描述：背景故事和关系

提取要求：
- 提取剧本中所有出场角色，不要遗漏任何有台词或重要动作的角色
- 角色要包含完整的外貌特征描述
- 只提取当前剧本真实出现的角色`;

    const userPrompt = `请从以下剧本中提取所有角色信息，返回 JSON 数组。
每个条目包含：name（角色名）、role（主角/配角/龙套）、description（角色描述）、appearance（外貌特征，用于生成角色立绘）、personality（性格特征）。
${existingChars.length > 0 ? '若角色已存在（名字匹配），请在条目中加 existing_id 字段标记已有角色的 id。' : ''}
只返回 JSON 数组。

剧本：
${script}${existingHint}`;

    const raw = await UseCases.text.postChat(settings, [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt }
    ], 0.3, 4000);
    if (!raw.ok) {
      return { ok: false, value: '', error: raw.error };
    }

    // 解析 ChatCompletion 响应，提取 content 文本
    let parsed: ChatResponse;
    try {
      parsed = JSON.parse(raw.value) as ChatResponse;
    } catch (e) {
      return { ok: false, value: '', error: '无法解析响应 JSON' };
    }
    const contentText = ChatResponseTextExtractor.extractFinalContent(parsed);
    if (contentText.trim().length === 0) {
      return { ok: false, value: '', error: 'Agnes 未返回角色信息' };
    }

    // 解析 JSON 数组
    let jsonStr = contentText.trim();
    if (!jsonStr.startsWith('[')) {
      const start = jsonStr.indexOf('[');
      const end = jsonStr.lastIndexOf(']');
      if (start >= 0 && end > start) {
        jsonStr = jsonStr.substring(start, end + 1);
      }
    }
    let items: Record<string, Object>[];
    try {
      items = JSON.parse(jsonStr) as Record<string, Object>[];
      if (!Array.isArray(items)) {
        return { ok: false, value: '', error: '角色提取结果格式错误' };
      }
    } catch (e) {
      return { ok: false, value: '', error: '无法解析角色提取结果' };
    }

    const now = Date.now();
    const characters: Character[] = [];

    // 先构建已有角色名→ID 的映射，用于去重合并
    const nameToExisting = new Map<string, Character>();
    for (const ch of existingChars) {
      nameToExisting.set(ch.name, ch);
    }

    for (const item of items) {
      const name = (typeof item['name'] === 'string' ? item['name'] : '') || '';
      if (name.length === 0) {
        continue;
      }
      const role = (typeof item['role'] === 'string' ? item['role'] : '') || '';
      const description = (typeof item['description'] === 'string' ? item['description'] : '') || '';
      const appearance = (typeof item['appearance'] === 'string' ? item['appearance'] : '') || '';
      const personality = (typeof item['personality'] === 'string' ? item['personality'] : '') || '';

      // 去重合并：同名角色保留已有 image 信息，更新文字描述（新数据优先，已有数据兜底）
      const existing = nameToExisting.get(name);
      characters.push({
        id: existing ? existing.id : 0,
        projectId: projectId,
        episodeId: episode?.id ?? null,
        name: name,
        role: role || (existing ? existing.role : ''),
        description: description || (existing ? existing.description : ''),
        appearance: appearance || (existing ? existing.appearance : ''),
        personality: personality || (existing ? existing.personality : ''),
        imageStatus: existing ? existing.imageStatus : AssetStatus.PENDING,
        imageUrl: existing ? existing.imageUrl : null,
        imageLocalPath: existing ? existing.imageLocalPath : null,
        imageErrorMessage: existing ? existing.imageErrorMessage : null,
        createdAt: existing ? existing.createdAt : now,
        updatedAt: now
      });
    }
    if (characters.length === 0) {
      return { ok: false, value: '', error: '未从剧本中提取到角色' };
    }

    await UseCases.repo.replaceCharacters(projectId, characters);
    hilog.info(DOMAIN, TAG, 'extractCharacters: project=%{public}d count=%{public}d', projectId, characters.length);
    return { ok: true, value: `${characters.length}`, error: '' };
  }

  /** GenerateCharacterImagesUseCase：为每个角色生成立绘图片。 */
  static async generateCharacterImages(
    projectId: number,
    settings: AgnesSettings,
    onProgress?: GenerationProgressCallback
  ): Promise<TextResult> {
    const project = await UseCases.repo.getProject(projectId);
    if (!project) {
      return { ok: false, value: '', error: 'Project not found' };
    }

    const characters = await UseCases.repo.getCharacters(projectId);
    if (characters.length === 0) {
      return { ok: false, value: '', error: '请先提取角色' };
    }

    hilog.info(DOMAIN, TAG, 'generateCharacterImages start: project=%{public}d characters=%{public}d', projectId, characters.length);

    let completed = 0;
    let generated = 0;
    let firstError = '';
    let current = 0;

    for (const ch of characters) {
      current++;
      onProgress?.(current, characters.length, current, '检查角色图');

      if (ch.imageStatus === AssetStatus.COMPLETED && UseCases.hasNonEmptyLocalFile(ch.imageLocalPath)) {
        hilog.info(DOMAIN, TAG, 'character %{public}s image already completed, skip', ch.name);
        completed++;
        continue;
      }

      await UseCases.repo.updateCharacterImage(
        ch.id, AssetStatus.PROCESSING, ch.imageUrl, ch.imageLocalPath, null);

      const prompt = `${ch.name}, ${ch.appearance || ch.description || '人物立绘'}, 高质量, 正面`;
      onProgress?.(current, characters.length, current, '生成角色图');
      const imageResult = await UseCases.image.generateImage(settings, prompt);
      if (imageResult.ok) {
        const charImageUrl = imageResult.value;
        onProgress?.(current, characters.length, current, '下载角色图');
        const downloadResult = await UseCases.mediaDownload.downloadCharImage(projectId, ch.id, charImageUrl);
        if (downloadResult.ok) {
          completed++;
          generated++;
          await UseCases.repo.updateCharacterImage(
            ch.id, AssetStatus.COMPLETED, charImageUrl, downloadResult.value, null);
        } else {
          if (firstError.length === 0) firstError = downloadResult.error;
          await UseCases.repo.updateCharacterImage(
            ch.id, AssetStatus.FAILED, charImageUrl, ch.imageLocalPath, downloadResult.error);
        }
      } else {
        if (firstError.length === 0) firstError = imageResult.error;
        await UseCases.repo.updateCharacterImage(
          ch.id, AssetStatus.FAILED, ch.imageUrl, ch.imageLocalPath, imageResult.error);
      }
    }

    hilog.info(DOMAIN, TAG, 'generateCharacterImages done: ok=%{public}d/%{public}d', completed, characters.length);
    if (completed === characters.length) {
      // 全部成功（含已存在跳过）即视为成功
      return { ok: true, value: `${generated}`, error: '' };
    }
    if (generated > 0) {
      return { ok: true, value: `${generated}`, error: '' };
    }
    return { ok: false, value: '', error: firstError.length > 0 ? firstError : '角色图生成失败' };
  }

  /** 为单个角色生成图片。从 generateCharacterImages 循环体中提取复用逻辑。 */
  static async generateSingleCharacterImage(
    projectId: number,
    characterId: number,
    settings: AgnesSettings
  ): Promise<TextResult> {
    const characters = await UseCases.repo.getCharacters(projectId);
    const ch = characters.find(c => c.id === characterId);
    if (!ch) {
      return { ok: false, value: '', error: '角色不存在' };
    }

    // 跳过已完成且有本地文件的
    if (ch.imageStatus === AssetStatus.COMPLETED && UseCases.hasNonEmptyLocalFile(ch.imageLocalPath)) {
      hilog.info(DOMAIN, TAG, 'character %{public}s image already completed, skip', ch.name);
      return { ok: true, value: '已存在', error: '' };
    }

    await UseCases.repo.updateCharacterImage(
      ch.id, AssetStatus.PROCESSING, ch.imageUrl, ch.imageLocalPath, null);

    const prompt = `${ch.name}, ${ch.appearance || ch.description || '人物立绘'}, 高质量, 正面`;
    const imageResult = await UseCases.image.generateImage(settings, prompt);
    if (imageResult.ok) {
      const charImageUrl = imageResult.value;
      const downloadResult = await UseCases.mediaDownload.downloadCharImage(projectId, ch.id, charImageUrl);
      if (downloadResult.ok) {
        await UseCases.repo.updateCharacterImage(
          ch.id, AssetStatus.COMPLETED, charImageUrl, downloadResult.value, null);
        return { ok: true, value: downloadResult.value, error: '' };
      } else {
        await UseCases.repo.updateCharacterImage(
          ch.id, AssetStatus.FAILED, charImageUrl, ch.imageLocalPath, downloadResult.error);
        return { ok: false, value: '', error: downloadResult.error };
      }
    } else {
      await UseCases.repo.updateCharacterImage(
        ch.id, AssetStatus.FAILED, ch.imageUrl, ch.imageLocalPath, imageResult.error);
      return { ok: false, value: '', error: imageResult.error };
    }
  }

  /**
   * 分镜图片生成时注入角色参考图。对于每个分镜，如果绑定了角色，则收集角色的已生成图片
   * 作为参考图，并增强 prompt 追加角色外貌描述。
   *
   * characterIds 可能是数字 ID 数组（remap 后）也可能是角色名字符串数组（LLM 直接返回），
   * 本方法对两种格式都做兼容处理。
   */
  private static async buildCharacterReferences(
    projectId: number,
    shot: StoryboardShot
  ): Promise<CharacterRefInfo> {
    const refs: string[] = [];
    const charDescs: string[] = [];

    // 尝试解析为数字 ID 数组
    let ids = UseCases.parseCharacterIds(shot.characterIds);

    // 如果解析出的全是数字，直接用 ID 匹配
    const allCharacters = await UseCases.repo.getCharacters(projectId);
    if (ids.length > 0 && allCharacters.length > 0) {
      const charMap = new Map<number, Character>();
      for (const ch of allCharacters) {
        charMap.set(ch.id, ch);
      }
      for (const cid of ids) {
        if (refs.length >= 3) break;
        const ch = charMap.get(cid);
        if (!ch) continue;
        const refUrl = (ch.imageLocalPath && UseCases.hasNonEmptyLocalFile(ch.imageLocalPath))
          ? ch.imageLocalPath : (ch.imageUrl ?? undefined);
        if (refUrl && refUrl.trim().length > 0) {
          refs.push(refUrl);
        }
        if (ch.appearance && ch.appearance.trim().length > 0) {
          charDescs.push(`${ch.name}：${ch.appearance}`);
        }
      }
      if (refs.length > 0) {
        const charText = charDescs.length > 0 ? charDescs.join('。') + '。\n' : '';
        const result: CharacterRefInfo = { referenceUrls: refs, characterText: charText };
        return result;
      }
    }

    // fallback：按角色名字符串匹配（LLM 返回的 character_names）
    let names: string[] = [];
    try {
      const arr: Object = JSON.parse(shot.characterIds ?? '[]');
      if (Array.isArray(arr)) {
        const filtered: string[] = [];
        for (let fi = 0; fi < arr.length; fi++) {
          if (typeof arr[fi] === 'string') {
            filtered.push(arr[fi] as string);
          }
        }
        names = filtered;
      }
    } catch (_e) { /* ignore */ }

    if (names.length > 0 && allCharacters.length > 0) {
      const nameToChar = new Map<string, Character>();
      for (const ch of allCharacters) {
        nameToChar.set(ch.name, ch);
      }
      for (const name of names) {
        if (refs.length >= 3) break;
        const ch = nameToChar.get(name);
        if (!ch) continue;
        const refUrl = (ch.imageLocalPath && UseCases.hasNonEmptyLocalFile(ch.imageLocalPath))
          ? ch.imageLocalPath : (ch.imageUrl ?? undefined);
        if (refUrl && refUrl.trim().length > 0) {
          refs.push(refUrl);
        }
        if (ch.appearance && ch.appearance.trim().length > 0) {
          charDescs.push(`${ch.name}：${ch.appearance}`);
        }
      }
    }

    const charText = charDescs.length > 0 ? charDescs.join('。') + '。\n' : '';
    const result: CharacterRefInfo = { referenceUrls: refs, characterText: charText };
    return result;
  }

  // 将 characterIds JSON 字符串解析为 number 数组
  private static parseCharacterIds(ids: string | null | undefined): number[] {
    if (!ids || ids.trim().length === 0) {
      return [];
    }
    try {
      const arr: Object = JSON.parse(ids);
      if (Array.isArray(arr)) {
        // 兼容字符名数组（LLM 返回 character_names 字符串数组）和数字 ID 数组
        const filtered: number[] = [];
        for (let fi = 0; fi < arr.length; fi++) {
          if (typeof arr[fi] === 'number') {
            filtered.push(arr[fi] as number);
          }
        }
        return filtered;
      }
      return [];
    } catch (_e) {
      return [];
    }
  }

  /** 角色名字匹配到数据库 ID，供分镜生成后调用。 */
  static async remapCharacterNamesToIds(projectId: number): Promise<void> {
    const shots = await UseCases.repo.getStoryboards(projectId);
    const characters = await UseCases.repo.getCharacters(projectId);
    const nameToId = new Map<string, number>();
    for (const ch of characters) {
      nameToId.set(ch.name, ch.id);
    }

    for (const shot of shots) {
      const ids = UseCases.parseCharacterIds(shot.characterIds);
      if (ids.length > 0) {
        continue; // already remapped
      }
      let raw: string[] = [];
      try {
        const arr: Object = JSON.parse(shot.characterIds ?? '[]');
        if (Array.isArray(arr)) {
          const filtered: string[] = [];
          for (let fi = 0; fi < arr.length; fi++) {
            if (typeof arr[fi] === 'string') {
              filtered.push(arr[fi] as string);
            }
          }
          raw = filtered;
        }
      } catch (_e) {
        continue;
      }
      const mapped: number[] = [];
      for (const name of raw) {
        const cid = nameToId.get(name);
        if (cid !== undefined) {
          mapped.push(cid);
        }
      }
      // 暂不更新数据库，仅记录日志；后续可在 refresh 时一并更新
      if (mapped.length > 0) {
        hilog.info(DOMAIN, TAG, 'remapped shot %{public}d character names to ids: %{public}s',
          shot.shotNumber, JSON.stringify(mapped));
      }
    }
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

    const filesDir = AppContext.get().filesDir;
    const outputPath = `${filesDir}/generated/${projectId}/final_video.mp4`;
    const inputPaths = sorted
      .map(s => s.videoLocalPath)
      .filter((p) => !!p && p.length > 0) as string[];

    let finalPath = '';
    try {
      finalPath = await UseCases.mp4Composer.compose(inputPaths, outputPath);
    } catch (e) {
      const msg = `视频合成失败：${(e as Error).message ?? String(e)}`;
      hilog.error(DOMAIN, TAG, 'composeFinalVideo failed: %{public}s', msg);
      await UseCases.repo.updateProjectFinalVideo(
        projectId, ProjectStatus.FAILED, GenerationStage.FINAL_VIDEO,
        AssetStatus.FAILED, null, msg, msg);
      return { ok: false, value: '', error: msg };
    }

    await UseCases.repo.updateProjectFinalVideo(
      projectId, ProjectStatus.COMPLETED, GenerationStage.FINAL_VIDEO,
      AssetStatus.COMPLETED, finalPath, null, null);
    hilog.info(DOMAIN, TAG, 'composeFinalVideo OK: path=%{public}s', finalPath);
    return { ok: true, value: finalPath, error: '' };
  }
}
