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
    hilog.info(DOMAIN, TAG, 'RDB ready: %{public}s', DB_NAME);
    return store;
  }
}
