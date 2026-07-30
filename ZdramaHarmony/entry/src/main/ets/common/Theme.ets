/** Shared dark-theme palette, ported from the Android colors.xml dark theme. */
export class Theme {
  static readonly bg = '#121212';
  static readonly surface = '#1E1E1E';
  static readonly surfaceAlt = '#262626';
  static readonly primary = '#E53935';
  static readonly primaryDisabled = '#4A3A3A';
  static readonly textPrimary = '#FFFFFF';
  static readonly textSecondary = '#B0B0B0';
  static readonly textHint = '#7A7A7A';
  static readonly border = '#333333';
  static readonly success = '#4CAF50';
  static readonly error = '#EF5350';
}

/** Map ProjectStatus / stage enum values to Chinese labels for display. */
export function statusLabel(status: string): string {
  switch (status) {
    case 'DRAFT': return '草稿';
    case 'PROCESSING': return '生成中';
    case 'COMPLETED': return '已完成';
    case 'FAILED': return '失败';
    case 'CANCELLED': return '已取消';
    default: return status;
  }
}

export function stageLabel(stage: string): string {
  switch (stage) {
    case 'NONE': return '未开始';
    case 'TEXT': return '脚本';
    case 'STORYBOARD': return '分镜';
    case 'IMAGE': return '图片';
    case 'VIDEO': return '视频';
    case 'FINAL_VIDEO': return '成片合成';
    default: return stage;
  }
}
