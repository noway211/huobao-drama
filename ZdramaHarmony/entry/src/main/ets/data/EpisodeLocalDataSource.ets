import { relationalStore } from '@kit.ArkData';
import { DramaDatabase } from './DramaDatabase';
import { Episode, EpisodeStatus, episodeStatusFrom } from '../model/DramaModels';

// 剧集表名
const TABLE = 'episodes';

// 查询时使用的列名列表
const COLUMNS = [
  'id', 'project_id', 'episode_number', 'episode_title', 'content',
  'script_content', 'episode_status', 'created_at', 'updated_at'
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
}
