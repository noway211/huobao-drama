import { ProjectLocalDataSource } from './ProjectLocalDataSource';
import { EpisodeLocalDataSource } from './EpisodeLocalDataSource';
import { StoryboardLocalDataSource } from './StoryboardLocalDataSource';
import { CharacterLocalDataSource } from './CharacterLocalDataSource';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DramaProject,
  Episode,
  EpisodeStatus,
  ProjectStatus,
  GenerationStage,
  StoryboardShot,
  Character,
  AssetStatus
} from '../model/DramaModels';

// 删除单集时清理本地文件的日志 tag
const DOMAIN = 0x0001;
const TAG = 'DramaRepository';

// 删除本地文件（容错：不存在或失败均不抛出）
function unlinkIfExists(path: string | null, what: string): void {
  if (!path || path.trim().length === 0) {
    return;
  }
  try {
    fileIo.unlinkSync(path);
  } catch (e) {
    // 文件可能已不存在，容错
    hilog.warn(DOMAIN, TAG, 'unlink %{public}s failed for %{public}s: %{public}s',
      what, path, JSON.stringify(e));
  }
}

/**
 * Ports com.huobao.zdrama.data.repository.DramaRepository (MVP subset).
 * Facade over the project + episode local data sources.
 */
export class DramaRepository {
  private projects = new ProjectLocalDataSource();
  private episodes = new EpisodeLocalDataSource();
  private storyboards = new StoryboardLocalDataSource();
  private characters = new CharacterLocalDataSource();

  // 创建新项目，返回自增主键 id
  createProject(project: DramaProject): Promise<number> {
    return this.projects.insertProject(project);
  }

  // 获取全部项目列表
  getProjects(): Promise<DramaProject[]> {
    return this.projects.getProjects();
  }

  // 按 id 获取单个项目，不存在返回 null
  getProject(id: number): Promise<DramaProject | null> {
    return this.projects.getProject(id);
  }

  // 更新项目的文本生成结果（状态、阶段、脚本、错误信息），返回是否有行被更新
  async updateProjectTextResult(
    projectId: number,
    status: ProjectStatus,
    currentStage: GenerationStage,
    generatedScript: string | null,
    errorMessage: string | null
  ): Promise<boolean> {
    const rows = await this.projects.updateProjectTextResult(
      projectId, status, currentStage, generatedScript, errorMessage);
    return rows > 0;
  }

  // 更新项目的成片生成结果（状态、阶段、成片状态、成片路径、错误信息），返回是否有行被更新
  async updateProjectFinalVideo(
    projectId: number,
    status: ProjectStatus,
    currentStage: GenerationStage,
    finalVideoStatus: AssetStatus,
    finalVideoLocalPath: string | null,
    finalVideoErrorMessage: string | null,
    errorMessage: string | null
  ): Promise<boolean> {
    const rows = await this.projects.updateProjectFinalVideo(
      projectId, status, currentStage, finalVideoStatus,
      finalVideoLocalPath, finalVideoErrorMessage, errorMessage);
    return rows > 0;
  }

  // 获取项目对应的剧集（当前每个项目仅一集），不存在返回 null
  getEpisodeForProject(projectId: number): Promise<Episode | null> {
    return this.episodes.getEpisodeForProject(projectId);
  }

  // 按 id 获取单个剧集，不存在返回 null
  getEpisodeById(episodeId: number): Promise<Episode | null> {
    return this.episodes.getEpisodeById(episodeId);
  }

  // 获取项目的全部剧集（按集号升序），多集支持的主查询路径
  getEpisodes(projectId: number): Promise<Episode[]> {
    return this.episodes.getEpisodes(projectId);
  }

  // 全量替换项目的分镜记录，先删后插（项目级视图，兼容旧调用）
  replaceStoryboards(projectId: number, shots: StoryboardShot[]): Promise<void> {
    return this.storyboards.replaceStoryboards(projectId, shots);
  }

  // 按集全量替换分镜记录，先删后插（多集支持的主写入路径）
  replaceStoryboardsForEpisode(
    projectId: number,
    episodeId: number,
    shots: StoryboardShot[]
  ): Promise<void> {
    return this.storyboards.replaceStoryboardsForEpisode(projectId, episodeId, shots);
  }

  // 获取项目的全部分镜（按 shotNumber 升序，项目级视图）
  getStoryboards(projectId: number): Promise<StoryboardShot[]> {
    return this.storyboards.getStoryboards(projectId);
  }

  // 获取某集的全部小分镜（按 shotNumber 升序，多集支持的主查询路径）
  getStoryboardsForEpisode(projectId: number, episodeId: number): Promise<StoryboardShot[]> {
    return this.storyboards.getStoryboardsForEpisode(projectId, episodeId);
  }

  // 删除某集的全部分镜记录（删除单集时的级联清理）
  deleteStoryboardsForEpisode(projectId: number, episodeId: number): Promise<number> {
    return this.storyboards.deleteStoryboardsForEpisode(projectId, episodeId);
  }

