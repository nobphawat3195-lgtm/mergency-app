import 'package:fixgo_core/src/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a Bangkok address as road, khwaeng, khet, city', () {
    expect(
      LocationService.formatNominatimAddress({
        'road': 'ถนนราชดำเนินกลาง',
        'quarter': 'แขวงบวรนิเวศ',
        'suburb': 'เขตพระนคร',
        'city': 'กรุงเทพมหานคร',
        'state': 'กรุงเทพมหานคร',
        'postcode': '10200',
        'country': 'ประเทศไทย',
      }),
      'ถนนราชดำเนินกลาง แขวงบวรนิเวศ เขตพระนคร กรุงเทพมหานคร',
    );
  });

  test('formats a provincial address and skips missing parts', () {
    expect(
      LocationService.formatNominatimAddress({
        'village': 'ตำบลศรีภูมิ',
        'county': 'อำเภอเมืองเชียงใหม่',
        'state': 'จังหวัดเชียงใหม่',
      }),
      'ตำบลศรีภูมิ อำเภอเมืองเชียงใหม่ จังหวัดเชียงใหม่',
    );
  });

  test('returns null when there is nothing usable', () {
    expect(LocationService.formatNominatimAddress(null), isNull);
    expect(LocationService.formatNominatimAddress({'country': 'ไทย'}), isNull);
  });
}
