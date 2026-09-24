import { PHOTO_SLOTS, photoProblems } from './photo-slots';

describe('photo slots', () => {
  it('has unique codes and sane limits', () => {
    const codes = PHOTO_SLOTS.map((s) => s.code);
    expect(new Set(codes).size).toBe(codes.length);
    for (const s of PHOTO_SLOTS) {
      expect(s.maxPhotos).toBeGreaterThan(0);
      expect(s.maxPhotos).toBeLessThanOrEqual(20);
    }
  });

  it('includes left and right door slots and a captioned defect slot', () => {
    const labels = PHOTO_SLOTS.map((s) => s.label);
    expect(labels).toEqual(
      expect.arrayContaining(['ประตูหน้าซ้าย', 'ประตูหน้าขวา', 'รูปตำหนิ']),
    );
    expect(PHOTO_SLOTS.find((s) => s.code === 'DEFECTS')?.captionRequired).toBe(
      true,
    );
  });

  it('lists every required slot when nothing is attached', () => {
    const { missingSlots } = photoProblems([]);
    expect(missingSlots).toHaveLength(
      PHOTO_SLOTS.filter((s) => s.required).length,
    );
    expect(missingSlots).not.toContain('รูปตำหนิ');
  });

  it('passes when all required slots have a photo', () => {
    const photos = PHOTO_SLOTS.filter((s) => s.required).map((s) => ({
      slotCode: s.code,
      url: `https://cdn.example.com/${s.code}.jpg`,
    }));
    expect(photoProblems(photos)).toEqual({ missingSlots: [], uncaptioned: 0 });
  });

  it('counts defect photos without a caption', () => {
    const { uncaptioned } = photoProblems([
      { slotCode: 'DEFECTS', url: 'a', caption: 'กันชนหน้าขวา รอยถลอก' },
      { slotCode: 'DEFECTS', url: 'b', caption: '  ' },
      { slotCode: 'DEFECTS', url: 'c' },
    ]);
    expect(uncaptioned).toBe(2);
  });
});
