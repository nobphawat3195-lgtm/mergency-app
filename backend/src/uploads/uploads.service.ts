import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  DeleteObjectsCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { link, mkdir, rm, unlink } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';

import { PresignUploadDto } from './dto/presign-upload.dto';

const EXTENSIONS: Record<PresignUploadDto['contentType'], string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export type UploadScope = PresignUploadDto['scope'];

const DIRECTORIES: Record<UploadScope, string> = {
  ORDER: 'orders',
  PROVIDER_TOOL: 'provider-tools',
  INSPECTION: 'inspections',
  PAYMENT_SLIP: 'payment-slips',
};

const UUID_FILE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$/;

/** key ของไฟล์ในโหมด local: <ไดเรกทอรี>/<userId>/<uuid>.<ext> ห้ามมี .. หรือ / เกิน */
export const LOCAL_KEY =
  /^(orders|provider-tools|inspections|payment-slips)\/([A-Za-z0-9:_-]{1,80})\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp))$/;

export const CONTENT_TYPES: Record<string, PresignUploadDto['contentType']> = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

/** ตรวจ magic bytes กันไฟล์อื่น (เช่น HTML) ปลอมเป็นรูป */
function looksLikeImage(
  head: Buffer,
  contentType: PresignUploadDto['contentType'],
): boolean {
  switch (contentType) {
    case 'image/jpeg':
      return (
        head.length >= 3 &&
        head[0] === 0xff &&
        head[1] === 0xd8 &&
        head[2] === 0xff
      );
    case 'image/png':
      return head
        .subarray(0, 8)
        .equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    case 'image/webp':
      return (
        head.subarray(0, 4).toString('latin1') === 'RIFF' &&
        head.subarray(8, 12).toString('latin1') === 'WEBP'
      );
  }
}

export type StorageMode = 's3' | 'local' | 'none';

@Injectable()
export class UploadsService {
  private readonly logger = new Logger(UploadsService.name);
  private readonly bucket = process.env.S3_BUCKET;
  private readonly publicBaseUrl: string | undefined;
  private readonly client: S3Client | null = null;
  readonly mode: StorageMode;

  /** โหมด local: เก็บไฟล์บนดิสก์ของเซิร์ฟเวอร์ ไม่ต้องใช้ R2/S3 */
  private readonly uploadDir =
    process.env.UPLOAD_DIR?.trim() || '/data/uploads';
  private readonly apiBaseUrl: string;
  private readonly signingKey: string;

  constructor() {
    const apiDomain = process.env.API_DOMAIN?.trim();
    this.apiBaseUrl = (
      process.env.PUBLIC_API_URL?.trim() ||
      (apiDomain ? `https://${apiDomain}` : 'http://localhost:3000')
    ).replace(/\/$/, '');
    this.signingKey = `uploads:${process.env.JWT_SECRET ?? 'dev-only-secret'}`;

    if (process.env.STORAGE_PROVIDER?.trim() === 'local') {
      this.mode = 'local';
      this.publicBaseUrl = `${this.apiBaseUrl}/api/uploads/files`;
      return;
    }

    this.publicBaseUrl = process.env.S3_PUBLIC_BASE_URL?.replace(/\/$/, '');
    const accessKeyId = process.env.S3_ACCESS_KEY_ID;
    const secretAccessKey = process.env.S3_SECRET_ACCESS_KEY;
    if (
      !this.bucket ||
      !this.publicBaseUrl ||
      !accessKeyId ||
      !secretAccessKey
    ) {
      this.mode = 'none';
      return;
    }

    this.mode = 's3';
    this.client = new S3Client({
      region: process.env.S3_REGION ?? 'auto',
      endpoint: process.env.S3_ENDPOINT,
      forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
      credentials: { accessKeyId, secretAccessKey },
    });
  }

