/**
 * สร้างข้อความ QR พร้อมเพย์ตามมาตรฐาน EMVCo (Thai QR Payment) แบบระบุยอดเงิน
 * แอปธนาคารทุกแห่งในไทยสแกนได้ ไม่ต้องผ่านผู้ให้บริการภายนอก จึงไม่มีค่าธรรมเนียม
 */

const PROMPTPAY_AID = 'A000000677010111';

function field(id: string, value: string): string {
  return `${id}${value.length.toString().padStart(2, '0')}${value}`;
}

/** CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) ตามที่ EMVCo กำหนด */
export function crc16(input: string): string {
  let crc = 0xffff;
  for (const byte of Buffer.from(input, 'utf8')) {
    crc ^= byte << 8;
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** รับเบอร์มือถือ 10 หลัก (0xxxxxxxxx) หรือเลขประจำตัวผู้เสียภาษี/บัตรประชาชน 13 หลัก */
export function normalizePromptPayId(raw: string): {
  type: 'phone' | 'taxId';
  value: string;
} {
  const digits = raw.replace(/[^0-9]/g, '');
  if (/^0[0-9]{9}$/.test(digits)) {
    // 0812345678 -> 0066812345678
    return { type: 'phone', value: `0066${digits.slice(1)}` };
  }
  if (/^[0-9]{13}$/.test(digits)) {
    return { type: 'taxId', value: digits };
  }
  throw new Error(
    'PROMPTPAY_ID ต้องเป็นเบอร์มือถือ 10 หลัก หรือเลขประจำตัว 13 หลัก ที่ผูกพร้อมเพย์ไว้',
  );
}

/** amountSatang: ยอดเงินเป็นสตางค์ QR จะล็อกยอดนี้ ลูกค้าแก้ไม่ได้ */
export function promptPayPayload(
  promptPayId: string,
  amountSatang: number,
): string {
  if (!Number.isInteger(amountSatang) || amountSatang <= 0) {
    throw new Error('ยอดเงินต้องเป็นจำนวนสตางค์ที่มากกว่า 0');
  }
  const id = normalizePromptPayId(promptPayId);
  const account = field(
    '29',
    field('00', PROMPTPAY_AID) +
      field(id.type === 'phone' ? '01' : '02', id.value),
  );
  const body =
    field('00', '01') + // payload format
    field('01', '12') + // dynamic: ใช้ครั้งเดียว มียอดเงิน
    account +
    field('53', '764') + // THB
    field('54', (amountSatang / 100).toFixed(2)) +
    field('58', 'TH') +
    '6304';
  return body + crc16(body);
}
