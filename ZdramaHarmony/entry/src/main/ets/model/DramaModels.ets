/**
 * Domain model — ports com.huobao.zdrama.domain.model.DramaModels.
 * Enums are string enums so they persist to RDB as their name (same as the
 * Android SQLite schema which stores enum .name strings).
 */

// 项目状态枚举（字符串枚举，持久化时按名称存储）
export enum ProjectStatus {
  DRAFT = 'DRAFT',
  PROCESSING = 'PROCESSING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

// 生成流程阶段枚举
export enum GenerationStage {
  NONE = 'NONE',
  TEXT = 'TEXT',
  STORYBOARD = 'STORYBOARD',
  IMAGE = 'IMAGE',
  VIDEO = 'VIDEO',
  FINAL_VIDEO = 'FINAL_VIDEO'
}

// 素材（图片/视频等）生成状态枚举
export enum AssetStatus {
  PENDING = 'PENDING',
  PROCESSING = 'PROCESSING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED'
}

// 剧集状态枚举
export enum EpisodeStatus {
  DRAFT = 'DRAFT',
  REWRITING = 'REWRITING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED'
}

// 将字符串安全转换为 ProjectStatus，未知值回退为 DRAFT
export function projectStatusFrom(value: string | null | undefined): ProjectStatus {
  switch (value) {
    case 'PROCESSING': return ProjectStatus.PROCESSING;
    case 'COMPLETED': return ProjectStatus.COMPLETED;
    case 'FAILED': return ProjectStatus.FAILED;
    case 'CANCELLED': return ProjectStatus.CANCELLED;
    default: return ProjectStatus.DRAFT;
  }
}

// 将字符串安全转换为 GenerationStage，未知值回退为 NONE
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

// 将字符串安全转换为 AssetStatus，未知值回退为 PENDING
export function assetStatusFrom(value: string | null | undefined): AssetStatus {
  switch (value) {
    case 'PROCESSING': return AssetStatus.PROCESSING;
    case 'COMPLETED': return AssetStatus.COMPLETED;
    case 'FAILED': return AssetStatus.FAILED;
    default: return AssetStatus.PENDING;
  }
}

// 将字符串安全转换为 EpisodeStatus，未知值回退为 DRAFT
export function episodeStatusFrom(value: string | null | undefined): EpisodeStatus {
  switch (value) {
    case 'REWRITING': return EpisodeStatus.REWRITING;
    case 'COMPLETED': return EpisodeStatus.COMPLETED;
    case 'FAILED': return EpisodeStatus.FAILED;
    default: return EpisodeStatus.DRAFT;
  }
}

// 创建短剧项目时的输入参数
export interface CreateDramaInput {
  title: string;
  prompt: string;
  style: string;
  targetAudience: string;
  aspectRatio: string;
  shotCount: number;
  shotDurationSeconds: number;
}

// 短剧项目实体，对应数据库中的项目记录
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

// 剧集实体，隶属于某个短剧项目
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
