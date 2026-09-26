import { stripInternalFields } from './hide-internal-fields.interceptor';

describe('stripInternalFields', () => {
  it('removes commissionRate at any depth and keeps other values', () => {
    const createdAt = new Date('2026-09-25T00:00:00Z');
    const result = stripInternalFields({
      id: 'o1',
      commissionRate: 0.35,
      createdAt,
      payment: { amount: 45000 },
      history: [{ id: 'o2', commissionRate: 0.35, priceFinal: 1000 }],
    });
    expect(result).toEqual({
      id: 'o1',
      createdAt,
      payment: { amount: 45000 },
      history: [{ id: 'o2', priceFinal: 1000 }],
    });
    expect((result as { createdAt: unknown }).createdAt).toBe(createdAt);
  });

  it('passes through primitives and null', () => {
    expect(stripInternalFields(null)).toBeNull();
    expect(stripInternalFields(5)).toBe(5);
    expect(stripInternalFields('x')).toBe('x');
  });
});
