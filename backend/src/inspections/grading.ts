import {
  AppliesTo,
  ChecklistItem,
  CHECKLIST,
  MeasurementRule,
  RiskFlag,
} from './checklist';

export type ItemStatus = 'PASS' | 'ATTENTION' | 'FAIL' | 'NOT_APPLICABLE';
export type Verdict = 'RECOMMENDED' | 'CAUTION' | 'NOT_RECOMMENDED';
export type Powertrain = 'combustion' | 'electrified';
export type Transmission = 'manual' | 'automatic';

export interface ItemResultInput {
  itemCode: string;
  status?: ItemStatus | null;
  measurement?: number | null;
}

export interface VehicleProfile {
  /** รถไฮบริดนับเป็นทั้งเครื่องยนต์และไฟฟ้า */
  powertrain: Powertrain | 'hybrid';
  transmission: Transmission;
}

export interface SectionScore {
  code: string;
  title: string;
  score: number;
  failCount: number;
  attentionCount: number;
}

export interface GradeResult {
  score: number;
  grade: 'A' | 'B' | 'C' | 'D' | 'E';
  verdict: Verdict;
  floodSuspected: boolean;
  accidentSuspected: boolean;
  odometerSuspected: boolean;
  legalIssue: boolean;
  criticalFailures: string[];
  sections: SectionScore[];
}

/** ข้อนี้ต้องตรวจกับรถคันนี้หรือไม่ */
export function isApplicable(
  appliesTo: AppliesTo | undefined,
  vehicle: VehicleProfile,
): boolean {
  switch (appliesTo ?? 'all') {
    case 'all':
      return true;
    case 'combustion':
      return vehicle.powertrain !== 'electrified';
    case 'electrified':
      return vehicle.powertrain !== 'combustion';
    case 'manual':
      return vehicle.transmission === 'manual';
    case 'automatic':
      return vehicle.transmission === 'automatic';
  }
}

/** แปลงค่าที่วัดได้เป็นผลตรวจตามเกณฑ์ของข้อนั้น */
export function statusFromMeasurement(
  rule: MeasurementRule,
  value: number,
): ItemStatus {
  if (rule.passMax !== undefined) {
    if (value <= rule.passMax) return 'PASS';
    if (rule.attentionMax !== undefined && value <= rule.attentionMax) {
      return 'ATTENTION';
    }
    return 'FAIL';
  }
  if (rule.passMin !== undefined) {
    if (value >= rule.passMin) return 'PASS';
    if (rule.attentionMin !== undefined && value >= rule.attentionMin) {
      return 'ATTENTION';
    }
    return 'FAIL';
  }
  return 'PASS';
}

/** ผลตรวจที่ใช้คำนวณจริง: ถ้าช่างกรอกค่าวัดแต่ไม่ได้เลือกผล ให้คำนวณจากเกณฑ์ */
export function resolveStatus(
  item: ChecklistItem,
  input: ItemResultInput | undefined,
): ItemStatus | null {
  if (!input) return null;
  if (input.status) return input.status;
  if (
    item.measurement &&
    input.measurement !== null &&
    input.measurement !== undefined
  ) {
    return statusFromMeasurement(item.measurement, input.measurement);
  }
  return null;
}

/** รายการข้อที่ต้องตอบแต่ยังไม่ได้ตอบ ใช้ตรวจก่อนส่งรายงาน */
export function missingItems(
  results: ItemResultInput[],
  vehicle: VehicleProfile,
): string[] {
  const byCode = new Map(results.map((result) => [result.itemCode, result]));
  const missing: string[] = [];
  for (const section of CHECKLIST) {
    for (const item of section.items) {
      if (!isApplicable(item.appliesTo, vehicle)) continue;
      if (resolveStatus(item, byCode.get(item.code)) === null) {
        missing.push(item.code);
      }
    }
  }
  return missing;
}

