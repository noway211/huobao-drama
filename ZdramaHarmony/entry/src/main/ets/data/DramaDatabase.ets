import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../common/AppContext';

const DOMAIN = 0x0001;
const TAG = 'DramaDatabase';

/**
 * Ports com.huobao.zdrama.data.local.DramaLocalDatabase (SQLiteOpenHelper) to
 * HarmonyOS relationalStore. MVP scope keeps `projects` + `episodes`; the
 * `storyboards` table is created too so a later phase can fill it in without a
 * schema bump.
 *
 * Enum columns are stored as their string names (matching the Android schema).
 * No FK constraints — cascades are handled in the repository layer.
 * Migrations: storyboards.character_ids and characters table may need ALTER TABLE
 * for existing databases; handled in open().
 */

// 数据库文件名
const DB_NAME = 'zdrama.db';

// 建表 SQL：projects（项目表），枚举列以字符串名存储，无外键约束
const CREATE_PROJECTS = `
CREATE TABLE IF NOT EXISTS projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  prompt TEXT NOT NULL,
  style TEXT NOT NULL,
  target_audience TEXT NOT NULL,
  aspect_ratio TEXT NOT NULL,
  shot_count INTEGER NOT NULL,
  shot_duration_seconds INTEGER NOT NULL,
  status TEXT NOT NULL,
  current_stage TEXT NOT NULL,
  error_message TEXT,
  generated_script TEXT,
  final_video_status TEXT NOT NULL DEFAULT 'PENDING',
  final_video_local_path TEXT,
  final_video_error_message TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

// 建表 SQL：episodes（剧集表），归属于某个 project
const CREATE_EPISODES = `
CREATE TABLE IF NOT EXISTS episodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  episode_number INTEGER NOT NULL DEFAULT 1,
  episode_title TEXT NOT NULL DEFAULT '',
  content TEXT,
  script_content TEXT,
  episode_status TEXT NOT NULL DEFAULT 'DRAFT',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

// 建表 SQL：storyboards（分镜表），当前 MVP 阶段仅建表、暂不写入
const CREATE_STORYBOARDS = `
CREATE TABLE IF NOT EXISTS storyboards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  episode_id INTEGER,
  shot_number INTEGER NOT NULL,
  scene TEXT NOT NULL,
  action TEXT NOT NULL,
  dialogue TEXT NOT NULL,
  camera TEXT NOT NULL,
  image_prompt TEXT NOT NULL,
  video_prompt TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  character_ids TEXT,
  image_status TEXT NOT NULL DEFAULT 'PENDING',
  image_url TEXT,
  image_local_path TEXT,
  image_error_message TEXT,
  video_status TEXT NOT NULL DEFAULT 'PENDING',
  video_task_id TEXT,
  video_url TEXT,
  video_local_path TEXT,
  video_error_message TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

// 建表 SQL：characters（角色表）
const CREATE_CHARACTERS = `
CREATE TABLE IF NOT EXISTS characters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  episode_id INTEGER,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  appearance TEXT NOT NULL DEFAULT '',
  personality TEXT NOT NULL DEFAULT '',
  image_status TEXT NOT NULL DEFAULT 'PENDING',
  image_url TEXT,
  image_local_path TEXT,
  image_error_message TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

export class DramaDatabase {
  private static store: relationalStore.RdbStore | null = null;
  private static initializing: Promise<relationalStore.RdbStore> | null = null;

  /** 懒加载获取（首次会建表）共享的 RDB 数据库实例。 */
  static async getStore(): Promise<relationalStore.RdbStore> {
    if (DramaDatabase.store) {
      return DramaDatabase.store;
    }
    if (DramaDatabase.initializing) {
      return DramaDatabase.initializing;
    }
    DramaDatabase.initializing = DramaDatabase.open();
    try {
      DramaDatabase.store = await DramaDatabase.initializing;
      return DramaDatabase.store;
    } finally {
      DramaDatabase.initializing = null;
    }
  }

  // 实际打开数据库并创建三张表（projects/episodes/storyboards）
  private static async open(): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(AppContext.get(), config);
    await store.executeSql(CREATE_PROJECTS);
    await store.executeSql(CREATE_EPISODES);
    await store.executeSql(CREATE_STORYBOARDS);
    await store.executeSql(CREATE_CHARACTERS);

    // 兼容已有数据库：storyboards 表可能缺少 character_ids 列
    await DramaDatabase.addColumnIfMissing(store, 'storyboards', 'character_ids', 'TEXT');

    hilog.info(DOMAIN, TAG, 'RDB ready: %{public}s', DB_NAME);
    return store;
  }

  /**
   * 兼容已有数据库的新增列迁移：如果表中不存在目标列，执行 ALTER TABLE ADD COLUMN。
   * SQLite 的 ALTER TABLE 不支持 IF NOT EXISTS，所以需要先查列是否存在。
   */
  private static async addColumnIfMissing(
    store: relationalStore.RdbStore,
    table: string,
    column: string,
    columnDef: string
  ): Promise<void> {
    try {
      const sql = `PRAGMA table_info(${table})`;
      const rs = await store.querySql(sql);
      let exists = false;
      try {
        while (rs.goToNextRow()) {
          const idx = rs.getColumnIndex('name');
          if (rs.getString(idx) === column) {
            exists = true;
            break;
          }
        }
      } finally {
        rs.close();
      }
      if (!exists) {
        await store.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${columnDef}`);
        hilog.info(DOMAIN, TAG, 'added column %{public}s to %{public}s', column, table);
      }
    } catch (err) {
      // ALTER TABLE 可能在极端情况下失败（如表被锁），记录日志但不阻断启动
      hilog.warn(DOMAIN, TAG, 'addColumnIfMissing %{public}s.%{public}s: %{public}s',
        table, column, JSON.stringify(err));
    }
  }
}
