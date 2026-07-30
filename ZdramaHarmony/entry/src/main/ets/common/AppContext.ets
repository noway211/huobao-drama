import { common } from '@kit.AbilityKit';

/**
 * Holds a process-wide reference to the ability UIAbilityContext so that the
 * data / settings layers (RDB, Preferences) can access the app context without
 * threading it through every call site — mirrors how the Android port relied on
 * a static application Context.
 */
export class AppContext {
  private static ctx: common.UIAbilityContext | null = null;

  // 初始化并保存全局的 UIAbilityContext，需在 EntryAbility.onCreate 中最先调用
  static init(context: common.UIAbilityContext): void {
    AppContext.ctx = context;
  }

  // 获取全局的 UIAbilityContext，若尚未初始化则抛出异常
  static get(): common.UIAbilityContext {
    if (!AppContext.ctx) {
      throw new Error('AppContext not initialized. EntryAbility.onCreate must run first.');
    }
    return AppContext.ctx;
  }
}
