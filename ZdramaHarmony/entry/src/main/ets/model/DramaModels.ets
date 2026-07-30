/**
 * Domain model — ports com.huobao.zdrama.domain.model.DramaModels.
 * Enums are string enums so they persist to RDB as their name (same as the
 * Android SQLite schema which stores enum .name strings).
 */

export enum ProjectStatus {
  DRAFT = 'DRAFT',
  PROCESSING = 'PROCESSING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

export enum GenerationStage {
  NONE = 'NONE',
  TEXT = 'TEXT',
  STORYBOARD = 'STORYBOARD',
  IMAGE = 'IMAGE',
  VIDEO = 'VIDEO',
  FINAL_VIDEO = 'FINAL_VIDEO'
}

export enum AssetStatus {
  PENDING = 'PENDING',
  PROCESSING = 'PROCESSING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED'
}

export enum EpisodeStatus {
  DRAFT = 'DRAFT',
  REWRITING = 'REWRITING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED'
}

export function projectStatusFrom(value: string | null | undefined): ProjectStatus {
  switch (value) {
    case 'PROCESSING': return ProjectStatus.PROCESSING;
    case 'COMPLETED': return ProjectStatus.COMPLETED;
    case 'FAILED': return ProjectStatus.FAILED;
    case 'CANCELLED': return ProjectStatus.CANCELLED;
    default: return ProjectStatus.DRAFT;
  }
}

export function generationStageFrom(value: string | null | undefined): GenerationStage {
  switch (value) {
    case 'TEXT': return GenerationStage.TEXT;
    case 'STORYBOARD': return GenerationStage.STORYBOARD;
    case 'IMAGE': return GenerationStage.IMAGE;
    case 'VIDEO': return GenerationStage.VIDEO;
    case 'FINAL_VIDEO': return GenerationStage.FINAL_VIDEO;
    default: return GenerationStage.NONE;
  }
}

export function assetStatusFrom(value: string | null | undefined): AssetStatus {
  switch (value) {
    case 'PROCESSING': return AssetStatus.PROCESSING;
    case 'COMPLETED': return AssetStatus.COMPLETED;
    case 'FAILED': return AssetStatus.FAILED;
    default: return AssetStatus.PENDING;
  }
}

export function episodeStatusFrom(value: string | null | undefined): EpisodeStatus {
  switch (value) {
    case 'REWRITING': return EpisodeStatus.REWRITING;
    case 'COMPLETED': return EpisodeStatus.COMPLETED;
    case 'FAILED': return EpisodeStatus.FAILED;
    default: return EpisodeStatus.DRAFT;
  }
}

export interface CreateDramaInput {
  title: string;
  prompt: string;
  style: string;
  targetAudience: string;
  aspectRatio: string;
  shotCount: number;
  shotDurationSeconds: number;
}

export interface DramaProject {
  id: number;
  title: string;
  prompt: string;
  style: string;
  targetAudience: string;
  aspectRatio: string;
  shotCount: number;
  shotDurationSeconds: number;
  status: ProjectStatus;
  currentStage: GenerationStage;
  errorMessage: string | null;
  generatedScript: string | null;
  finalVideoStatus: AssetStatus;
  finalVideoLocalPath: string | null;
  finalVideoErrorMessage: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface Episode {
  id: number;
  projectId: number;
  episodeNumber: number;
  title: string;
  content: string | null;
  scriptContent: string | null;
  status: EpisodeStatus;
  createdAt: number;
  updatedAt: number;
}
