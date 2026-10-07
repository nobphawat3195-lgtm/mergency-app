import { BadRequestException, Injectable } from '@nestjs/common';
import { ChatSender, OrderStatus, Role } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { PushService } from '../notifications/push.service';
import { UploadsService } from '../uploads/uploads.service';
import { OrdersService } from './orders.service';
import { SendOrderMessageDto } from './dto/order-chat.dto';

/** ส่งข้อความได้ตั้งแต่ช่างรับงานจนงานจบ */
const CHAT_OPEN_STATUSES: OrderStatus[] = [
  OrderStatus.MATCHED,
  OrderStatus.EN_ROUTE,
  OrderStatus.IN_PROGRESS,
];

const MESSAGE_SELECT = {
  id: true,
  sender: true,
  text: true,
  imageUrl: true,
  createdAt: true,
} as const;

interface ChatActor {
  sub: string;
  role: Role;
}

interface ChatOrder {
  id: string;
  status: OrderStatus;
  providerId: string | null;
  chatCustomerReadAt: Date | null;
  chatProviderReadAt: Date | null;
}

function senderOf(role: Role): ChatSender {
  return role === Role.PROVIDER ? ChatSender.PROVIDER : ChatSender.CUSTOMER;
}

/**
 * แชทต่อออเดอร์ระหว่างลูกค้ากับช่างที่ได้งาน
 *
 * สิทธิ์ใช้ OrdersService.findAccessibleById: คนนอกงานได้ 404 เหมือนดูรายละเอียดงาน
 * หลังงานจบหรือยกเลิกอ่านย้อนหลังได้ แต่ส่งเพิ่มไม่ได้
 * แจ้งอีกฝ่ายผ่าน SSE ของงาน (แอปที่เปิดหน้าอยู่ดึงใหม่ทันที) และ push ถ้าตั้งค่า Firebase แล้ว
 */
@Injectable()
export class OrderChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly orders: OrdersService,
    private readonly uploads: UploadsService,
    private readonly push: PushService,
  ) {}

  isOpen(order: Pick<ChatOrder, 'status' | 'providerId'>): boolean {
    return (
      order.providerId !== null && CHAT_OPEN_STATUSES.includes(order.status)
    );
  }

  /** ข้อความใหม่ของอีกฝ่ายที่ผู้เรียกยังไม่ได้เปิดอ่าน */
  async unreadFor(order: ChatOrder, role: Role): Promise<number> {
    if (!order.providerId) return 0;
    const mine = senderOf(role);
    const readAt =
      mine === ChatSender.CUSTOMER
        ? order.chatCustomerReadAt
        : order.chatProviderReadAt;
    return this.prisma.orderMessage.count({
      where: {
        orderId: order.id,
        sender: { not: mine },
        ...(readAt ? { createdAt: { gt: readAt } } : {}),
      },
    });
  }

  async hasMessages(orderId: string): Promise<boolean> {
    const first = await this.prisma.orderMessage.findFirst({
      where: { orderId },
      select: { id: true },
    });
    return first !== null;
  }

  /** จำนวนที่ยังไม่อ่านของหลายงาน (หน้ารายการงานของช่าง) */
  async unreadForProvider(
    orders: Pick<ChatOrder, 'id' | 'chatProviderReadAt'>[],
  ): Promise<Map<string, number>> {
    const counts = new Map<string, number>();
    await Promise.all(
      orders.map(async (order) => {
        const unread = await this.prisma.orderMessage.count({
          where: {
            orderId: order.id,
            sender: ChatSender.CUSTOMER,
            ...(order.chatProviderReadAt
              ? { createdAt: { gt: order.chatProviderReadAt } }
              : {}),
          },
        });
        if (unread > 0) counts.set(order.id, unread);
      }),
    );
    return counts;
  }

  /** เปิดแชท: คืนข้อความทั้งหมด (ล่าสุด 500) และบันทึกว่าอ่านแล้ว */
  async list(orderId: string, actor: ChatActor) {
    const order = await this.orders.findAccessibleById(orderId, actor);
    const messages = await this.prisma.orderMessage.findMany({
      where: { orderId },
      orderBy: { createdAt: 'asc' },
      take: 500,
      select: MESSAGE_SELECT,
    });
    await this.prisma.order.update({
      where: { id: orderId },
      data:
        actor.role === Role.PROVIDER
          ? { chatProviderReadAt: new Date() }
          : { chatCustomerReadAt: new Date() },
    });
    return { canSend: this.isOpen(order), messages };
  }

  async send(orderId: string, actor: ChatActor, dto: SendOrderMessageDto) {
    const order = await this.orders.findAccessibleById(orderId, actor);
    if (!this.isOpen(order)) {
      throw new BadRequestException(
        order.providerId
          ? 'งานนี้จบแล้ว แชทอ่านย้อนหลังได้อย่างเดียว'
          : 'ส่งข้อความได้หลังช่างรับงาน',
      );
    }
    const text = dto.text?.trim() || null;
    const imageUrl = dto.imageUrl ?? null;
    if (!text && !imageUrl) {
      throw new BadRequestException('พิมพ์ข้อความหรือแนบรูปก่อนส่ง');
    }
    if (imageUrl) {
      this.uploads.assertOwnedUploads([imageUrl], actor.sub, 'ORDER');
    }
    const sender = senderOf(actor.role);
    const now = new Date();
    const [message] = await this.prisma.$transaction([
      this.prisma.orderMessage.create({
        data: { orderId, sender, text, imageUrl, createdAt: now },
        select: MESSAGE_SELECT,
      }),
      // ข้อความของตัวเองถือว่าอ่านแล้ว
      this.prisma.order.update({
        where: { id: orderId },
        data:
          sender === ChatSender.PROVIDER
            ? { chatProviderReadAt: now }
            : { chatCustomerReadAt: now },
      }),
    ]);
    const ref = { id: order.id, orderNo: order.orderNo };
    void (sender === ChatSender.PROVIDER
      ? this.push.chatMessage(Role.CUSTOMER, order.customerId, ref, 'ช่าง')
      : this.push.chatMessage(Role.PROVIDER, order.providerId!, ref, 'ลูกค้า'));
    return message;
  }

  /** แอดมินเปิดอ่านกรณีมีปัญหา (บันทึก audit ที่ controller) ไม่เปลี่ยนสถานะอ่าน */
  listForAdmin(orderId: string) {
    return this.prisma.orderMessage.findMany({
      where: { orderId },
      orderBy: { createdAt: 'asc' },
      select: MESSAGE_SELECT,
    });
  }
}
