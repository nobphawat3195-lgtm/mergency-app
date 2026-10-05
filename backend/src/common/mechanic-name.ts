/** ชื่อช่างที่แสดงให้คนอื่นเห็น: เติม 'ช่าง' นำหน้า ยกเว้นชื่อเล่นที่ขึ้นต้นด้วย 'ช่าง' อยู่แล้ว */
export function mechanicDisplayName(
  nickname: string | null | undefined,
): string {
  const name = (nickname ?? '').trim();
  if (!name) return 'ช่าง';
  return name.startsWith('ช่าง') ? name : `ช่าง${name}`;
}
