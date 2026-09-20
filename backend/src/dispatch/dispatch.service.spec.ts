import { bangkokMinuteOfDay, isWithinWorkingHours } from './dispatch.service';

describe('dispatch time helpers', () => {
  it('converts UTC to Bangkok time', () => {
    expect(bangkokMinuteOfDay(new Date('2026-09-20T00:30:00.000Z'))).toBe(
      7 * 60 + 30,
    );
  });

  it('handles a normal working window inclusively', () => {
    expect(isWithinWorkingHours(8 * 60, 18 * 60, 12 * 60)).toBe(true);
    expect(isWithinWorkingHours(8 * 60, 18 * 60, 7 * 60 + 59)).toBe(false);
  });

  it('handles a working window that crosses midnight', () => {
    expect(isWithinWorkingHours(20 * 60, 6 * 60, 23 * 60)).toBe(true);
    expect(isWithinWorkingHours(20 * 60, 6 * 60, 3 * 60)).toBe(true);
    expect(isWithinWorkingHours(20 * 60, 6 * 60, 12 * 60)).toBe(false);
  });
});