const POINTS: Record<Exclude<ItemStatus, 'NOT_APPLICABLE'>, number> = {
  PASS: 1,
  ATTENTION: 0.5,
  FAIL: 0,
};

function gradeFromScore(score: number): GradeResult['grade'] {
  if (score >= 90) return 'A';
  if (score >= 80) return 'B';
  if (score >= 70) return 'C';
  if (score >= 60) return 'D';
  return 'E';
}

/**
 * คำนวณคะแนนและผลสรุปของรายงานตรวจรถ
 *
 * - ข้อสำคัญ (critical) มีน้ำหนัก 3 เท่า
 * - ข้อสำคัญไม่ผ่านแม้ข้อเดียว = ไม่แนะนำให้ซื้อ ไม่ว่าคะแนนรวมจะสูงแค่ไหน
 * - ความเสี่ยงหลักแต่ละด้าน (น้ำท่วม/ชนหนัก/เลขไมล์) ถือว่า "สงสัย" เมื่อ
 *   มีข้อที่เกี่ยวข้องไม่ผ่าน 1 ข้อ หรือควรระวังตั้งแต่ 2 ข้อขึ้นไป
 */
export function gradeInspection(
  results: ItemResultInput[],
  vehicle: VehicleProfile,
): GradeResult {
  const byCode = new Map(results.map((result) => [result.itemCode, result]));
  const flagFails: Record<RiskFlag, number> = {
    flood: 0,
    accident: 0,
    odometer: 0,
    legal: 0,
  };
  const flagAttention: Record<RiskFlag, number> = {
    flood: 0,
    accident: 0,
    odometer: 0,
    legal: 0,
  };
  const criticalFailures: string[] = [];
  const sections: SectionScore[] = [];
  let earned = 0;
  let possible = 0;

  for (const section of CHECKLIST) {
    let sectionEarned = 0;
    let sectionPossible = 0;
    let failCount = 0;
    let attentionCount = 0;

    for (const item of section.items) {
      if (!isApplicable(item.appliesTo, vehicle)) continue;
      const status = resolveStatus(item, byCode.get(item.code));
      if (status === null || status === 'NOT_APPLICABLE') continue;

      const weight = item.critical ? 3 : 1;
      sectionEarned += POINTS[status] * weight;
      sectionPossible += weight;

      if (status === 'FAIL') {
        failCount += 1;
        if (item.critical) criticalFailures.push(item.code);
        for (const flag of item.flags ?? []) flagFails[flag] += 1;
      } else if (status === 'ATTENTION') {
        attentionCount += 1;
        for (const flag of item.flags ?? []) flagAttention[flag] += 1;
      }
    }

    if (sectionPossible > 0) {
      sections.push({
        code: section.code,
        title: section.title,
        score: Math.round((sectionEarned / sectionPossible) * 100),
        failCount,
        attentionCount,
      });
    }
    earned += sectionEarned;
    possible += sectionPossible;
  }

  const suspected = (flag: RiskFlag) =>
    flagFails[flag] >= 1 || flagAttention[flag] >= 2;

  const score = possible === 0 ? 0 : Math.round((earned / possible) * 100);
  const floodSuspected = suspected('flood');
  const accidentSuspected = suspected('accident');
  const odometerSuspected = suspected('odometer');
  const legalIssue = flagFails.legal >= 1;

  let verdict: Verdict;
  if (
    criticalFailures.length > 0 ||
    floodSuspected ||
    legalIssue ||
    score < 60
  ) {
    verdict = 'NOT_RECOMMENDED';
  } else if (accidentSuspected || odometerSuspected || score < 85) {
    verdict = 'CAUTION';
  } else {
    verdict = 'RECOMMENDED';
  }

  return {
    score,
    grade: gradeFromScore(score),
    verdict,
    floodSuspected,
    accidentSuspected,
    odometerSuspected,
    legalIssue,
    criticalFailures,
    sections,
  };
}
