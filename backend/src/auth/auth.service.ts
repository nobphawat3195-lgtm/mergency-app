import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { OTP_MAX_ATTEMPTS, OTP_TTL_MS } from '../common/constants';

export interface JwtPayload {
  sub: string;
  role: Role;
  phone: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  private hashCode(phone: string, role: Role, code: string): string {
    const secret = process.env.OTP_SECRET ?? 'dev-otp-secret';
    return createHmac('sha256', secret)
      .update(`${phone}:${role}:${code}`)
      .digest('hex');
  }

  /** ส่ง OTP ไปยังเบอร์โทร คืน code กลับมาเฉพาะตอน dev เพื่อทดสอบได้โดยไม่ต้องต่อ SMS gateway */
  async requestOtp(
    phone: string,
    role: Role,
  ): Promise<{ sent: true; devCode?: string }> {
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');

    await this.prisma.otpCode.create({
      data: {
        phone,
        role,
        codeHash: this.hashCode(phone, role, code),
        expiresAt: new Date(Date.now() + OTP_TTL_MS),
      },
    });

    // TODO: ต่อ SMS gateway จริงตอน production
    return process.env.NODE_ENV === 'production'
      ? { sent: true }
      : { sent: true, devCode: code };
  }

  async verifyOtp(
    phone: string,
    role: Role,
    code: string,
  ): Promise<{ accessToken: string; hasProfile: boolean; userId: string | null }> {
    const record = await this.prisma.otpCode.findFirst({
      where: { phone, role, consumed: false, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!record) {
      throw new UnauthorizedException('OTP หมดอายุหรือไม่ถูกต้อง');
    }

    if (record.attempts >= OTP_MAX_ATTEMPTS) {
      throw new UnauthorizedException('ใส่รหัสผิดเกินจำนวนที่กำหนด');
    }

    const expected = Buffer.from(record.codeHash, 'hex');
    const actual = Buffer.from(this.hashCode(phone, role, code), 'hex');
    const matched =
      expected.length === actual.length && timingSafeEqual(expected, actual);

    if (!matched) {
      await this.prisma.otpCode.update({
        where: { id: record.id },
        data: { attempts: { increment: 1 } },
      });
      throw new UnauthorizedException('รหัส OTP ไม่ถูกต้อง');
    }

    await this.prisma.otpCode.update({
      where: { id: record.id },
      data: { consumed: true },
    });

    return this.issueToken(phone, role);
  }

  private async issueToken(
    phone: string,
    role: Role,
  ): Promise<{ accessToken: string; hasProfile: boolean; userId: string | null }> {
    if (role === Role.CUSTOMER) {
      // ลูกค้าไม่ต้องกรอกโปรไฟล์ก่อนใช้งาน สร้างให้อัตโนมัติตอน verify ผ่าน
      const customer = await this.prisma.customer.upsert({
        where: { phone },
        create: { phone },
        update: {},
      });
      return {
        accessToken: await this.sign({
          sub: customer.id,
          role,
          phone,
        }),
        hasProfile: true,
        userId: customer.id,
      };
    }

    if (role === Role.PROVIDER) {
      // ช่างต้องกรอกแบบฟอร์มลงทะเบียนก่อน โทเคนช่วงนี้ใช้ยื่นใบสมัครได้อย่างเดียว
      const provider = await this.prisma.provider.findUnique({
        where: { phone },
      });
      return {
        accessToken: await this.sign({
          sub: provider?.id ?? `pending:${phone}`,
          role,
          phone,
        }),
        hasProfile: provider !== null,
        userId: provider?.id ?? null,
      };
    }

    throw new BadRequestException('ผู้ดูแลระบบเข้าสู่ระบบผ่านช่องทางนี้ไม่ได้');
  }

  private sign(payload: JwtPayload): Promise<string> {
    return this.jwt.signAsync(payload);
  }
}
