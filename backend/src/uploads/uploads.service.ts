import {
  ForbiddenException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'node:crypto';

import { PresignUploadDto } from './dto/presign-upload.dto';

const EXTENSIONS: Record<PresignUploadDto['contentType'], string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

@Injectable()
export class UploadsService {
  private readonly bucket = process.env.S3_BUCKET;
  private readonly publicBaseUrl = process.env.S3_PUBLIC_BASE_URL?.replace(
    /\/$/,
    '',
  );
  private readonly client: S3Client | null;

  constructor() {
    const accessKeyId = process.env.S3_ACCESS_KEY_ID;
    const secretAccessKey = process.env.S3_SECRET_ACCESS_KEY;
    if (!this.bucket || !this.publicBaseUrl || !accessKeyId || !secretAccessKey) {
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

    if (dto.scope === 'PROVIDER_TOOL' && role !== 'PROVIDER') {
      throw new ForbiddenException('บัญชีนี้แนบรูปเครื่องมือช่างไม่ได้');
    }

    const directory = dto.scope === 'ORDER' ? 'orders' : 'provider-tools';
    const key = `${directory}/${userId}/${randomUUID()}.${EXTENSIONS[dto.contentType]}`;
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
}
