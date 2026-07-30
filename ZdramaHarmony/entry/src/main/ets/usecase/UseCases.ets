import { DramaRepository } from '../data/DramaRepository';
import { AgnesTextRepository, TextResult } from '../remote/AgnesTextRepository';
import { AgnesSettings } from '../model/AgnesSettings';
import {
  CreateDramaInput,
  DramaProject,
  Episode,
  ProjectStatus,
  GenerationStage,
  AssetStatus,
  EpisodeStatus
} from '../model/DramaModels';

/**
 * Ports the MVP subset of com.huobao.zdrama.domain.usecase.*.
 * Kept as static methods on one class since each is thin.
 */
export class UseCases {
  private static repo = new DramaRepository();
  private static text = new AgnesTextRepository();

  /** CreateDramaUseCase: insert project (DRAFT) + auto-create episode 1. */
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

  static getProjects(): Promise<DramaProject[]> {
    return UseCases.repo.getProjects();
  }

  static getProject(projectId: number): Promise<DramaProject | null> {
    return UseCases.repo.getProject(projectId);
  }

  static getEpisode(projectId: number): Promise<Episode | null> {
    return UseCases.repo.getEpisodeForProject(projectId);
  }

  static deleteProject(projectId: number): Promise<boolean> {
    return UseCases.repo.deleteProject(projectId);
  }

  /** Cold-start recovery: reset orphan PROCESSING projects to FAILED. */
  static resetOrphanProcessingProjects(): Promise<number> {
    return UseCases.repo.resetOrphanProcessingProjects();
  }

  /** GenerateProjectScriptUseCase: create screenplay from the project prompt. */
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

  /** RewriteEpisodeScriptUseCase: rewrite episode.content into a screenplay. */
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
}
