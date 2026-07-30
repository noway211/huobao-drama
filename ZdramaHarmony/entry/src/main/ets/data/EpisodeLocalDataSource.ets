import { relationalStore } from '@kit.ArkData';
import { DramaDatabase } from './DramaDatabase';
import { Episode, EpisodeStatus, episodeStatusFrom } from '../model/DramaModels';

const TABLE = 'episodes';

const COLUMNS = [
  'id', 'project_id', 'episode_number', 'episode_title', 'content',
  'script_content', 'episode_status', 'created_at', 'updated_at'
];

function nullableString(rs: relationalStore.ResultSet, column: string): string | null {
  const idx = rs.getColumnIndex(column);
  if (rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getString(idx);
}

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

  async deleteEpisodesForProject(projectId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    return store.delete(predicates);
  }
}
