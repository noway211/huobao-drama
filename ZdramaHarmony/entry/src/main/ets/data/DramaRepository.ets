import { ProjectLocalDataSource } from './ProjectLocalDataSource';
import { EpisodeLocalDataSource } from './EpisodeLocalDataSource';
import {
  DramaProject,
  Episode,
  EpisodeStatus,
  ProjectStatus,
  GenerationStage
} from '../model/DramaModels';

/**
 * Ports com.huobao.zdrama.data.repository.DramaRepository (MVP subset).
 * Facade over the project + episode local data sources.
 */
export class DramaRepository {
  private projects = new ProjectLocalDataSource();
  private episodes = new EpisodeLocalDataSource();

  createProject(project: DramaProject): Promise<number> {
    return this.projects.insertProject(project);
  }

  getProjects(): Promise<DramaProject[]> {
    return this.projects.getProjects();
  }

  getProject(id: number): Promise<DramaProject | null> {
    return this.projects.getProject(id);
  }

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

  getEpisodeForProject(projectId: number): Promise<Episode | null> {
    return this.episodes.getEpisodeForProject(projectId);
  }

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

  async updateEpisodeScriptContent(
    episodeId: number,
    scriptContent: string,
    status: EpisodeStatus
  ): Promise<boolean> {
    const rows = await this.episodes.updateEpisodeScriptContent(episodeId, scriptContent, status);
    return rows > 0;
  }

  async updateEpisodeContent(episodeId: number, content: string): Promise<boolean> {
    const rows = await this.episodes.updateEpisodeContent(episodeId, content);
    return rows > 0;
  }

  /** Cascade delete: episodes + project row. (Storyboards/media added later.) */
  async deleteProject(projectId: number): Promise<boolean> {
    await this.episodes.deleteEpisodesForProject(projectId);
    const rows = await this.projects.deleteProject(projectId);
    return rows > 0;
  }
}
