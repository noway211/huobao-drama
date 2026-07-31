import { ProjectLocalDataSource } from './ProjectLocalDataSource';
import { EpisodeLocalDataSource } from './EpisodeLocalDataSource';
import { StoryboardLocalDataSource } from './StoryboardLocalDataSource';
import {
  DramaProject,
  Episode,
  EpisodeStatus,
  ProjectStatus,
  GenerationStage,
  StoryboardShot,
  AssetStatus
} from '../model/DramaModels';

/**
 * Ports com.huobao.zdrama.data.repository.DramaRepository (MVP subset).
 * Facade over the project + episode local data sources.
 */
export class DramaRepository {
  private projects = new ProjectLocalDataSource();
  private episodes = new EpisodeLocalDataSource();
  private storyboards = new StoryboardLocalDataSource();

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

  // 获取项目对应的剧集（当前每个项目仅一集），不存在返回 null
  getEpisodeForProject(projectId: number): Promise<Episode | null> {
    return this.episodes.getEpisodeForProject(projectId);
  }

  // 全量替换项目的分镜记录，先删后插
  replaceStoryboards(projectId: number, shots: StoryboardShot[]): Promise<void> {
    return this.storyboards.replaceStoryboards(projectId, shots);
  }

  // 获取项目的全部分镜（按 shotNumber 升序）
  getStoryboards(projectId: number): Promise<StoryboardShot[]> {
    return this.storyboards.getStoryboards(projectId);
  }

  // 更新单个分镜的图片提示词
  async updateShotImagePrompt(shotId: number, newPrompt: string): Promise<void> {
    return this.storyboards.updateShotImagePrompt(shotId, newPrompt);
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

  // 为项目创建一集（默认第 1 集、DRAFT 草稿状态），返回新剧集 id
  async createEpisodeForProject(projectId: number, title: string, content: string): Promise<number> {
    const now = Date.now();
    const episode: Episode = {
      id: 0,
      projectId,
      episodeNumber: 1,
      title,
      content,
      scriptContent: null,
      status: EpisodeStatus.DRAFT,
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

  /** 级联删除：先删分镜和剧集，再删项目行。 */
  async deleteProject(projectId: number): Promise<boolean> {
    await this.storyboards.deleteStoryboardsForProject(projectId);
    await this.episodes.deleteEpisodesForProject(projectId);
    const rows = await this.projects.deleteProject(projectId);
    return rows > 0;
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
