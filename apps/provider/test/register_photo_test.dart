import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyCatalogApi extends FixGoApiClient {
  _EmptyCatalogApi() : super(baseUrl: 'https://api.example.com');
  @override
  Future<List<ServiceCategory>> listCategories() async => [];
  @override
  Future<List<VehicleType>> listVehicleTypes() async => [];
}

Future<ProviderAppState> _pumpRegister(WidgetTester tester) async {
  // จอสูงพอให้ทั้งฟอร์มอยู่ในหน้าเดียว (ListView สร้างเฉพาะส่วนที่เห็น)
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = ProviderAppState(api: _EmptyCatalogApi());
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ProviderAppScope(
      state: state,
      child: const MaterialApp(home: RegisterScreen()),
    ),
  );
  // แคตตาล็อกว่างจะแสดงวงหมุนค้าง จึงใช้ pump แทน pumpAndSettle
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

void main() {
  testWidgets('ส่งใบสมัครโดยไม่มีรูปหน้าตรง ชี้กลับไปที่วงกลมรูปโปรไฟล์',
      (tester) async {
    await _pumpRegister(tester);

    Future<void> fill(String label, String value) => tester.enterText(
          find.widgetWithText(TextFormField, label),
          value,
        );
    await fill('ชื่อจริง-นามสกุล', 'ช่าง ทดสอบ');
    await fill('ชื่อเล่น', 'เอ');
    await fill('ประสบการณ์ด้านรถยนต์ (ปี)', '5');
    await fill('ทะเบียนรถ', 'กข 1234');

    // ส่วนรูปเครื่องมือบอกชัดว่าไม่บังคับ และรูปหน้าอยู่คนละช่อง
    expect(find.text('รูปเครื่องมือช่าง (ไม่บังคับ)'), findsOneWidget);
    expect(find.text('รูปหน้าของคุณให้ใส่ที่วงกลมด้านบนสุด'), findsOneWidget);

    await tester.tap(find.text('ส่งใบสมัคร'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text(
        'กรุณาใส่รูปหน้าตรงที่วงกลมด้านบนสุด (รูปเครื่องมือใช้แทนไม่ได้)',
      ),
      findsOneWidget,
    );
    final label = tester.widget<Text>(
      find.text('แตะเพื่อใส่รูปหน้าตรง (บังคับ)'),
    );
    expect(label.style?.color, FixGoColors.error);
  });

  testWidgets('เวลารับงานเลือกได้ด้วยปุ่มเดียว ค่าเริ่มต้น 24 ชั่วโมง',
      (tester) async {
    await _pumpRegister(tester);

    final allDay = find.widgetWithText(ChoiceChip, '24 ชั่วโมง');
    expect(tester.widget<ChoiceChip>(allDay).selected, true);
    // ไม่ต้องตั้งเวลาเองถ้าไม่ได้เลือก "กำหนดเอง"
    expect(find.text('เปิด'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'กำหนดเอง'));
    await tester.pump();
    expect(find.text('เปิด'), findsOneWidget);
    expect(find.text('ปิด'), findsOneWidget);
  });

  testWidgets('ปุ่มปักหมุดบอกชัดว่าใช้ตำแหน่งปัจจุบัน', (tester) async {
    await _pumpRegister(tester);
    expect(find.text('ยังไม่ได้ปักหมุด'), findsOneWidget);
    expect(find.text('ใช้ตำแหน่งปัจจุบัน'), findsOneWidget);
    expect(find.text('ดูบนแผนที่'), findsNothing);
  });

  testWidgets('ออกจากระบบจากหน้าสมัครเพื่อใช้บัญชีอื่นได้', (tester) async {
    final state = await _pumpRegister(tester);
    state.api.accessToken = 'header.payload.signature';

    await tester.tap(find.text('ออกจากระบบ / ใช้บัญชีอื่น'));
    await tester.pump(const Duration(milliseconds: 300));
    // ยืนยันก่อน เพราะข้อมูลที่กรอกไว้จะหาย
    expect(find.text('ออกจากระบบ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'ออกจากระบบ'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.isSignedIn, false);
  });
}
