/** แปลงสตางค์เป็นข้อความเงินบาท เช่น 199000 -> "฿1,990" (มีเศษสตางค์จะแสดง 2 ตำแหน่ง) */
export function formatBaht(satang: number): string {
  const baht = satang / 100;
  const hasFraction = satang % 100 !== 0;
  return `฿${baht.toLocaleString('en-US', {
    minimumFractionDigits: hasFraction ? 2 : 0,
    maximumFractionDigits: 2,
  })}`;
}
