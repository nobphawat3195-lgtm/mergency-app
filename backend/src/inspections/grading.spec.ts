import { allChecklistItems, CHECKLIST } from './checklist';
import {
  gradeInspection,
  isApplicable,
  ItemResultInput,
  missingItems,
  statusFromMeasurement,
  VehicleProfile,
} from './grading';

const petrolAuto: VehicleProfile = {
  powertrain: 'combustion',
  transmission: 'automatic',
};

function allPass(vehicle: VehicleProfile): ItemResultInput[] {
  return allChecklistItems()
    .filter((item) => isApplicable(item.appliesTo, vehicle))
    .map((item) => ({ itemCode: item.code, status: 'PASS' as const }));
}

function withStatus(
  results: ItemResultInput[],
  code: string,
  status: ItemResultInput['status'],
): ItemResultInput[] {
  return results.map((result) =>
    result.itemCode === code ? { ...result, status } : result,
  );
}

describe('checklist', () => {
  it('has unique item codes', () => {
    const codes = allChecklistItems().map((item) => item.code);
    expect(new Set(codes).size).toBe(codes.length);
  });

  it('covers at least 130 points across all sections', () => {
    expect(allChecklistItems().length).toBeGreaterThanOrEqual(130);
    expect(CHECKLIST.every((section) => section.items.length > 0)).toBe(true);
  });
});

describe('statusFromMeasurement', () => {
  it('grades paint thickness (lower is better)', () => {
    const rule = { unit: 'ไมครอน', passMax: 180, attentionMax: 300 };
    expect(statusFromMeasurement(rule, 120)).toBe('PASS');
    expect(statusFromMeasurement(rule, 250)).toBe('ATTENTION');
    expect(statusFromMeasurement(rule, 450)).toBe('FAIL');
  });

  it('grades tread depth (higher is better)', () => {
    const rule = { unit: 'มม.', passMin: 3, attentionMin: 1.6 };
    expect(statusFromMeasurement(rule, 5)).toBe('PASS');
    expect(statusFromMeasurement(rule, 2)).toBe('ATTENTION');
    expect(statusFromMeasurement(rule, 1)).toBe('FAIL');
  });
});

describe('gradeInspection', () => {
  it('recommends a car that passes every item', () => {
    const result = gradeInspection(allPass(petrolAuto), petrolAuto);
    expect(result.score).toBe(100);
    expect(result.grade).toBe('A');
    expect(result.verdict).toBe('RECOMMENDED');
    expect(result.floodSuspected).toBe(false);
  });

  it('never recommends a car with a failed critical item', () => {
    const results = withStatus(allPass(petrolAuto), 'FRM01', 'FAIL');
    const result = gradeInspection(results, petrolAuto);
    expect(result.criticalFailures).toEqual(['FRM01']);
    expect(result.accidentSuspected).toBe(true);
    expect(result.verdict).toBe('NOT_RECOMMENDED');
  });

  it('flags a flood car from two minor flood signs', () => {
    let results = withStatus(allPass(petrolAuto), 'FLD02', 'ATTENTION');
    results = withStatus(results, 'INT17', 'ATTENTION');
    const result = gradeInspection(results, petrolAuto);
    expect(result.floodSuspected).toBe(true);
    expect(result.verdict).toBe('NOT_RECOMMENDED');
  });

  it('derives status from measurements when none is chosen', () => {
    const results = allPass(petrolAuto).map((result) =>
      result.itemCode === 'PNT01'
        ? { itemCode: 'PNT01', measurement: 260 }
        : result,
    );
    const result = gradeInspection(results, petrolAuto);
    expect(result.verdict).toBe('RECOMMENDED');
    const paint = result.sections.find((section) => section.code === 'PNT');
    expect(paint?.attentionCount).toBe(1);
  });

  it('skips EV items for a petrol car and requires them for an EV', () => {
    const ev: VehicleProfile = {
      powertrain: 'electrified',
      transmission: 'automatic',
    };
    expect(missingItems(allPass(petrolAuto), petrolAuto)).toEqual([]);
    expect(missingItems(allPass(petrolAuto), ev)).toContain('EV01');
    expect(missingItems(allPass(ev), ev)).toEqual([]);
  });
});
