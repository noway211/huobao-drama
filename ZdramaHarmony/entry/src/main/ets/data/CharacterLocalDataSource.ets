import { relationalStore } from '@kit.ArkData';
import { DramaDatabase } from './DramaDatabase';
import { Character, AssetStatus, assetStatusFrom } from '../model/DramaModels';

// 角色表名
const TABLE = 'characters';

// 查询时使用的列名列表
const COLUMNS = [
  'id', 'project_id', 'episode_id', 'name', 'role',
  'description', 'appearance', 'personality',
  'image_status', 'image_url', 'image_local_path',
  'image_error_message', 'created_at', 'updated_at'
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

// 将结果集当前行映射为 Character 对象
function mapRow(rs: relationalStore.ResultSet): Character {
  return {
    id: rs.getLong(rs.getColumnIndex('id')),
    projectId: rs.getLong(rs.getColumnIndex('project_id')),
    episodeId: nullableNumber(rs, 'episode_id'),
    name: rs.getString(rs.getColumnIndex('name')),
    role: rs.getString(rs.getColumnIndex('role')),
    description: rs.getString(rs.getColumnIndex('description')),
    appearance: rs.getString(rs.getColumnIndex('appearance')),
    personality: rs.getString(rs.getColumnIndex('personality')),
    imageStatus: assetStatusFrom(rs.getString(rs.getColumnIndex('image_status'))),
    imageUrl: nullableString(rs, 'image_url'),
    imageLocalPath: nullableString(rs, 'image_local_path'),
    imageErrorMessage: nullableString(rs, 'image_error_message'),
    createdAt: rs.getLong(rs.getColumnIndex('created_at')),
    updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
  };
}

/** 角色数据本地数据源，参照 StoryboardLocalDataSource 模式。 */
export class CharacterLocalDataSource {
  /**
   * 全量替换项目的角色记录：删除旧记录后批量插入新记录。
   * 仅用于需要清空重建的场景（当前提取角色已改走 upsertCharacters）。
   */
  async replaceCharacters(projectId: number, characters: Character[]): Promise<void> {
    const store = await DramaDatabase.getStore();
    // 先删除该项目的所有旧角色
    const delPredicates = new relationalStore.RdbPredicates(TABLE);
    delPredicates.equalTo('project_id', projectId);
    await store.delete(delPredicates);

    // 逐条插入新记录
    const now = Date.now();
    for (const ch of characters) {
      const values: relationalStore.ValuesBucket = {
        'project_id': projectId,
        'episode_id': ch.episodeId,
        'name': ch.name,
        'role': ch.role,
        'description': ch.description,
        'appearance': ch.appearance,
        'personality': ch.personality,
        'image_status': ch.imageStatus,
        'image_url': ch.imageUrl,
        'image_local_path': ch.imageLocalPath,
        'image_error_message': ch.imageErrorMessage,
        'created_at': now,
        'updated_at': now
      };
      await store.insert(TABLE, values);
    }
  }

  /**
   * 增量写入角色（对齐 backend save_dedup_characters / Android upsertCharacters）：
   * - id > 0：UPDATE 文字字段，保留主键 / 立绘 / createdAt / episodeId
   * - id == 0：INSERT 新行
   * 本集未提到的已有角色**不删除**。
   */
  async upsertCharacters(projectId: number, characters: Character[]): Promise<void> {
    const store = await DramaDatabase.getStore();
    const now = Date.now();
    for (const ch of characters) {
      if (ch.id > 0) {
        const values: relationalStore.ValuesBucket = {
          'role': ch.role,
          'description': ch.description,
          'appearance': ch.appearance,
          'personality': ch.personality,
          'updated_at': now
        };
        const predicates = new relationalStore.RdbPredicates(TABLE);
        predicates.equalTo('id', ch.id);
        await store.update(values, predicates);
      } else {
        const values: relationalStore.ValuesBucket = {
          'project_id': projectId,
          'episode_id': ch.episodeId,
          'name': ch.name,
          'role': ch.role,
          'description': ch.description,
          'appearance': ch.appearance,
          'personality': ch.personality,
          'image_status': ch.imageStatus,
          'image_url': ch.imageUrl,
          'image_local_path': ch.imageLocalPath,
          'image_error_message': ch.imageErrorMessage,
          'created_at': now,
          'updated_at': now
        };
        await store.insert(TABLE, values);
      }
    }
  }

  // 查询某项目的所有角色
  async getCharacters(projectId: number): Promise<Character[]> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    const rs = await store.query(predicates, COLUMNS);
    const result: Character[] = [];
    try {
      while (rs.goToNextRow()) {
        result.push(mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return result;
  }

  // 删除某项目的全部角色记录，返回删除的行数
  async deleteCharactersForProject(projectId: number): Promise<number> {
    const store = await DramaDatabase.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('project_id', projectId);
    return store.delete(predicates);
  }

  /**
   * 更新单个角色的图片生成结果（URL、本地路径、错误信息）。
   */
  async updateCharacterImage(
    characterId: number,
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
    predicates.equalTo('id', characterId);
    await store.update(values, predicates);
  }

  /**
   * 更新单个角色的外貌描述（用于编辑提示词）。
   * 参照 updateCharacterImage 的查询模式。
   */
  async updateCharacterAppearance(
    characterId: number,
    appearance: string
  ): Promise<void> {
    const store = await DramaDatabase.getStore();
    const values: relationalStore.ValuesBucket = {
      'appearance': appearance,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', characterId);
    await store.update(values, predicates);
  }
}
