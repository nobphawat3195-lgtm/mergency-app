import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatRelativeMinutes', () {
    final now = DateTime.utc(2026, 9, 28, 10);
    expect(
      formatRelativeMinutes(now.subtract(const Duration(seconds: 20)),
          now: now),
      'เมื่อสักครู่',
    );
    expect(
      formatRelativeMinutes(now.subtract(const Duration(minutes: 3)), now: now),
      '3 นาทีที่แล้ว',
    );
    expect(
      formatRelativeMinutes(now.subtract(const Duration(minutes: 125)),
          now: now),
      '2 ชม.ที่แล้ว',
    );
  });

  test('ProviderSummary reads the trust card and live position', () {
    final provider = ProviderSummary.fromJson({
      'id': 'p1',
      'realName': 'สมชาย ใจดี',
      'nickname': 'ชาย',
      'phone': '0811111111',
      'ratingAvg': 4.8,
      'ratingCount': 25,
      'experienceYears': 8,
      'photoUrl': null,
      'vehicleDesc': 'กระบะสีขาว',
      'vehiclePlate': 'กข 1234',
      'verified': true,
      'completedJobs': 31,
      'currentLat': 13.8,
      'currentLng': 100.55,
      'locationUpdatedAt': '2026-09-28T10:00:00.000Z',
      'distanceKm': 5.6,
      'etaMinutes': 16,
    });
    expect(provider.verified, isTrue);
    expect(provider.completedJobs, 31);
    expect(provider.hasLivePosition, isTrue);
    expect(provider.etaMinutes, 16);
  });

  test('ProviderSummary tolerates the older response without card fields', () {
    final provider = ProviderSummary.fromJson({
      'id': 'p1',
      'realName': 'สมชาย ใจดี',
      'nickname': 'ชาย',
      'phone': '0811111111',
      'ratingAvg': 0,
    });
    expect(provider.hasLivePosition, isFalse);
    expect(provider.verified, isFalse);
  });
}
