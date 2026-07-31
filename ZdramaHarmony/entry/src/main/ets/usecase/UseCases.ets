import { DramaRepository } from '../data/DramaRepository';
import { AgnesTextRepository, TextResult } from '../remote/AgnesTextRepository';
import { AgnesStoryboardRepository } from '../remote/AgnesStoryboardRepository';
import { AgnesSettings } from '../model/AgnesSettings';
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

/**
 * 移植 com.huobao.zdrama.domain.usecase.* 的 MVP 子集。
 * 由于每个用例都很轻量，统一实现为一个类上的静态方法。
 */
export class UseCases {
  private static repo = new DramaRepository();
  private static text = new AgnesTextRepository();
  private static storyboard = new AgnesStoryboardRepository();

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
}
