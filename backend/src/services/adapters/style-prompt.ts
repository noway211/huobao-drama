/**
 * 将 drama.style 转换为英文提示词片段
 */
export function getStylePrompt(style: string | null | undefined): string {
  const map: Record<string, string> = {
    realistic: 'photorealistic, lifelike details',
    anime: 'anime style, vibrant colors, clean lines',
    ghibli: 'Studio Ghibli style, soft watercolor, whimsical',
    cinematic: 'cinematic lighting, film grain, dramatic composition',
    comic: 'comic book style, bold outlines, dynamic panels',
    watercolor: 'watercolor painting, soft pastel tones, fluid washes',
    'traditional-chinese-xianxia': 'traditional Chinese xianxia fantasy art, ethereal celestial realm, flowing immortal robes, misty mountain peaks, ancient Taoist architecture, ink wash atmosphere, jade and gold accents, divine aura',
  }
  return map[style?.toLowerCase() || ''] || ''
}
