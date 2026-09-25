import { Injectable, Logger } from '@nestjs/common';

type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number }>;

export type AdminAlertChannel = 'none' | 'line' | 'webhook';

interface AdminAlertConfig {
  channel: AdminAlertChannel;
  /** LINE Messaging API: channel access token (long-lived) */
  lineToken?: string;
  /** LINE: userId / groupId ที่จะส่งข้อความเข้า (บอตต้องอยู่ในกลุ่มแล้ว) */
  lineTo?: string;
  /** Slack / Discord incoming webhook หรือระบบอื่นที่รับ JSON */
  webhookUrl?: string;
  /** ลิงก์หน้าแอดมิน แนบท้ายข้อความให้กดเข้าไปจัดการต่อ */
  adminUrl?: string;
}

export function readAdminAlertConfig(
  env: NodeJS.ProcessEnv = process.env,
): AdminAlertConfig {
  const channel = (env.ADMIN_ALERT_CHANNEL?.trim() ||
    'none') as AdminAlertChannel;
  return {
    channel: ['line', 'webhook'].includes(channel) ? channel : 'none',
    lineToken: env.LINE_CHANNEL_ACCESS_TOKEN?.trim(),
    lineTo: env.LINE_ADMIN_TO?.trim(),
    webhookUrl: env.ADMIN_ALERT_WEBHOOK_URL?.trim(),
    adminUrl: env.ADMIN_URL?.trim().replace(/\/$/, ''),
  };
}

/**
 * แจ้งทีมงานเมื่อมีเรื่องที่คนต้องจัดการ (ไม่มีช่างรับงาน, ช่างสมัครใหม่, คำขอเบิกเงิน)
 *
 * ส่งแบบ best effort ไม่ throw และไม่ใส่เบอร์โทร/ชื่อลูกค้าในข้อความแชท (PDPA)
 * รายละเอียดดูในหน้าแอดมินที่ต้องล็อกอิน
 */
@Injectable()
export class AdminAlertService {
  private readonly logger = new Logger(AdminAlertService.name);

  constructor(
    private readonly config: AdminAlertConfig = readAdminAlertConfig(),
    private readonly fetchImpl: FetchLike = fetch as unknown as FetchLike,
  ) {}

  async send(text: string): Promise<void> {
    const message = this.config.adminUrl
      ? `${text}\n${this.config.adminUrl}`
      : text;
    try {
      if (this.config.channel === 'line') {
        if (!this.config.lineToken || !this.config.lineTo) {
          this.logger.warn('ADMIN_ALERT_CHANNEL=line แต่ตั้งค่า LINE ไม่ครบ');
          return;
        }
        const response = await this.fetchImpl(
          'https://api.line.me/v2/bot/message/push',
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${this.config.lineToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              to: this.config.lineTo,
              messages: [{ type: 'text', text: message.slice(0, 4900) }],
            }),
          },
        );
        if (!response.ok) {
          this.logger.warn(`LINE push ไม่สำเร็จ HTTP ${response.status}`);
        }
        return;
      }
      if (this.config.channel === 'webhook') {
        if (!this.config.webhookUrl) {
          this.logger.warn(
            'ADMIN_ALERT_CHANNEL=webhook แต่ไม่มี ADMIN_ALERT_WEBHOOK_URL',
          );
          return;
        }
        // text = Slack, content = Discord ส่งทั้งคู่ให้ใช้ได้กับทั้งสองแบบ
        const response = await this.fetchImpl(this.config.webhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: message,
            content: message.slice(0, 1990),
          }),
        });
        if (!response.ok) {
          this.logger.warn(`admin webhook ไม่สำเร็จ HTTP ${response.status}`);
        }
        return;
      }
      this.logger.log(`[admin alert] ${text}`);
    } catch (error) {
      this.logger.warn(
        `ส่งแจ้งเตือนแอดมินไม่สำเร็จ: ${(error as Error).message}`,
      );
    }
  }

  noMatch(order: {
    orderNo: string;
    serviceName: string;
    area?: string | null;
  }) {
    return this.send(
      [
        `🚨 ไม่มีช่างรับงาน ${order.orderNo}`,
        `บริการ: ${order.serviceName}`,
        order.area ? `พื้นที่: ${order.area}` : null,
        'ลูกค้ารออยู่ ให้ติดต่อลูกค้า ส่งหาช่างอีกครั้ง หรือยกเลิกงานในหน้าแอดมิน',
      ]
        .filter(Boolean)
        .join('\n'),
    );
  }

  providerApplied(nickname: string) {
    return this.send(`🧰 ช่างสมัครใหม่: ${nickname} รอตรวจเอกสารและอนุมัติ`);
  }

  withdrawalRequested(nickname: string, amountText: string) {
    return this.send(`💸 คำขอเบิกเงิน ${amountText} จาก ${nickname} รอโอน`);
  }
}

/** ตัดเหลือแค่เขต/อำเภอ-จังหวัด ไม่ส่งบ้านเลขที่เข้าแชท */
export function coarseArea(address?: string | null): string | null {
  if (!address) return null;
  const parts = address
    .split(/[,\n]/)
    .map((part) => part.trim())
    .filter(Boolean);
  return parts.slice(-2).join(', ') || null;
}
