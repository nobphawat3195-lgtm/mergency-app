import { distanceKm, estimateEtaMinutes } from './geo';

describe('distanceKm', () => {
  it('returns zero for the same coordinate', () => {
    expect(distanceKm(13.7563, 100.5018, 13.7563, 100.5018)).toBe(0);
  });

  it('calculates a plausible Bangkok to Rangsit distance', () => {
    const distance = distanceKm(13.7563, 100.5018, 13.989, 100.618);
    expect(distance).toBeGreaterThan(25);
    expect(distance).toBeLessThan(35);
  });
});

describe('estimateEtaMinutes', () => {
  it('never shows less than 2 minutes', () => {
    expect(estimateEtaMinutes(0)).toBe(2);
  });

  it('assumes winding roads and city traffic', () => {
    // 10 กม. เส้นตรง ≈ 13.5 กม. บนถนน ที่ 30 กม./ชม. ≈ 27 นาที
    expect(estimateEtaMinutes(10)).toBe(27);
  });
});
