import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { RegisterProviderDto } from './provider.dto';

const base = {
  realName: 'ช่าง ทดสอบ',
  nickname: 'เอ',
  experienceYears: 3,
  baseLat: 13.75,
  baseLng: 100.5,
  openMinute: 0,
  closeMinute: 23 * 60 + 59,
  categoryIds: ['cat-1'],
  vehicleTypeIds: ['vt-1'],
  toolPhotoUrls: [] as string[],
  photoUrl: 'https://example.com/face.jpg',
  vehiclePlate: 'กข 1234',
};

async function errorsFor(input: Record<string, unknown>) {
  const errors = await validate(plainToInstance(RegisterProviderDto, input));
  return errors.map((error) => error.property);
}

describe('RegisterProviderDto', () => {
  it('accepts an application without tool photos', async () => {
    expect(await errorsFor(base)).toEqual([]);
  });

  it('still caps tool photos at 6', async () => {
    expect(
      await errorsFor({ ...base, toolPhotoUrls: Array(7).fill('u') }),
    ).toContain('toolPhotoUrls');
  });

  it('still requires the face photo', async () => {
    const withoutPhoto: Record<string, unknown> = { ...base };
    delete withoutPhoto.photoUrl;
    expect(await errorsFor(withoutPhoto)).toContain('photoUrl');
  });
});
