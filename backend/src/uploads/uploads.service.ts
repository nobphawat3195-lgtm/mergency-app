import {
  BadRequestException,
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
import { randomUUID } from 'node:crypto';

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
};

const UUID_FILE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$/;

@Injectable()
export class UploadsService {
  private readonly logger = new Logger(UploadsService.name);
  private readonly bucket = process.env.S3_BUCKET;
  private readonly publicBaseUrl = process.env.S3_PUBLIC_BASE_URL?.replace(
    /\/$/,
    '',
  );
  private readonly client: S3Client | null;

  constructor() {
    const accessKeyId = process.env.S3_ACCESS_KEY_ID;
    const secretAccessKey = process.env.S3_SECRET_ACCESS_KEY;
    if (
      !this.bucket ||
      !this.publicBaseUrl ||
      !accessKeyId ||
      !secretAccessKey
    ) {
      this.client = null;
      return;
    }

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
    if (!this.client || !this.bucket || !this.publicBaseUrl) {
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

    const key = `${DIRECTORIES[dto.scope]}/${userId}/${randomUUID()}.${EXTENSIONS[dto.contentType]}`;
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: dto.contentType,
      ContentLength: dto.byteLength,
      CacheControl: 'public, max-age=31536000, immutable',
    });
    const uploadUrl = await getSignedUrl(this.client, command, {
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
    if (!this.client || !this.bucket || !this.publicBaseUrl) return;
    const prefix = `${this.publicBaseUrl}/`;
    const keys = urls
      .filter((url) => url.startsWith(prefix))
      .map((url) => url.slice(prefix.length));
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
}