  async createPresignedUpload(
    userId: string,
    role: string,
    dto: PresignUploadDto,
  ) {
    if (this.mode === 'none') {
      throw new ServiceUnavailableException(
        'ระบบแนบรูปยังไม่ได้ตั้งค่า object storage',
      );
    }

    if (
      (dto.scope === 'PROVIDER_TOOL' || dto.scope === 'INSPECTION') &&
      role !== 'PROVIDER'
    ) {
      throw new ForbiddenException('บัญชีนี้แนบรูปเครื่องมือช่างไม่ได้');
    }
    if (dto.scope === 'PAYMENT_SLIP' && role !== 'CUSTOMER') {
      throw new ForbiddenException('แนบสลิปได้เฉพาะลูกค้า');
    }

    const key = `${DIRECTORIES[dto.scope]}/${userId}/${randomUUID()}.${EXTENSIONS[dto.contentType]}`;
    if (this.mode === 'local') {
      const expires = Math.floor(Date.now() / 1000) + 5 * 60;
      const signature = this.sign(key, dto.byteLength, expires);
      const query = new URLSearchParams({
        size: String(dto.byteLength),
        exp: String(expires),
        sig: signature,
      });
      return {
        uploadUrl: `${this.apiBaseUrl}/api/uploads/local/${key}?${query}`,
        publicUrl: `${this.publicBaseUrl}/${key}`,
        headers: { 'Content-Type': dto.contentType },
        expiresInSeconds: 5 * 60,
      };
    }
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: dto.contentType,
      ContentLength: dto.byteLength,
      CacheControl: 'public, max-age=31536000, immutable',
    });
    const uploadUrl = await getSignedUrl(this.client!, command, {
      expiresIn: 5 * 60,
    });

    return {
      uploadUrl,
      publicUrl: `${this.publicBaseUrl}/${key}`,
      headers: { 'Content-Type': dto.contentType },
      expiresInSeconds: 5 * 60,
    };
  }

  /**
   * รับเฉพาะรูปที่ผู้ใช้คนนี้อัปโหลดผ่าน /uploads/presign ของเราเอง
   *
   * กันไม่ให้ส่ง URL ภายนอก (รูปไม่เหมาะสม, tracking pixel) หรือรูปของคนอื่นเข้ามา
   * แสดงให้อีกฝ่ายเห็น ตอนพัฒนาที่ยังไม่ตั้ง object storage จะข้ามการตรวจ
   */
  assertOwnedUploads(
    urls: readonly string[] | undefined,
    userId: string,
    scope: UploadScope,
  ): void {
    if (!urls?.length || !this.publicBaseUrl) return;
    const prefix = `${this.publicBaseUrl}/${DIRECTORIES[scope]}/${userId}/`;
    for (const url of urls) {
      const file = url.startsWith(prefix) ? url.slice(prefix.length) : null;
      if (!file || !UUID_FILE.test(file)) {
        throw new BadRequestException(
          'รูปต้องอัปโหลดผ่านแอป FixGo ของบัญชีนี้เท่านั้น',
        );
      }
    }
  }

  /**
   * ลบไฟล์ใน object storage (ใช้ตอนลบบัญชี) ทำแบบ best effort:
   * ลบไม่สำเร็จจะ log ไว้ ไม่ทำให้การลบบัญชีล้มเหลว เพราะข้อมูลใน DB ถูกลบไปแล้ว
   */
  async deleteUploads(urls: readonly string[]): Promise<void> {
    if (this.mode === 'none' || !this.publicBaseUrl) return;
    const prefix = `${this.publicBaseUrl}/`;
    const keys = urls
      .filter((url) => url.startsWith(prefix))
      .map((url) => url.slice(prefix.length));
    if (this.mode === 'local') {
      for (const key of keys) {
        if (!LOCAL_KEY.test(key)) continue;
        await unlink(join(this.uploadDir, key)).catch(
          (error: NodeJS.ErrnoException) => {
            if (error.code !== 'ENOENT') {
              this.logger.error(`ลบไฟล์ ${key} ไม่สำเร็จ`, error);
            }
          },
        );
      }
      return;
    }
    if (!this.client || !this.bucket) return;
    for (let i = 0; i < keys.length; i += 1000) {
      const batch = keys.slice(i, i + 1000);
      try {
        await this.client.send(
          new DeleteObjectsCommand({
            Bucket: this.bucket,
            Delete: { Objects: batch.map((Key) => ({ Key })), Quiet: true },
          }),
        );
      } catch (error) {
        this.logger.error(
          `ลบไฟล์ ${batch.length} ไฟล์ไม่สำเร็จ ต้องลบเองใน storage`,
          error as Error,
        );
      }
    }
  }

  // ---------- โหมด local ----------

  private sign(key: string, size: number, expires: number): string {
    return createHmac('sha256', this.signingKey)
      .update(`${key}\n${size}\n${expires}`)
      .digest('base64url');
  }

  /** path บนดิสก์ของไฟล์ที่อัปโหลดแล้ว (null ถ้า key ไม่ถูกต้อง) */
  localPath(key: string): string | null {
    if (this.mode !== 'local' || !LOCAL_KEY.test(key)) return null;
    return join(this.uploadDir, key);
  }

  /**
   * รับไฟล์จากลิงก์ที่ /uploads/presign ออกให้ ตรวจลายเซ็น อายุ ขนาด ชนิดไฟล์ และ magic bytes
   * เขียนลงไฟล์ชั่วคราวก่อนแล้วค่อย rename จะได้ไม่มีไฟล์ครึ่งๆ กลางๆ ให้เปิดดู
   */
  async receiveLocalUpload(
    key: string,
    query: { size?: string; exp?: string; sig?: string },
    contentType: string | undefined,
    body: Readable,
  ): Promise<void> {
    if (this.mode !== 'local') {
      throw new ServiceUnavailableException(
        'ไม่ได้เปิดโหมดเก็บไฟล์บนเซิร์ฟเวอร์',
      );
    }
    const match = LOCAL_KEY.exec(key);
    const size = Number(query.size);
    const expires = Number(query.exp);
    if (
      !match ||
      !Number.isInteger(size) ||
      size < 1 ||
      size > 10 * 1024 * 1024 ||
      !Number.isInteger(expires) ||
      !query.sig
    ) {
      throw new BadRequestException('ลิงก์อัปโหลดไม่ถูกต้อง');
    }
    const expected = Buffer.from(this.sign(key, size, expires));
    const actual = Buffer.from(query.sig);
    if (
      expected.length !== actual.length ||
      !timingSafeEqual(expected, actual)
    ) {
      throw new ForbiddenException('ลิงก์อัปโหลดไม่ถูกต้อง');
    }
    if (expires < Math.floor(Date.now() / 1000)) {
      throw new ForbiddenException('ลิงก์อัปโหลดหมดอายุ ลองแนบรูปใหม่');
    }
    const expectedType = CONTENT_TYPES[match[4]];
    if (contentType?.split(';')[0].trim() !== expectedType) {
      throw new BadRequestException('ชนิดไฟล์ไม่ตรงกับที่ขอไว้');
    }

    const target = join(this.uploadDir, key);
    const temp = `${target}.${randomUUID()}.part`;
    await mkdir(dirname(target), { recursive: true });
    let received = 0;
    let head = Buffer.alloc(0);
    const out = createWriteStream(temp, { flags: 'wx' });
    try {
      for await (const chunk of body) {
        const buffer = Buffer.isBuffer(chunk)
          ? chunk
          : Buffer.from(chunk as string);
        received += buffer.length;
        if (received > size) {
          throw new BadRequestException('ไฟล์ใหญ่กว่าที่ขอไว้');
        }
        if (head.length < 12)
          head = Buffer.concat([head, buffer]).subarray(0, 12);
        if (!out.write(buffer)) {
          await new Promise<void>((resolve) => out.once('drain', resolve));
        }
      }
      await new Promise<void>((resolve, reject) => {
        out.end((error?: Error | null) => (error ? reject(error) : resolve()));
      });
      if (received !== size) {
        throw new BadRequestException('ไฟล์ไม่ครบ ลองแนบรูปใหม่');
      }
      if (!looksLikeImage(head, expectedType)) {
        throw new BadRequestException('ไฟล์นี้ไม่ใช่รูปภาพ');
      }
      // เขียนได้ครั้งเดียว: link ล้มถ้ามีไฟล์อยู่แล้ว กันการสลับรูปหลังแนบไปแล้ว (เช่น สลิป)
      await link(temp, target).catch((error: NodeJS.ErrnoException) => {
        if (error.code === 'EEXIST') {
          throw new ConflictException('ไฟล์นี้อัปโหลดไปแล้ว');
        }
        throw error;
      });
      await rm(temp, { force: true });
    } catch (error) {
      out.destroy();
      await rm(temp, { force: true });
      throw error;
    }
  }
}
