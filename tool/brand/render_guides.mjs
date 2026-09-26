// ภาพตัวอย่างมุมถ่ายของช่องภาพหลักฐานตรวจรถ (ต้นฉบับ SVG ใน guides/ แก้ไขได้)
// ใช้: PLAYWRIGHT_MODULE=<path>/playwright node tool/brand/render_guides.mjs
// ได้ PNG 480x300 ที่ packages/fixgo_core/assets/guides/<SLOT_CODE>.png
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { chromium } = createRequire(import.meta.url)(
  process.env.PLAYWRIGHT_MODULE ?? 'playwright',
);
const out = join(here, '../../packages/fixgo_core/assets/guides');
mkdirSync(out, { recursive: true });
const font = readFileSync(
  join(here, '../../packages/fixgo_core/assets/fonts/NotoSansThai-Bold.ttf'),
).toString('base64');

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 320, height: 200 },
  deviceScaleFactor: 1.5,
});
for (const file of readdirSync(join(here, 'guides')).filter((f) => f.endsWith('.svg'))) {
  const svg = readFileSync(join(here, 'guides', file), 'utf8').replace(
    '<rect id="background"',
    `<style>@font-face{font-family:'Noto Sans Thai';font-weight:700;src:url(data:font/ttf;base64,${font})}text{font-family:'Noto Sans Thai',sans-serif}text[font-family=monospace]{font-family:monospace}</style><rect id="background"`,
  );
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.evaluate(() => document.fonts.ready);
  await page.locator('svg').screenshot({ path: join(out, file.replace('.svg', '.png')), omitBackground: true });
}
await browser.close();