  /** 历史数据修复：episode_id 为 NULL 的存量分镜回填到所属项目第一集。 */
  backfillStoryboardEpisodeIds(): Promise<void> {
    return this.storyboards.backfillEpisodeIds();
  }

  // 更新单个分镜的图片提示词
  async updateShotImagePrompt(shotId: number, newPrompt: string): Promise<void> {
    return this.storyboards.updateShotImagePrompt(shotId, newPrompt);
  }

  // 更新单个分镜的角色绑定（存 number[] JSON 字符串）
  async updateStoryboardCharacterIds(
    shotId: number,
    characterIdsJson: string
  ): Promise<void> {
    return this.storyboards.updateStoryboardCharacterIds(shotId, characterIdsJson);
  }

  // 更新单个分镜的视频提示词
  async updateShotVideoPrompt(shotId: number, newPrompt: string): Promise<void> {
    return this.storyboards.updateShotVideoPrompt(shotId, newPrompt);
  }

  // 更新单个分镜的图片生成结果（代理到 StoryboardLocalDataSource）
  async updateShotImage(
    shotId: number,
    imageStatus: AssetStatus,
    imageUrl: string | null,
    imageLocalPath: string | null,
    imageErrorMessage: string | null
  ): Promise<void> {
    return this.storyboards.updateShotImage(shotId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage);
  }

  // 更新单个分镜的视频生成结果（代理到 StoryboardLocalDataSource）
  async updateShotVideo(
    shotId: number,
    videoStatus: AssetStatus,
    videoTaskId: string | null,
    videoUrl: string | null,
    videoLocalPath: string | null,
    videoErrorMessage: string | null
  ): Promise<void> {
    return this.storyboards.updateShotVideo(
      shotId, videoStatus, videoTaskId, videoUrl, videoLocalPath, videoErrorMessage);
  }

  // 批量软删除某项目下所有已生成分镜图片：DB 一次性 UPDATE，返回被清掉的 imageLocalPath 列表
  async bulkClearShotImagesForProject(projectId: number): Promise<string[]> {
    return this.storyboards.bulkClearShotImagesForProject(projectId);
  }

  // 批量软删除**某集**下所有已生成分镜图片：DB 一次性 UPDATE，返回被清掉的 imageLocalPath 列表
  async bulkClearShotImagesForEpisode(projectId: number, episodeId: number): Promise<string[]> {
    return this.storyboards.bulkClearShotImagesForEpisode(projectId, episodeId);
  }

  // 批量软删除某项目下所有已生成分镜视频：DB 一次性 UPDATE，返回被清掉的 videoLocalPath 列表
  async bulkClearShotVideosForProject(projectId: number): Promise<string[]> {
    return this.storyboards.bulkClearShotVideosForProject(projectId);
  }

  // 批量软删除**某集**下所有已生成分镜视频：DB 一次性 UPDATE，返回被清掉的 videoLocalPath 列表
  async bulkClearShotVideosForEpisode(projectId: number, episodeId: number): Promise<string[]> {
    return this.storyboards.bulkClearShotVideosForEpisode(projectId, episodeId);
  }

  // 为项目创建一集（集号取当前最大 +1，DRAFT 草稿状态），返回新剧集 id
  async createEpisodeForProject(projectId: number, title: string, content: string): Promise<number> {
    const now = Date.now();
    const episodes = await this.episodes.getEpisodes(projectId);
    const nextNumber = episodes.length === 0 ? 1 : (episodes[episodes.length - 1].episodeNumber + 1);
    const episode: Episode = {
      id: 0,
      projectId,
      episodeNumber: nextNumber,
      title,
      content,
      scriptContent: null,
      status: EpisodeStatus.DRAFT,
      finalVideoStatus: AssetStatus.PENDING,
      finalVideoLocalPath: null,
      finalVideoErrorMessage: null,
      createdAt: now,
      updatedAt: now
    };
    return this.episodes.insertEpisode(episode);
  }

  // 更新剧集的脚本内容与状态，返回是否有行被更新
  async updateEpisodeScriptContent(
    episodeId: number,
    scriptContent: string,
    status: EpisodeStatus
  ): Promise<boolean> {
    const rows = await this.episodes.updateEpisodeScriptContent(episodeId, scriptContent, status);
    return rows > 0;
  }

  // 更新剧集的正文内容，返回是否有行被更新
  async updateEpisodeContent(episodeId: number, content: string): Promise<boolean> {
    const rows = await this.episodes.updateEpisodeContent(episodeId, content);
    return rows > 0;
  }

  // 更新单集成片生成结果（状态、本地路径、错误信息），返回是否有行被更新
  async updateEpisodeFinalVideo(
    episodeId: number,
    finalVideoStatus: AssetStatus,
    finalVideoLocalPath: string | null,
    finalVideoErrorMessage: string | null
  ): Promise<boolean> {
    const rows = await this.episodes.updateEpisodeFinalVideo(
      episodeId, finalVideoStatus, finalVideoLocalPath, finalVideoErrorMessage);
    return rows > 0;
  }

