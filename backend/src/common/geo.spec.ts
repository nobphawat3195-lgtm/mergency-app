import { distanceKm } from './geo';

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
