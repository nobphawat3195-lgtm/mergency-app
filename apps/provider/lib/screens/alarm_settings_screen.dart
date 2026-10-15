import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../native_offer_alerts.dart';

/// รายการตั้งค่าให้แจ้งเตือนงานใหม่ดังแบบนาฬิกาปลุกตอนล็อกจอ (แอป Android)
/// และปุ่มทดสอบเสียงทั้งในแอปและแบบล็อกจอ
class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen>
    with WidgetsBindingObserver {
  AlarmReadiness? _readiness;

  NativeOfferAlerts get _alerts => ProviderAppScope.of(context).nativeAlerts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readiness == null) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// กลับมาจากหน้าตั้งค่าของระบบ: ตรวจใหม่ว่าอนุญาตแล้วหรือยัง
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final readiness = await _alerts.readiness();
    if (mounted) setState(() => _readiness = readiness);
  }

  Future<void> _open(AlarmSetting setting) async {
    await _alerts.openSetting(setting);
    await _load();
  }

  void _testInApp() {
    unawaited(ProviderAppScope.of(context).offerAlarm.test());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'กำลังเล่นเสียงปลุกและเสียงพูด ถ้าไม่ได้ยิน ให้เพิ่มเสียงเครื่องหรือปิดโหมดเงียบ',
        ),
      ),
    );
  }

  void _testLocked() {
    unawaited(_alerts.showTest());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'กดปุ่มล็อกจอตอนนี้ ภายใน 5 วินาทีจะมีแจ้งเตือนงานทดสอบเด้งขึ้น'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _readiness;
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าเสียงเตือนงาน')),
      body: ListView(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        children: [
          const Text(
            'ทำครบทุกข้อเพื่อให้งานใหม่ดังแบบนาฬิกาปลุก เด้งเต็มจอแม้ล็อกจอ จนกว่าจะกดรับหรือปฏิเสธ',
            style: TextStyle(color: FixGoColors.textSecondary),
          ),
          const SizedBox(height: FixGoSpacing.md),
          if (readiness == null)
            const LoadingStateView()
          else ...[
            if (readiness.notifications != null)
              _CheckTile(
                done: readiness.notifications!,
                title: 'อนุญาตการแจ้งเตือน',
                body: 'ไม่อนุญาต = งานเข้าแล้วไม่มีอะไรเด้งเลย',
                onFix: () => _open(AlarmSetting.notifications),
              ),
            if (readiness.fullScreen != null)
              _CheckTile(
                done: readiness.fullScreen!,
                title: 'แสดงเต็มจอตอนล็อกจอ',
                body:
                    'งานใหม่เด้งขึ้นเต็มจอเหมือนสายเรียกเข้า (Android 14 ขึ้นไปต้องเปิดเอง)',
                onFix: () => _open(AlarmSetting.fullScreen),
              ),
            if (readiness.batteryUnrestricted != null)
              _CheckTile(
                done: readiness.batteryUnrestricted!,
                title: 'ไม่จำกัดแบตเตอรี่ให้แอปนี้',
                body: 'โหมดประหยัดแบตอาจหยุดแอป ทำให้แจ้งเตือนมาช้าหรือไม่มา',
                onFix: () => _open(AlarmSetting.battery),
              ),
            if (readiness.notifications != null)
              _CheckTile(
                done: null,
                title: 'แสดงป๊อปอัป / แสดงบนหน้าจอล็อก',
                body:
                    'บางยี่ห้อ (เช่น Xiaomi, OPPO, vivo) ต้องเปิดเพิ่มในหน้าข้อมูลแอป > การแจ้งเตือน หรือ สิทธิ์อื่นๆ',
                onFix: () => _open(AlarmSetting.appDetails),
              ),
          ],
          const SizedBox(height: FixGoSpacing.lg),
          FilledButton.icon(
            onPressed: _testInApp,
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text('ทดสอบเสียงเตือนงาน'),
          ),
          if (readiness?.notifications != null) ...[
            const SizedBox(height: FixGoSpacing.sm),
            OutlinedButton.icon(
              onPressed: _testLocked,
              icon: const Icon(Icons.lock_clock_outlined),
              label: const Text('ทดสอบตอนล็อกจอ (เด้งใน 5 วินาที)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.done,
    required this.title,
    required this.body,
    required this.onFix,
  });

  /// null = ตรวจจากในแอปไม่ได้ ให้ช่างเปิดดูเอง
  final bool? done;
  final String title;
  final String body;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final done = this.done;
    return Card(
      margin: const EdgeInsets.only(bottom: FixGoSpacing.sm),
      child: ListTile(
        leading: Icon(
          done == true
              ? Icons.check_circle
              : done == false
                  ? Icons.error_outline
                  : Icons.help_outline,
          color: done == true
              ? FixGoColors.success
              : done == false
                  ? FixGoColors.error
                  : FixGoColors.textSecondary,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(body),
        trailing: done == true
            ? const Text('เรียบร้อย',
                style: TextStyle(color: FixGoColors.success))
            : TextButton(onPressed: onFix, child: const Text('ตั้งค่า')),
      ),
    );
  }
}
