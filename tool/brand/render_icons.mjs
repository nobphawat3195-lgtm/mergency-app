// สร้างไฟล์ไอคอนทุกขนาดจาก fixgo_logo.svg / fixgo_fixer_logo.svg
// ใช้: node tool/brand/render_icons.mjs <โฟลเดอร์ output>
// ต้องมี Playwright + Chromium (ใช้ render SVG ให้ตรงกับเบราว์เซอร์จริง)
// ได้ไฟล์ PNG 1024px: <name>_full.png (มีพื้น) และ <name>_mark.png (โปร่งใส ไม่มีพื้น)
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
// ระบุที่อยู่ playwright เองได้ด้วย PLAYWRIGHT_MODULE ถ้าไม่ได้ติดตั้งในโปรเจกต์
const { chromium } = createRequire(import.meta.url)(
  process.env.PLAYWRIGHT_MODULE ?? 'playwright',
);
const out = process.argv[2] ?? join(here, 'out');
mkdirSync(out, { recursive: true });
const font = readFileSync(
  join(here, '../../packages/fixgo_core/assets/fonts/NotoSansThai-ExtraBold.ttf'),
).toString('base64');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
for (const name of ['fixgo_logo', 'fixgo_fixer_logo']) {
  const svg = readFileSync(join(here, `${name}.svg`), 'utf8').replace(
    '<rect id="background"',
    `<style>@font-face{font-family:'Noto Sans Thai';font-weight:800;src:url(data:font/ttf;base64,${font})}</style><rect id="background"`,
  );
  for (const [suffix, withBackground] of [['full', true], ['mark', false]]) {
    const body = withBackground ? svg : svg.replace(/<rect id="background"[^>]*\/>/, '');
    await page.setContent(`<html><body style="margin:0;background:transparent">${body}</body></html>`);
    await page.evaluate(() => document.fonts.ready);
    await page.locator('svg').screenshot({ path: join(out, `${name}_${suffix}.png`), omitBackground: true });
  }
}
await browser.close();
