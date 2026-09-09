import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DramaDatabase } from './DramaDatabase';
import { StoryboardShot, AssetStatus, assetStatusFrom } from '../model/DramaModels';

// 分镜表名
const TABLE = 'storyboards';

// 查询时使用的列名列表
const COLUMNS = [
  'id', 'project_id', 'episode_id', 'shot_number', 'scene',
  'action', 'dialogue', 'camera', 'image_prompt', 'video_prompt',
  'duration_seconds', 'character_ids', 'image_status', 'image_url', 'image_local_path',
  'image_error_message', 'video_status', 'video_task_id', 'video_url',
  'video_local_path', 'video_error_message', 'created_at', 'updated_at'
];

// 读取可空字符串列：列值为 NULL 时返回 null，否则返回字符串
function nullableString(rs: relationalStore.ResultSet, column: string): string | null {
  const idx = rs.getColumnIndex(column);
  if (rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getString(idx);
}

// 读取可空整数列
function nullableNumber(rs: relationalStore.ResultSet, column: string): number | null {
  const idx = rs.getColumnIndex(column);
  if (rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getLong(idx);
}

// 将结果集当前行映射为 StoryboardShot 对象
function mapRow(rs: relationalStore.ResultSet): StoryboardShot {
  return {
    id: rs.getLong(rs.getColumnIndex('id')),
    projectId: rs.getLong(rs.getColumnIndex('project_id')),
    episodeId: nullableNumber(rs, 'episode_id'),
    shotNumber: rs.getLong(rs.getColumnIndex('shot_number')),
    scene: rs.getString(rs.getColumnIndex('scene')),
    action: rs.getString(rs.getColumnIndex('action')),
    dialogue: rs.getString(rs.getColumnIndex('dialogue')),
    camera: rs.getString(rs.getColumnIndex('camera')),
    imagePrompt: rs.getString(rs.getColumnIndex('image_prompt')),
    videoPrompt: rs.getString(rs.getColumnIndex('video_prompt')),
    durationSeconds: rs.getLong(rs.getColumnIndex('duration_seconds')),
    characterIds: nullableString(rs, 'character_ids'),
    imageStatus: assetStatusFrom(rs.getString(rs.getColumnIndex('image_status'))),
    imageUrl: nullableString(rs, 'image_url'),
    imageLocalPath: nullableString(rs, 'image_local_path'),
    imageErrorMessage: nullableString(rs, 'image_error_message'),
    videoStatus: assetStatusFrom(rs.getString(rs.getColumnIndex('video_status'))),
    videoTaskId: nullableString(rs, 'video_task_id'),
    videoUrl: nullableString(rs, 'video_url'),
    videoLocalPath: nullableString(rs, 'video_local_path'),
    videoErrorMessage: nullableString(rs, 'video_error_message'),
    createdAt: rs.getLong(rs.getColumnIndex('created_at')),
    updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
  };
}

/** Ports com.huobao.zdrama.data.local.StoryboardLocalDataSource. */
export class StoryboardLocalDataSource {
  // 全量替换项目的分镜记录：删除旧记录后批量插入新记录（项目级视图，兼容旧调用）
  async replaceStoryboards(projectId: number, shots: StoryboardShot[]): Promise<void> {
    const store = await DramaDatabase.getStore();
    // 先删除该项目的所有旧分镜
    const delPredicates = new relationalStore.RdbPredicates(TABLE);
    delPredicates.equalTo('project_id', projectId);
    await store.delete(delPredicates);

    // 逐条插入新记录
    const now = Date.now();
    for (const shot of shots) {
      const values: relationalStore.ValuesBucket = {
        'project_id': projectId,
        'episode_id': shot.episodeId,
        'shot_number': shot.shotNumber,
        'scene': shot.scene,
        'action': shot.action,
        'dialogue': shot.dialogue,
        'camera': shot.camera,
        'image_prompt': shot.imagePrompt,
        'video_prompt': shot.videoPrompt,
        'duration_seconds': shot.durationSeconds,
        'character_ids': shot.characterIds,
        'image_status': shot.imageStatus,
        'image_url': shot.imageUrl,
        'image_local_path': shot.imageLocalPath,
        'image_error_message': shot.imageErrorMessage,
        'video_status': shot.videoStatus,
        'video_task_id': shot.videoTaskId,
        'video_url': shot.videoUrl,
        'video_local_path': shot.videoLocalPath,
        'video_error_message': shot.videoErrorMessage,
        'created_at': now,
        'updated_at': now
      };
      await store.insert(TABLE, values);
    }
  }

  // 按集全量替换分镜记录：删除该集的旧记录后批量插入（多集支持的主写入路径）
  async replaceStoryboardsForEpisode(
    projectId: number,
    episodeId: number,
    shots: StoryboardShot[]
  ): Promise<void> {
    const store = await DramaDatabase.getStore();
    const delPredicates = new relationalStore.RdbPredicates(TABLE);
    delPredicates.equalTo('project_id', projectId);
    delPredicates.equalTo('episode_id', episodeId);
    await store.delete(delPredicates);

    const now = Date.now();
    for (const shot of shots) {
      const values: relationalStore.ValuesBucket = {
        'project_id': projectId,
        'episode_id': episodeId,
        'shot_number': shot.shotNumber,
        'scene': shot.scene,
        'action': shot.action,
        'dialogue': shot.dialogue,
        'camera': shot.camera,
        'image_prompt': shot.imagePrompt,
        'video_prompt': shot.videoPrompt,
        'duration_seconds': shot.durationSeconds,
        'character_ids': shot.characterIds,
        'image_status': shot.imageStatus,
        'image_url': shot.imageUrl,
        'image_local_path': shot.imageLocalPath,
        'image_error_message': shot.imageErrorMessage,
        'video_status': shot.videoStatus,
        'video_task_id': shot.videoTaskId,
        'video_url': shot.videoUrl,
        'video_local_path': shot.videoLocalPath,
        'video_error_message': shot.videoErrorMessage,
        'created_at': now,
        'updated_at': now
      };
      await store.insert(TABLE, values);
    }
  }

  // 查询某项目的所有分镜，按 shot_number 升序排列（项目级视图，兼容旧调用）
  async getStoryboards(projectId: number): Promise<StoryboardShot[]> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    predicates.orderByAsc('shot_number');
    const rs = await store.query(predicates, COLUMNS);
    const result: StoryboardShot[] = [];
    try {
      while (rs.goToNextRow()) {
        result.push(mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return result;
  }

  // 查询某集的全部小分镜，按 shot_number 升序排列（多集支持的主查询路径）
  async getStoryboardsForEpisode(projectId: number, episodeId: number): Promise<StoryboardShot[]> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    predicates.equalTo('episode_id', episodeId);
    predicates.orderByAsc('shot_number');
    const rs = await store.query(predicates, COLUMNS);
    const result: StoryboardShot[] = [];
    try {
      while (rs.goToNextRow()) {
        result.push(mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return result;
  }

  // 删除某项目的全部分镜记录，返回删除的行数
  async deleteStoryboardsForProject(projectId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    return store.delete(predicates);
  }

  // 删除某集的全部分镜记录，返回删除的行数（删除单集时的级联清理）
  async deleteStoryboardsForEpisode(projectId: number, episodeId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    predicates.equalTo('episode_id', episodeId);
    return store.delete(predicates);
  }

  /**
   * 历史数据修复：把 episode_id 为 NULL 的分镜回填到所属项目的第一集。
   * 多集改造前生成的分镜未写 episode_id，按集查询（getStoryboardsForEpisode）
   * 会漏掉这些镜头。启动时兜底执行一次。
   */
  async backfillEpisodeIds(): Promise<void> {
    const store = await DramaDatabase.getStore();
    await store.executeSql(
      `UPDATE ${TABLE} SET episode_id = (
         SELECT id FROM episodes
         WHERE episodes.project_id = ${TABLE}.project_id
         ORDER BY episode_number ASC
         LIMIT 1
       ) WHERE episode_id IS NULL`
    );
    hilog.info(0x0001, 'StoryboardLocalDataSource', 'backfillEpisodeIds done');
  }

  /**
   * 更新单个分镜的图片提示词（image_prompt 列）。
   */
  async updateShotImagePrompt(shotId: number, newPrompt: string): Promise<void> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'image_prompt': newPrompt,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', shotId);
    await store.update(values, predicates);
  }

  /**
   * 更新单个分镜的角色绑定（character_ids 列，存 number[] JSON 字符串）。
   * 参照 updateShotImagePrompt 的查询模式。
   */
  async updateStoryboardCharacterIds(
    shotId: number,
    characterIdsJson: string
  ): Promise<void> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'character_ids': characterIdsJson,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', shotId);
    await store.update(values, predicates);
  }

  /**
   * 更新单个分镜的图片生成结果（image/URL、本地路径、错误信息），
   * 对应 Android StoryboardLocalDataSource.updateShotImageAndUpdatedAt()。
   */
  async updateShotImage(
    shotId: number,
    imageStatus: AssetStatus,
    imageUrl: string | null,
    imageLocalPath: string | null,
    imageErrorMessage: string | null
  ): Promise<void> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'image_status': imageStatus,
      'image_url': imageUrl,
      'image_local_path': imageLocalPath,
      'image_error_message': imageErrorMessage,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', shotId);
    await store.update(values, predicates);
  }

  /**
   * 更新单个分镜的视频生成结果（taskId、URL、本地路径、错误信息）。
   * 对应 Android StoryboardLocalDataSource.updateShotVideo()。
   */
  async updateShotVideo(
    shotId: number,
    videoStatus: AssetStatus,
    videoTaskId: string | null,
    videoUrl: string | null,
    videoLocalPath: string | null,
    videoErrorMessage: string | null
  ): Promise<void> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'video_status': videoStatus,
      'video_task_id': videoTaskId,
      'video_url': videoUrl,
      'video_local_path': videoLocalPath,
      'video_error_message': videoErrorMessage,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', shotId);
    await store.update(values, predicates);
  }

  /**
   * 更新单个分镜的视频提示词（video_prompt 列）。
   */
  async updateShotVideoPrompt(shotId: number, newPrompt: string): Promise<void> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'video_prompt': newPrompt,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', shotId);
    await store.update(values, predicates);
  }

  /**
   * 批量清空某项目下所有"已生成分镜图片"：DB 软删除（status 置 PENDING + 清字段），
   * 并返回被影响的分镜行的 imageLocalPath 列表，方便 UI 层同步 unlink 本地文件。
   *
   * **重要**：只清 image_status='COMPLETED' 的行；FAILED / PROCESSING / PENDING 一律不动。
   * 调用方拿到返回的 paths 后应自行 unlink（容错：文件已不在不应报错）。
   *
   * 对应 Android StoryboardLocalDataSource.bulkClearShotImagesForProject()。
   */
  async bulkClearShotImagesForProject(projectId: number): Promise<string[]> {
    const store = await DramaDatabase.getStore();
    // 1) 先查出会被影响的行（用于返回 localPath 给 UI 删文件）
    const queryPred = new relationalStore.RdbPredicates(TABLE);
    queryPred.equalTo('project_id', projectId);
    queryPred.equalTo('image_status', 'COMPLETED');
    const localPaths: string[] = [];
    const rs = await store.query(queryPred, ['image_local_path']);
    if (rs !== null && rs !== undefined) {
      try {
        while (rs.goToNextRow()) {
          const p = nullableString(rs, 'image_local_path');
          if (p !== null && p.length > 0) {
            localPaths.push(p);
          }
        }
      } finally {
        rs.close();
      }
    }
    // 2) 一次性 UPDATE（WHERE 同时带 project_id 和 image_status 双重过滤，避免影响其它行）
    const updatePred = new relationalStore.RdbPredicates(TABLE);
    updatePred.equalTo('project_id', projectId);
    updatePred.equalTo('image_status', 'COMPLETED');
    const values: relationalStore.ValuesBucket = {
      'image_status': AssetStatus.PENDING,
      'image_url': null,
      'image_local_path': null,
      'image_error_message': null,
      'updated_at': Date.now()
    };
    await store.update(values, updatePred);
    return localPaths;
  }

  /**
   * 批量清空**某集**下所有"已生成分镜图片"：语义与 bulkClearShotImagesForProject 相同，
   * 但限定 episode_id（多集下「全部删除」只应作用于当前集）。
   */
  async bulkClearShotImagesForEpisode(projectId: number, episodeId: number): Promise<string[]> {
    const store = await DramaDatabase.getStore();
    const queryPred = new relationalStore.RdbPredicates(TABLE);
    queryPred.equalTo('project_id', projectId);
    queryPred.equalTo('episode_id', episodeId);
    queryPred.equalTo('image_status', 'COMPLETED');
    const localPaths: string[] = [];
    const rs = await store.query(queryPred, ['image_local_path']);
    if (rs !== null && rs !== undefined) {
      try {
        while (rs.goToNextRow()) {
          const p = nullableString(rs, 'image_local_path');
          if (p !== null && p.length > 0) {
            localPaths.push(p);
          }
        }
      } finally {
        rs.close();
      }
    }
    const updatePred = new relationalStore.RdbPredicates(TABLE);
    updatePred.equalTo('project_id', projectId);
    updatePred.equalTo('episode_id', episodeId);
    updatePred.equalTo('image_status', 'COMPLETED');
    const values: relationalStore.ValuesBucket = {
      'image_status': AssetStatus.PENDING,
      'image_url': null,
      'image_local_path': null,
      'image_error_message': null,
      'updated_at': Date.now()
    };
    await store.update(values, updatePred);
    return localPaths;
  }

  /**
   * 批量清空某项目下所有"已生成分镜视频"，语义与 bulkClearShotImagesForProject 对称。
   * 对应 Android StoryboardLocalDataSource.bulkClearShotVideosForProject()。
   */
  async bulkClearShotVideosForProject(projectId: number): Promise<string[]> {
    const store = await DramaDatabase.getStore();
    const queryPred = new relationalStore.RdbPredicates(TABLE);
    queryPred.equalTo('project_id', projectId);
    queryPred.equalTo('video_status', 'COMPLETED');
    const localPaths: string[] = [];
    const rs = await store.query(queryPred, ['video_local_path']);
    if (rs !== null && rs !== undefined) {
      try {
        while (rs.goToNextRow()) {
          const p = nullableString(rs, 'video_local_path');
          if (p !== null && p.length > 0) {
            localPaths.push(p);
          }
        }
      } finally {
        rs.close();
      }
    }
    const updatePred = new relationalStore.RdbPredicates(TABLE);
    updatePred.equalTo('project_id', projectId);
    updatePred.equalTo('video_status', 'COMPLETED');
    const values: relationalStore.ValuesBucket = {
      'video_status': AssetStatus.PENDING,
      'video_task_id': null,
      'video_url': null,
      'video_local_path': null,
      'video_error_message': null,
      'updated_at': Date.now()
    };
    await store.update(values, updatePred);
    return localPaths;
  }

  /**
   * 批量清空**某集**下所有"已生成分镜视频"：语义与 bulkClearShotVideosForProject 相同，
   * 但限定 episode_id（多集下「全部删除」只应作用于当前集）。
   */
  async bulkClearShotVideosForEpisode(projectId: number, episodeId: number): Promise<string[]> {
    const store = await DramaDatabase.getStore();
    const queryPred = new relationalStore.RdbPredicates(TABLE);
    queryPred.equalTo('project_id', projectId);
    queryPred.equalTo('episode_id', episodeId);
    queryPred.equalTo('video_status', 'COMPLETED');
    const localPaths: string[] = [];
    const rs = await store.query(queryPred, ['video_local_path']);
    if (rs !== null && rs !== undefined) {
      try {
        while (rs.goToNextRow()) {
          const p = nullableString(rs, 'video_local_path');
          if (p !== null && p.length > 0) {
            localPaths.push(p);
          }
        }
      } finally {
        rs.close();
      }
    }
    const updatePred = new relationalStore.RdbPredicates(TABLE);
    updatePred.equalTo('project_id', projectId);
    updatePred.equalTo('episode_id', episodeId);
    updatePred.equalTo('video_status', 'COMPLETED');
    const values: relationalStore.ValuesBucket = {
      'video_status': AssetStatus.PENDING,
      'video_task_id': null,
      'video_url': null,
      'video_local_path': null,
      'video_error_message': null,
      'updated_at': Date.now()
    };
    await store.update(values, updatePred);
    return localPaths;
  }
}