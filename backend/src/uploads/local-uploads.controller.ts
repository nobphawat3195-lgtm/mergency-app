import {
  Controller,
  Get,
  Headers,
  HttpCode,
  NotFoundException,
  Param,
  Put,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { access } from 'node:fs/promises';

import { CONTENT_TYPES, UploadsService } from './uploads.service';

/**
 * เก็บรูปบนดิสก์ของเซิร์ฟเวอร์ (STORAGE_PROVIDER=local) แทน R2/S3
 *
 * - PUT ไม่ใช้ JWT: สิทธิ์มาจากลายเซ็นในลิงก์ที่ /uploads/presign ออกให้ (อายุ 5 นาที ผูกกับ key และขนาดไฟล์)
 * - GET เปิดสาธารณะเหมือน bucket: ชื่อไฟล์เป็น UUID สุ่ม คนที่ไม่มีลิงก์เดาไม่ได้
 */
@Controller('uploads')
export class LocalUploadsController {
  constructor(private readonly uploads: UploadsService) {}

  @Put('local/:dir/:owner/:file')
  @HttpCode(200)
  async upload(
    @Param('dir') dir: string,
    @Param('owner') owner: string,
    @Param('file') file: string,
    @Query() query: { size?: string; exp?: string; sig?: string },
    @Headers('content-type') contentType: string | undefined,
    @Req() request: Request,
  ) {
    await this.uploads.receiveLocalUpload(
      `${dir}/${owner}/${file}`,
      query,
      contentType,
      request,
    );
    return { ok: true };
  }

  @Get('files/:dir/:owner/:file')
  async file(
    @Param('dir') dir: string,
    @Param('owner') owner: string,
    @Param('file') file: string,
    @Res() response: Response,
  ) {
    const path = this.uploads.localPath(`${dir}/${owner}/${file}`);
    if (!path) throw new NotFoundException();
    try {
      await access(path);
    } catch {
      throw new NotFoundException();
    }
    const extension = file.slice(file.lastIndexOf('.') + 1);
    response.sendFile(path, {
      headers: {
        'Content-Type': CONTENT_TYPES[extension],
        'Cache-Control': 'public, max-age=31536000, immutable',
        'X-Content-Type-Options': 'nosniff',
        'Content-Security-Policy': "default-src 'none'",
      },
    });
  }
}
