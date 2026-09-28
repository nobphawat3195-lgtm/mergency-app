const EARTH_RADIUS_KM = 6371;

const toRad = (deg: number): number => (deg * Math.PI) / 180;

/** ระยะทางเส้นตรงระหว่าง 2 พิกัด (กิโลเมตร) */
export function distanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

/** ถนนจริงอ้อมกว่าเส้นตรงราว 35% ในเมืองไทย */
const ROAD_FACTOR = 1.35;
/** ความเร็วเฉลี่ยของช่างในเมืองรวมรถติด (กม./ชม.) */
const AVERAGE_SPEED_KMH = 30;

/**
 * เวลาเดินทางโดยประมาณจากระยะเส้นตรง (นาที) ใช้แสดง "ช่างจะถึงในอีกราว X นาที"
 * เป็นค่าประมาณ ไม่ได้คิดเส้นทางจริง จึงปัดขึ้นและไม่ต่ำกว่า 2 นาที
 */
export function estimateEtaMinutes(straightLineKm: number): number {
  const minutes = ((straightLineKm * ROAD_FACTOR) / AVERAGE_SPEED_KMH) * 60;
  return Math.max(2, Math.ceil(minutes));
}
