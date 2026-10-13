import { Injectable, Logger } from '@nestjs/common';

import { PrismaService } from '../prisma/prisma.service';
import { formatBaht } from '../common/money';
import { publicFixerUrl } from '../config/environment';
import { FetchLike, LineMessage, linePush } from './line-push';

export interface ProviderLineConfig {
  enabled: boolean;
  /** channel access token (long-lived) ของ Messaging API */
  token?: string;
  /** ปุ่มในข้อความพาไปเว็บแอปช่าง */
  fixerUrl: string | null;
  /** ลิงก์เพิ่มเพื่อน LINE OA แสดงเป็นการ์ดในหน้าหลักแอปช่าง */
  addFriendUrl?: string;
}

export function readProviderLineConfig(
  env: NodeJS.ProcessEnv = process.env,
): ProviderLineConfig {
  return {
    enabled: env.PROVIDER_LINE_ALERTS?.trim().toLowerCase() === 'true',
    // ใช้ OA เดียวกับแจ้งเตือนแอดมินได้ ถ้าไม่ตั้งแยก
    token:
      env.LINE_MESSAGING_TOKEN?.trim() ||
      env.LINE_CHANNEL_ACCESS_TOKEN?.trim() ||
      undefined,
    fixerUrl: publicFixerUrl(env),
    addFriendUrl: env.LINE_OA_ADD_FRIEND_URL?.trim() || undefined,
  };
}

/** ลิงก์เพิ่มเพื่อน OA สำหรับช่างที่ผูก LINE แล้ว (null = ไม่ต้องแสดงการ์ด) */
export function providerLineAddFriendUrl(
  provider: { lineUserId: string | null },
  config: ProviderLineConfig = readProviderLineConfig(),
): string | null {
  if (!config.enabled || !provider.lineUserId) return null;
  return config.addFriendUrl ?? null;
}

/** ข้อความในเทมเพลตปุ่มของ LINE ยาวได้ไม่เกิน 160 ตัวอักษร */
const BUTTONS_TEXT_MAX = 160;
const BUTTON_LABEL = 'เปิดรับงาน';

export interface OfferLineOrder {
  serviceName: string;
  /** เขต/อำเภอ จังหวัด (ไม่ใส่บ้านเลขที่) */
  area: string | null;
  priceSatang: number;
}

export function offerLineText(
  order: OfferLineOrder,
  timeoutMs: number,
): string {
  const seconds = Math.round(timeoutMs / 1000);
  // ปัดลง: บอกเวลาน้อยกว่าจริงดีกว่าให้ช่างกดตอนหมดเวลาแล้ว
  const window =
    seconds >= 60 ? `${Math.floor(seconds / 60)} นาที` : `${seconds} วินาที`;
  return [
    '🔔 มีงานใหม่ใกล้คุณ',
    order.area ? `${order.serviceName} · ${order.area}` : order.serviceName,
    `ราคาประเมิน ${formatBaht(order.priceSatang)}`,
    `กดรับภายใน ${window}`,
  ].join('\n');
}

/**
 * แจ้งเตือนช่างผ่าน LINE OA (ใช้ระหว่างที่ยังไม่มีแอปในสโตร์ เว็บแอปแจ้งเตือนได้เฉพาะตอนเปิดหน้าอยู่)
 *
 * ส่งแบบ fire-and-forget: ไม่ throw ไม่รอ ส่งไม่สำเร็จแค่เขียน warn log
 * LINE ส่งได้เฉพาะช่างที่ล็อกอินด้วย LINE และเพิ่มเพื่อน OA แล้ว
 */
@Injectable()
export class ProviderLineService {
  private readonly logger = new Logger(ProviderLineService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ProviderLineConfig = readProviderLineConfig(),
    private readonly fetchImpl: FetchLike = fetch as unknown as FetchLike,
  ) {}

  get enabled(): boolean {
    return this.config.enabled;
  }

  /** งานใหม่เสนอให้ช่างกลุ่มนี้ */
  async offer(
    providerIds: string[],
    order: OfferLineOrder,
    timeoutMs: number,
  ): Promise<void> {
    await this.sendTo(providerIds, offerLineText(order, timeoutMs));
  }

  /** ลูกค้ายืนยัน/ไม่ยืนยันราคา หรืองานถูกยกเลิก */
  async orderUpdate(
    providerId: string | null,
    title: string,
    body: string,
  ): Promise<void> {
    if (!providerId) return;
    await this.sendTo([providerId], `${title}\n${body}`);
  }

  private message(text: string): LineMessage {
    if (!this.config.fixerUrl) return { type: 'text', text };
    return {
      type: 'template',
      altText: text.slice(0, 400),
      template: {
        type: 'buttons',
        text:
          text.length > BUTTONS_TEXT_MAX
            ? `${text.slice(0, BUTTONS_TEXT_MAX - 1)}…`
            : text,
        actions: [
          { type: 'uri', label: BUTTON_LABEL, uri: `${this.config.fixerUrl}/` },
        ],
      },
    };
  }

  private async sendTo(providerIds: string[], text: string): Promise<void> {
    if (!this.config.enabled || providerIds.length === 0) return;
    const token = this.config.token;
    if (!token) {
      this.logger.warn(
        'PROVIDER_LINE_ALERTS=true แต่ไม่มี LINE_MESSAGING_TOKEN ไม่ได้ส่ง LINE',
      );
      return;
    }
    try {
      const providers = await this.prisma.provider.findMany({
        where: { id: { in: providerIds }, lineUserId: { not: null } },
        select: { id: true, lineUserId: true },
      });
      const message = this.message(text);
      await Promise.all(
        providers.map(async ({ id, lineUserId }) => {
          try {
            const response = await linePush(
              this.fetchImpl,
              token,
              lineUserId!,
              [message],
            );
            if (!response.ok) {
              this.logger.warn(
                `LINE ถึงช่าง ${id} ไม่สำเร็จ HTTP ${response.status}`,
              );
            }
          } catch (error) {
            this.logger.warn(
              `LINE ถึงช่าง ${id} ไม่สำเร็จ: ${(error as Error).message}`,
            );
          }
        }),
      );
    } catch (error) {
      this.logger.warn(
        `ส่ง LINE ถึงช่างไม่สำเร็จ: ${(error as Error).message}`,
      );
    }
  }
}
