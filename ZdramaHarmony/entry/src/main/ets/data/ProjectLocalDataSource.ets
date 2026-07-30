import { relationalStore } from '@kit.ArkData';
import { DramaDatabase } from './DramaDatabase';
import {
  DramaProject,
  ProjectStatus,
  GenerationStage,
  AssetStatus,
  projectStatusFrom,
  generationStageFrom,
  assetStatusFrom
} from '../model/DramaModels';

// 项目表名
const TABLE = 'projects';

// 查询时使用的列名列表
const COLUMNS = [
  'id', 'title', 'prompt', 'style', 'target_audience', 'aspect_ratio',
  'shot_count', 'shot_duration_seconds', 'status', 'current_stage',
  'error_message', 'generated_script', 'final_video_status',
  'final_video_local_path', 'final_video_error_message', 'created_at', 'updated_at'
];

// 读取可空字符串列：列值为 NULL 时返回 null，否则返回字符串
function nullableString(rs: relationalStore.ResultSet, column: string): string | null {
  const idx = rs.getColumnIndex(column);
  if (rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getString(idx);
}

// 将结果集当前行映射为 DramaProject 对象（枚举列字符串转枚举）
function mapRow(rs: relationalStore.ResultSet): DramaProject {
  return {
    id: rs.getLong(rs.getColumnIndex('id')),
    title: rs.getString(rs.getColumnIndex('title')),
    prompt: rs.getString(rs.getColumnIndex('prompt')),
    style: rs.getString(rs.getColumnIndex('style')),
    targetAudience: rs.getString(rs.getColumnIndex('target_audience')),
    aspectRatio: rs.getString(rs.getColumnIndex('aspect_ratio')),
    shotCount: rs.getLong(rs.getColumnIndex('shot_count')),
    shotDurationSeconds: rs.getLong(rs.getColumnIndex('shot_duration_seconds')),
    status: projectStatusFrom(rs.getString(rs.getColumnIndex('status'))),
    currentStage: generationStageFrom(rs.getString(rs.getColumnIndex('current_stage'))),
    errorMessage: nullableString(rs, 'error_message'),
    generatedScript: nullableString(rs, 'generated_script'),
    finalVideoStatus: assetStatusFrom(rs.getString(rs.getColumnIndex('final_video_status'))),
    finalVideoLocalPath: nullableString(rs, 'final_video_local_path'),
    finalVideoErrorMessage: nullableString(rs, 'final_video_error_message'),
    createdAt: rs.getLong(rs.getColumnIndex('created_at')),
    updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
  };
}

/** Ports com.huobao.zdrama.data.local.ProjectLocalDataSource. */
export class ProjectLocalDataSource {
  // 插入一条项目记录，返回新记录的自增 id
  async insertProject(project: DramaProject): Promise<number> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'title': project.title,
      'prompt': project.prompt,
      'style': project.style,
      'target_audience': project.targetAudience,
      'aspect_ratio': project.aspectRatio,
      'shot_count': project.shotCount,
      'shot_duration_seconds': project.shotDurationSeconds,
      'status': project.status,
      'current_stage': project.currentStage,
      'error_message': project.errorMessage,
      'generated_script': project.generatedScript,
      'final_video_status': project.finalVideoStatus,
      'final_video_local_path': project.finalVideoLocalPath,
      'final_video_error_message': project.finalVideoErrorMessage,
      'created_at': project.createdAt,
      'updated_at': project.updatedAt
    };
    return store.insert(TABLE, values);
  }

  // 查询全部项目，按更新时间倒序返回
  async getProjects(): Promise<DramaProject[]> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.orderByDesc('updated_at');
    const rs = await store.query(predicates, COLUMNS);
    const result: DramaProject[] = [];
    try {
      while (rs.goToNextRow()) {
        result.push(mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return result;
  }

  // 按 id 查询单个项目，不存在返回 null
  async getProject(projectId: number): Promise<DramaProject | null> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', projectId);
    const rs = await store.query(predicates, COLUMNS);
    try {
      if (rs.goToFirstRow()) {
        return mapRow(rs);
      }
      return null;
    } finally {
      rs.close();
    }
  }

  // 按 id 删除项目，返回删除的行数
  async deleteProject(projectId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', projectId);
    return store.delete(predicates);
  }

  // 更新项目的文本生成结果（状态、阶段、脚本、错误信息）并刷新更新时间，返回受影响行数
  async updateProjectTextResult(
    projectId: number,
    status: ProjectStatus,
    currentStage: GenerationStage,
    generatedScript: string | null,
    errorMessage: string | null
  ): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', projectId);
    const values: relationalStore.ValuesBucket = {
      'status': status,
      'current_stage': currentStage,
      'generated_script': generatedScript,
      'error_message': errorMessage,
      'updated_at': Date.now()
    };
    return store.update(values, predicates);
  }
}
