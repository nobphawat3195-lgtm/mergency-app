import { mechanicDisplayName } from './mechanic-name';

describe('mechanicDisplayName', () => {
  it('adds the ช่าง prefix once', () => {
    expect(mechanicDisplayName('เอ')).toBe('ช่างเอ');
    expect(mechanicDisplayName('ช่างเอ')).toBe('ช่างเอ');
    expect(mechanicDisplayName(' ช่างเอ ')).toBe('ช่างเอ');
  });

  it('falls back to ช่าง without a nickname', () => {
    expect(mechanicDisplayName(null)).toBe('ช่าง');
    expect(mechanicDisplayName('')).toBe('ช่าง');
  });
});