  /**
   * 删除单集：级联删除该集分镜（含其图片/视频文件）、成片与成片目录，再删集记录。
   * 对齐 Android DramaRepository.deleteEpisode。
   */
  async deleteEpisode(episodeId: number): Promise<boolean> {
    const episode = await this.episodes.getEpisodeById(episodeId);
    if (!episode) {
      return false;
    }
    // 分镜媒体按 generated/<projectId>/shot_<id>_* 平铺存放，不在成片目录内：
    // 必须在删除分镜行之前先取路径，否则行删掉后再也找不到这些文件。
    const shots = await this.storyboards.getStoryboardsForEpisode(episode.projectId, episodeId);
    for (const shot of shots) {
      unlinkIfExists(shot.imageLocalPath, `shot image #${shot.id}`);
      unlinkIfExists(shot.videoLocalPath, `shot video #${shot.id}`);
    }
    await this.storyboards.deleteStoryboardsForEpisode(episode.projectId, episodeId);
    unlinkIfExists(episode.finalVideoLocalPath, `episode final video #${episodeId}`);
    const dbOk = (await this.episodes.deleteEpisode(episodeId)) > 0;
    // 清理该集成片目录（此时目录内文件已删，rmdirSync 兜底清掉中间产物如 concat_list.txt）
    if (episode.finalVideoLocalPath && episode.finalVideoLocalPath.trim().length > 0) {
      const dir = episode.finalVideoLocalPath.substring(0, episode.finalVideoLocalPath.lastIndexOf('/'));
      if (dir.length > 0) {
        try {
          fileIo.rmdirSync(dir);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'delete episode dir failed for #%{public}d: %{public}s',
            episodeId, JSON.stringify(e));
        }
      }
    }
    return dbOk;
  }

  /** 软删除某集成片：DB 清状态（保留成片本地路径便于失败提示）+ 删本地文件。 */
  async deleteEpisodeFinalVideo(episodeId: number): Promise<boolean> {
    const episode = await this.episodes.getEpisodeById(episodeId);
    if (!episode) {
      return false;
    }
    unlinkIfExists(episode.finalVideoLocalPath, `episode final video #${episodeId}`);
    return (await this.episodes.updateEpisodeFinalVideo(
      episodeId, AssetStatus.PENDING, null, null)) > 0;
  }

  /** 级联删除：先删分镜和剧集和角色，再删项目行。 */
  async deleteProject(projectId: number): Promise<boolean> {
    await this.storyboards.deleteStoryboardsForProject(projectId);
    await this.characters.deleteCharactersForProject(projectId);
    await this.episodes.deleteEpisodesForProject(projectId);
    const rows = await this.projects.deleteProject(projectId);
    return rows > 0;
  }

  // ---------- 角色操作 ----------

  // 全量替换项目的角色记录，先删后插（仅清空重建场景）
  replaceCharacters(projectId: number, characters: Character[]): Promise<void> {
    return this.characters.replaceCharacters(projectId, characters);
  }

  /**
   * 增量写入角色：同名已有行 UPDATE（保留 id/立绘），新角色 INSERT。
   * 本集未提到的已有角色不删除。对齐 backend save_dedup_characters。
   */
  upsertCharacters(projectId: number, characters: Character[]): Promise<void> {
    return this.characters.upsertCharacters(projectId, characters);
  }

  // 获取项目的所有角色
  getCharacters(projectId: number): Promise<Character[]> {
    return this.characters.getCharacters(projectId);
  }

  // 更新单个角色的图片生成结果
  async updateCharacterImage(
    characterId: number,
    imageStatus: AssetStatus,
    imageUrl: string | null,
    imageLocalPath: string | null,
    imageErrorMessage: string | null
  ): Promise<void> {
    return this.characters.updateCharacterImage(characterId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage);
  }

  // 更新单个角色的外貌描述（图片生成提示词）
  async updateCharacterAppearance(characterId: number, appearance: string): Promise<void> {
    return this.characters.updateCharacterAppearance(characterId, appearance);
  }

  /**
   * 对应 ZdramaApplication.resetOrphanGenerationJobs：冷启动时，将卡在
   * PROCESSING（应用在请求中途被杀）的项目置为 FAILED，避免其永远停留在
   * “生成中”。返回被重置的项目数量。
   */
  async resetOrphanProcessingProjects(): Promise<number> {
    const projects = await this.projects.getProjects();
    let reset = 0;
    for (const project of projects) {
      if (project.status === ProjectStatus.PROCESSING) {
        await this.projects.updateProjectTextResult(
          project.id,
          ProjectStatus.FAILED,
          project.currentStage,
          project.generatedScript,
          '生成任务中断（应用被关闭），请重新开始'
        );
        reset++;
      }
    }
    return reset;
  }
}
