import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { mkdtemp, readFile, readdir, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';

import { UploadsService } from './uploads.service';

const JPEG = Buffer.concat([
  Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
  Buffer.alloc(60, 1),
]);

describe('UploadsService local storage', () => {
  let dir: string;
  let service: UploadsService;
  const previous = { ...process.env };

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'fixgo-uploads-'));
    Object.assign(process.env, {
      STORAGE_PROVIDER: 'local',
      UPLOAD_DIR: dir,
      API_DOMAIN: 'api.fixgo.test',
      JWT_SECRET: 'test-secret',
    });
    service = new UploadsService();
  });

  afterEach(async () => {
    process.env = { ...previous };
    await rm(dir, { recursive: true, force: true });
  });

  async function presign(byteLength = JPEG.length) {
    const result = await service.createPresignedUpload('cus_1', 'CUSTOMER', {
      fileName: 'a.jpg',
      contentType: 'image/jpeg',
      byteLength,
      scope: 'ORDER',
    });
    const url = new URL(result.uploadUrl);
    const key = url.pathname.replace('/api/uploads/local/', '');
    const query = Object.fromEntries(url.searchParams) as {
      size: string;
      exp: string;
      sig: string;
    };
    return { result, key, query };
  }

  it('stores a signed upload and serves it under the public URL', async () => {
    const { result, key, query } = await presign();
    expect(
      result.uploadUrl.startsWith(
        'https://api.fixgo.test/api/uploads/local/orders/cus_1/',
      ),
    ).toBe(true);
    expect(result.publicUrl).toBe(
      `https://api.fixgo.test/api/uploads/files/${key}`,
    );

    await service.receiveLocalUpload(
      key,
      query,
      'image/jpeg',
      Readable.from([JPEG]),
    );
    // ลิงก์เดิมใช้ซ้ำเพื่อเขียนทับไม่ได้
    await expect(
      service.receiveLocalUpload(
        key,
        query,
        'image/jpeg',
        Readable.from([JPEG]),
      ),
    ).rejects.toThrow('อัปโหลดไปแล้ว');
    const path = service.localPath(key)!;
    expect(await readFile(path)).toEqual(JPEG);
    // ไม่มีไฟล์ .part ค้าง
    expect((await readdir(join(dir, 'orders/cus_1'))).length).toBe(1);
    // เจ้าของตรวจผ่านเหมือนโหมด S3
    expect(() =>
      service.assertOwnedUploads([result.publicUrl], 'cus_1', 'ORDER'),
    ).not.toThrow();

    await service.deleteUploads([result.publicUrl]);
    await expect(stat(path)).rejects.toThrow();
  });

  it('rejects a tampered signature, size, key or expired link', async () => {
    const { key, query } = await presign();
    const body = () => Readable.from([JPEG]);
    await expect(
      service.receiveLocalUpload(
        key,
        { ...query, sig: query.sig.slice(1) + 'A' },
        'image/jpeg',
        body(),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.receiveLocalUpload(
        key,
        { ...query, size: String(JPEG.length + 1) },
        'image/jpeg',
        body(),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.receiveLocalUpload(
        key.replace('cus_1', 'cus_2'),
        query,
        'image/jpeg',
        body(),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.receiveLocalUpload(`../${key}`, query, 'image/jpeg', body()),
    ).rejects.toBeInstanceOf(BadRequestException);

    jest.useFakeTimers().setSystemTime(Date.now() + 10 * 60 * 1000);
    try {
      await expect(
        service.receiveLocalUpload(key, query, 'image/jpeg', body()),
      ).rejects.toThrow('หมดอายุ');
    } finally {
      jest.useRealTimers();
    }
  });

  it('rejects wrong content, oversize bodies and non-images without leaving files', async () => {
    const { key, query } = await presign();
    await expect(
      service.receiveLocalUpload(
        key,
        query,
        'text/html',
        Readable.from([JPEG]),
      ),
    ).rejects.toThrow('ชนิดไฟล์');
    await expect(
      service.receiveLocalUpload(
        key,
        query,
        'image/jpeg',
        Readable.from([JPEG, Buffer.from('x')]),
      ),
    ).rejects.toThrow('ใหญ่กว่า');
    const html = Buffer.alloc(JPEG.length, 0x3c);
    await expect(
      service.receiveLocalUpload(
        key,
        query,
        'image/jpeg',
        Readable.from([html]),
      ),
    ).rejects.toThrow('ไม่ใช่รูปภาพ');
    await expect(
      service.receiveLocalUpload(
        key,
        query,
        'image/jpeg',
        Readable.from([JPEG.subarray(0, 10)]),
      ),
    ).rejects.toThrow('ไม่ครบ');
    const files = await readdir(join(dir, 'orders/cus_1')).catch(() => []);
    expect(files).toEqual([]);
  });

  it('refuses paths outside the upload directory', () => {
    expect(service.localPath('orders/cus_1/../../etc/passwd')).toBeNull();
    expect(
      service.localPath(
        'secrets/cus_1/3f2b8c1e-9a4d-4e21-8f00-1234567890ab.jpg',
      ),
    ).toBeNull();
  });
});
