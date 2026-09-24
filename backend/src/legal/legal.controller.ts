import {
  Controller,
  Get,
  Header,
  NotFoundException,
  Param,
} from '@nestjs/common';

import { LEGAL_PAGES, LegalPage } from './content';

const escapeHtml = (value: string) =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

/** ค่าที่ยังไม่ได้ตั้งแสดงเป็นช่องว่างสีเหลือง ให้เห็นชัดว่าต้องกรอกก่อนเผยแพร่ */
function fill(text: string): string {
  const values: Record<string, [string | undefined, string]> = {
    company: [process.env.LEGAL_COMPANY_NAME, 'ชื่อบริษัท'],
    email: [process.env.LEGAL_CONTACT_EMAIL, 'อีเมลติดต่อ'],
    phone: [process.env.LEGAL_CONTACT_PHONE, 'เบอร์ติดต่อ'],
    address: [process.env.LEGAL_ADDRESS, 'ที่อยู่บริษัท'],
  };
  return escapeHtml(text).replace(/\{\{(\w+)\}\}/g, (_, key: string) => {
    const [value, label] = values[key] ?? [undefined, key];
    return value?.trim() ? escapeHtml(value.trim()) : `<mark>[${label}]</mark>`;
  });
}

function render(page: LegalPage): string {
  const sections = page.sections
    .map(
      (section) =>
        `<section><h2>${escapeHtml(section.heading)}</h2>${(
          section.paragraphs ?? []
        )
          .map((p) => `<p>${fill(p)}</p>`)
          .join('')}${
          section.bullets
            ? `<ul>${section.bullets.map((b) => `<li>${fill(b)}</li>`).join('')}</ul>`
            : ''
        }</section>`,
    )
    .join('');
  return `<!doctype html><html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(page.title)} | FixGo</title>
<style>
:root{--ink:#122821;--muted:#4A6259;--green:#0B5F45;--mint:#ECF8F1;--line:#D5E8DE}
body{margin:0;background:var(--mint);color:var(--ink);font:16px/1.7 "Noto Sans Thai",system-ui,sans-serif}
main{max-width:720px;margin:0 auto;padding:24px 16px 48px}
header{background:var(--green);color:#fff;border-radius:16px;padding:20px}
header h1{margin:0;font-size:24px}header p{margin:8px 0 0;color:#DDF3E7}
section{background:#fff;border:1px solid var(--line);border-radius:14px;padding:4px 18px;margin-top:14px}
h2{font-size:18px;color:var(--green);margin:14px 0 4px}ul{padding-left:22px}
mark{background:#FFF4DC;color:#9A5B00;padding:0 4px;border-radius:4px}
footer{color:var(--muted);font-size:13px;margin-top:20px}
</style></head><body><main>
<header><h1>${escapeHtml(page.title)}</h1><p>${fill(page.intro)}</p></header>
${sections}
<footer>FixGo · ปรับปรุงล่าสุด ${escapeHtml(process.env.LEGAL_UPDATED_AT ?? '')}</footer>
</main></body></html>`;
}

/** หน้าเว็บสาธารณะสำหรับลิงก์ใน App Store / Google Play และลิงก์จากในแอป */
@Controller('legal')
export class LegalController {
  @Get(':page')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'public, max-age=300')
  page(@Param('page') name: string): string {
    const page = LEGAL_PAGES[name];
    if (!page) throw new NotFoundException('ไม่พบหน้านี้');
    return render(page);
  }
}
