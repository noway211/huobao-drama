import { relationalStore } from '@kit.ArkData';
import { DramaDatabase } from './DramaDatabase';
import { Episode, EpisodeStatus, AssetStatus, episodeStatusFrom, assetStatusFrom } from '../model/DramaModels';

// 剧集表名
const TABLE = 'episodes';

// 查询时使用的列名列表
const COLUMNS = [
  'id', 'project_id', 'episode_number', 'episode_title', 'content',
  'script_content', 'episode_status', 'final_video_status',
  'final_video_local_path', 'final_video_error_message',
  'created_at', 'updated_at'
];

// 读取可空字符串列：列值为 NULL 时返回 null，否则返回字符串
function nullableString(rs: relationalStore.ResultSet, column: string): string | null {
  const idx = rs.getColumnIndex(column);
  if (rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getString(idx);
}

// 将结果集当前行映射为 Episode 对象
function mapRow(rs: relationalStore.ResultSet): Episode {
  return {
    id: rs.getLong(rs.getColumnIndex('id')),
    projectId: rs.getLong(rs.getColumnIndex('project_id')),
    episodeNumber: rs.getLong(rs.getColumnIndex('episode_number')),
    title: rs.getString(rs.getColumnIndex('episode_title')),
    content: nullableString(rs, 'content'),
    scriptContent: nullableString(rs, 'script_content'),
    status: episodeStatusFrom(rs.getString(rs.getColumnIndex('episode_status'))),
    finalVideoStatus: assetStatusFrom(rs.getString(rs.getColumnIndex('final_video_status'))),
    finalVideoLocalPath: nullableString(rs, 'final_video_local_path'),
    finalVideoErrorMessage: nullableString(rs, 'final_video_error_message'),
    createdAt: rs.getLong(rs.getColumnIndex('created_at')),
    updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
  };
}

/** Ports com.huobao.zdrama.data.local.EpisodeLocalDataSource. */
export class EpisodeLocalDataSource {
  // 插入一条剧集记录，返回新记录的自增 id
  async insertEpisode(episode: Episode): Promise<number> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'project_id': episode.projectId,
      'episode_number': episode.episodeNumber,
      'episode_title': episode.title,
      'content': episode.content,
      'script_content': episode.scriptContent,
      'episode_status': episode.status,
      'final_video_status': episode.finalVideoStatus,
      'final_video_local_path': episode.finalVideoLocalPath,
      'final_video_error_message': episode.finalVideoErrorMessage,
      'created_at': episode.createdAt,
      'updated_at': episode.updatedAt
    };
    return store.insert(TABLE, values);
  }

  // 查询项目的首集（按集号升序取第一条），不存在返回 null
  async getEpisodeForProject(projectId: number): Promise<Episode | null> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    predicates.orderByAsc('episode_number');
    predicates.limitAs(1);
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

  // 查询项目的全部剧集（按集号升序），多集支持的主查询路径
  async getEpisodes(projectId: number): Promise<Episode[]> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    predicates.orderByAsc('episode_number');
    const rs = await store.query(predicates, COLUMNS);
    const result: Episode[] = [];
    try {
      while (rs.goToNextRow()) {
        result.push(mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return result;
  }

  // 按 id 查询单集，不存在返回 null
  async getEpisodeById(episodeId: number): Promise<Episode | null> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', episodeId);
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

  // 更新指定剧集的正文内容并刷新更新时间，返回受影响行数
  async updateEpisodeContent(episodeId: number, content: string): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', episodeId);
    const values: relationalStore.ValuesBucket = {
      'content': content,
      'updated_at': Date.now()
    };
    return store.update(values, predicates);
  }

  // 更新指定剧集的脚本内容与状态并刷新更新时间，返回受影响行数
  async updateEpisodeScriptContent(
    episodeId: number,
    scriptContent: string,
    status: EpisodeStatus
  ): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', episodeId);
    const values: relationalStore.ValuesBucket = {
      'script_content': scriptContent,
      'episode_status': status,
      'updated_at': Date.now()
    };
    return store.update(values, predicates);
  }

  // 删除某项目下的全部剧集，返回删除的行数
  async deleteEpisodesForProject(projectId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    return store.delete(predicates);
  }

  // 删除单集，返回删除的行数（调用方负责级联清理分镜/成片文件）
  async deleteEpisode(episodeId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', episodeId);
    return store.delete(predicates);
  }

  // 更新单集成片生成结果（状态、本地路径、错误信息），返回受影响行数
  async updateEpisodeFinalVideo(
    episodeId: number,
    finalVideoStatus: AssetStatus,
    finalVideoLocalPath: string | null,
    finalVideoErrorMessage: string | null
  ): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', episodeId);
    const values: relationalStore.ValuesBucket = {
      'final_video_status': finalVideoStatus,
      'final_video_local_path': finalVideoLocalPath,
      'final_video_error_message': finalVideoErrorMessage,
      'updated_at': Date.now()
    };
    return store.update(values, predicates);
  }
}
