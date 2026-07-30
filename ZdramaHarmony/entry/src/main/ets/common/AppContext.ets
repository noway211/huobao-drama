import { common } from '@kit.AbilityKit';

/**
 * Holds a process-wide reference to the ability UIAbilityContext so that the
 * data / settings layers (RDB, Preferences) can access the app context without
 * threading it through every call site — mirrors how the Android port relied on
 * a static application Context.
 */
export class AppContext {
  private static ctx: common.UIAbilityContext | null = null;

  static init(context: common.UIAbilityContext): void {
    AppContext.ctx = context;
  }

  static get(): common.UIAbilityContext {
    if (!AppContext.ctx) {
      throw new Error('AppContext not initialized. EntryAbility.onCreate must run first.');
    }
    return AppContext.ctx;
  }
}
