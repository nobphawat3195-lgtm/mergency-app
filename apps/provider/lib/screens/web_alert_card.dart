import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../web_alerts.dart';

/// การ์ดในหน้าหลักของเว็บแอปช่าง: ชวนติดตั้งลงหน้าจอหลักและเปิดการแจ้งเตือน
/// เว็บในแท็บเตือนได้เฉพาะตอนเปิดหน้าอยู่ ติดตั้งแล้วถึงจะเด้งเตือนตอนล็อกจอได้
class WebAlertCard extends StatelessWidget {
  const WebAlertCard({
    super.key,
    required this.status,
    required this.isIos,
    required this.canAskPermission,
    required this.busy,
    required this.onEnable,
    required this.onHide,
  });

  final WebAlertStatus status;
  final bool isIos;

  /// เบราว์เซอร์นี้ขอสิทธิ์แจ้งเตือนได้เลยแม้ยังไม่ติดตั้ง (Android Chrome)
  final bool canAskPermission;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final (title, body, steps) = switch (status) {
      WebAlertStatus.install => (
          'ติดตั้งแอปลงหน้าจอหลักเพื่อให้เตือนงานดังขึ้น',
          'ติดตั้งแล้วงานเข้าจะเด้งเตือนแม้ล็อกจอหรือปิดหน้านี้',
          isIos
              ? const [
                  'แตะปุ่มแชร์ (สี่เหลี่ยมมีลูกศรชี้ขึ้น) ใน Safari',
                  'เลือก "เพิ่มไปยังหน้าจอโฮม"',
                  'เปิดแอปจากไอคอน FixGo Fixer แล้วกด "เปิดการแจ้งเตือน"',
                ]
              : const [
                  'แตะเมนูจุดสามจุด มุมขวาบนของ Chrome',
                  'เลือก "ติดตั้งแอป" หรือ "เพิ่มลงในหน้าจอหลัก"',
                  'เปิดแอปจากไอคอน FixGo Fixer',
                ],
        ),
      WebAlertStatus.askPermission => (
          'เปิดการแจ้งเตือนงานใหม่',
          'งานเข้าเมื่อไหร่ โทรศัพท์จะเด้งเตือนแม้ล็อกจอหรือปิดหน้านี้ไปแล้ว',
          const <String>[],
        ),
      WebAlertStatus.blocked => (
          'การแจ้งเตือนถูกปิดอยู่',
          isIos
              ? 'เปิดได้ที่ การตั้งค่า > การแจ้งเตือน > FixGo Fixer แล้วเปิด "อนุญาตการแจ้งเตือน"'
              : 'แตะรูปแม่กุญแจข้างช่องที่อยู่เว็บ (หรือ ตั้งค่าแอป > การแจ้งเตือน) แล้วอนุญาตการแจ้งเตือน',
          const <String>[],
        ),
      WebAlertStatus.ready => ('', '', const <String>[]),
    };
    final showEnable = status == WebAlertStatus.askPermission ||
        (status == WebAlertStatus.install && canAskPermission);

    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      decoration: BoxDecoration(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        border: Border.all(
          color: status == WebAlertStatus.blocked
              ? FixGoColors.warning
              : FixGoColors.jade,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                status == WebAlertStatus.install
                    ? Icons.add_to_home_screen
                    : status == WebAlertStatus.blocked
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined,
                color: status == WebAlertStatus.blocked
                    ? FixGoColors.warning
                    : FixGoColors.accent,
              ),
              const SizedBox(width: FixGoSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: FixGoColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: FixGoColors.textSecondary,
            ),
          ),
          for (final (index, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${index + 1}. $step',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(height: FixGoSpacing.sm),
          Row(
            children: [
              if (showEnable)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onEnable,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('เปิดการแจ้งเตือน'),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: FixGoSpacing.sm),
              TextButton(onPressed: onHide, child: const Text('ไว้ทีหลัง')),
            ],
          ),
        ],
      ),
    );
  }
}
