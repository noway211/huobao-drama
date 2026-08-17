import { router, promptAction } from '@kit.ArkUI';
import { ApiLogStore, ApiLogEntry } from '../remote/ApiLogStore';
import { Theme } from '../common/Theme';

/**
 * API 调用日志查看页 — 移植自 com.huobao.zdrama.ui.project.ApiLogActivity。
 * 数据源：ApiLogStore 内存环形缓冲（100 条上限），与 Android 端语义一致。
 */
@Entry
@Component
struct ApiLogPage {
  @State entries: ApiLogEntry[] = [];

  // 页面每次显示时重新拉取（用户可能刚从项目页跳转过来时已有新请求）
  onPageShow(): void {
    this.refresh();
  }

  private refresh(): void {
    // 倒序展示（最新在前），与 Android ApiLogStore.snapshot 行为一致
    const all: ApiLogEntry[] = ApiLogStore.snapshot();
    this.entries = all;
  }

  // 「清空」按钮：清空内存缓冲 + 刷新
  private onClearClick(): void {
    ApiLogStore.clear();
    this.refresh();
    promptAction.showToast({ message: '日志已清空' });
  }

  // 把 timestamp(ms) 格式化为 HH:mm:ss
  private formatTime(ts: number): string {
    const d: Date = new Date(ts);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  // 根据状态码决定 header 颜色（成功 = 绿色，失败 = 红色）
  private statusColor(statusCode: number): string {
    if (statusCode >= 200 && statusCode < 300) {
      return Theme.success;
    }
    return Theme.error;
  }

  // header 文本：HH:mm:ss  METHOD  STATUS  DURATIONms
  private headerText(entry: ApiLogEntry): string {
    const t: string = this.formatTime(entry.timestamp);
    const sc: string = entry.errorMessage !== null && entry.errorMessage.length > 0
      ? '失败'
      : `${entry.statusCode}`;
    return `${t}  ${entry.method}  ${sc}  ${entry.durationMs}ms`;
  }

  // 把请求/响应体里过长的内容截断展示，避免列表项过高
  private truncate(s: string, max: number = 4096): string {
    if (s.length <= max) {
      return s;
    }
    return s.substring(0, max) + `…（已截断 ${s.length - max} 字符）`;
  }

  build() {
    Column() {
      // ── 顶部栏 ──
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick((): void => { router.back(); })
        Text('API 调用日志')
          .fontSize(20)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .margin({ left: 12 })
        Button('清空')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .enabled(this.entries.length > 0)
          .opacity(this.entries.length > 0 ? 1 : 0.5)
          .onClick((): void => { this.onClearClick(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (this.entries.length === 0) {
        // ── 空态 ──
        Column() {
          Text('暂无 API 调用记录')
            .fontSize(15)
            .fontColor(Theme.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        // ── 列表 ──
        Scroll() {
          Column() {
            ForEach(this.entries, (entry: ApiLogEntry, index: number): void => {
              Column() {
                // header: 时间 方法 状态码 耗时（按成功/失败染色）
                Text(this.headerText(entry))
                  .fontSize(15)
                  .fontColor(this.statusColor(entry.statusCode))
                  .fontWeight(FontWeight.Bold)
                  .width('100%')

                // URL（可复制 — Harmony 暂不内置 selectable，但字号小可长按）
                Text(entry.url)
                  .fontSize(13)
                  .fontColor(Theme.textSecondary)
                  .width('100%')
                  .margin({ top: 4 })
                  .copyOption(CopyOptions.InApp)

                // 请求体（仅当非空时显示）
                if (entry.requestBody.length > 0) {
                  Text('请求')
                    .fontSize(13)
                    .fontColor(Theme.primary)
                    .fontWeight(FontWeight.Bold)
                    .width('100%')
                    .margin({ top: 8 })
                  Text(this.truncate(entry.requestBody))
                    .fontSize(12)
                    .fontColor(Theme.textPrimary)
                    .backgroundColor(Theme.bg)
                    .padding(8)
                    .width('100%')
                    .borderRadius(6)
                    .margin({ top: 2 })
                    .copyOption(CopyOptions.InApp)
                }

                // 响应 / 错误
                Text(entry.errorMessage !== null && entry.errorMessage.length > 0 ? '错误' : '响应')
                  .fontSize(13)
                  .fontColor(Theme.primary)
                  .fontWeight(FontWeight.Bold)
                  .width('100%')
                  .margin({ top: 8 })
                Text(this.truncate(entry.errorMessage ?? entry.responseBody ?? '-'))
                  .fontSize(12)
                  .fontColor(Theme.textPrimary)
                  .backgroundColor(Theme.bg)
                  .padding(8)
                  .width('100%')
                  .borderRadius(6)
                  .margin({ top: 2 })
                  .copyOption(CopyOptions.InApp)
              }
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .width('100%')
              .backgroundColor(Theme.surface)
              .borderRadius(10)
              .margin({ bottom: 16 })
            }, (entry: ApiLogEntry, index: number): string => {
              // 用 timestamp + url 哈希作 key 防止 ForEach 复用错位
              return `${entry.timestamp}-${entry.url}`;
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
