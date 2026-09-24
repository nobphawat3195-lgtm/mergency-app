import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'booking/booking_flow.dart';

/// รายละเอียดบริการตรวจรถมือสอง/ตรวจรถพิเศษ ก่อนจอง
///
/// ข้อมูลทุกอย่างมาจากระบบ: ราคาจากบริการย่อยในแคตตาล็อก, รายการตรวจจาก checklist
/// ของ backend, เกณฑ์เกรดตรงกับ backend/src/inspections/grading.ts
/// ส่วนข้อมูลของ TRUSTCAR 360 ยังตรวจสอบต้นฉบับไม่ได้ จึงแสดงเป็นสถานะต้นแบบเท่านั้น
class InspectionDetailScreen extends StatefulWidget {
  const InspectionDetailScreen({
    super.key,
    required this.category,
    this.pickupLocation,
  });

  final ServiceCategory? category;
  final LocationResult? pickupLocation;

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

typedef _DetailData = ({
  ServiceCategory category,
  SubService? subService,
  InspectionChecklist checklist,
});

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  Future<_DetailData>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_DetailData> _load() async {
    final api = AppStateScope.of(context).api;
    var category = widget.category;
    if (category == null) {
      final categories = await api.listCategories();
      category = categories.firstWhere(
        (c) => c.iconKey == 'inspection',
        orElse: () => throw ApiException(404, 'ยังไม่มีบริการตรวจรถในระบบ'),
      );
    }
    final results = await Future.wait([
      api.listSubServices(category.id),
      api.getInspectionChecklist(),
    ]);
    final subs = results[0] as List<SubService>;
    return (
      category: category,
      subService: subs.isEmpty ? null : subs.first,
      checklist: results[1] as InspectionChecklist,
    );
  }

  void _book(ServiceCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingFlow(
          initialCategory: category,
          pickupLocation: widget.pickupLocation,
          initialSubServiceKeyword: 'ตรวจ',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตรวจรถมือสอง')),
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(FixGoSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error is ApiException
                          ? error.message
                          : 'โหลดรายละเอียดไม่สำเร็จ',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: FixGoSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final groups = data.checklist.displayGroups;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(FixGoSpacing.md),
                  children: [
                    _SummaryCard(
                      subService: data.subService,
                      totalItems: data.checklist.totalItems,
                      groupCount: groups.length,
                    ),
                    const SizedBox(height: FixGoSpacing.lg),
                    const _Heading('ตรวจอะไรบ้าง'),
                    const SizedBox(height: FixGoSpacing.sm),
                    for (final (index, group) in groups.indexed) ...[
                      _GroupTile(index: index + 1, group: group),
                      const SizedBox(height: FixGoSpacing.sm),
                    ],
                    _InfoCard(
                      number: groups.length + 1,
                      icon: Icons.photo_camera_outlined,
                      title: 'ภาพหลักฐาน',
                      lines: [
                        if (data.checklist.photoSlots.isNotEmpty)
                          'ถ่ายตามหัวข้อบังคับ ${data.checklist.photoSlots.where((slot) => slot.required).length} ช่อง: '
                              '${data.checklist.photoGroups.join(', ')}',
                        if (data.checklist.photoSlots
                            .any((slot) => slot.captionRequired))
                          'รูปตำหนิทุกรูปต้องระบุตำแหน่งและอาการ เช่น "กันชนหน้าขวา รอยถลอก"',
                        'มี ${data.checklist.photoRequiredItems} รายการที่ช่างต้องแนบรูปทุกครั้งเมื่อพบว่า "ไม่ผ่าน" หรือ "ควรระวัง"',
                        'ระบบไม่ยอมให้ส่งรายงานถ้าข้อที่พบปัญหายังไม่มีรูป',
                        'ค่าวัด เช่น ความหนาสีและความลึกดอกยาง ระบบตัดสินผลให้อัตโนมัติ ช่างเปลี่ยนผลเองไม่ได้',
                      ],
                    ),
                    const SizedBox(height: FixGoSpacing.sm),
                    _InfoCard(
                      number: groups.length + 2,
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'รายงานสรุป',
                      lines: const [
                        'คะแนนเต็ม 100 ข้อสำคัญมีน้ำหนัก 3 เท่า เกรด A ≥ 90, B ≥ 80, C ≥ 70, D ≥ 60, ต่ำกว่านั้น E',
                        '"ไม่แนะนำให้ซื้อ" ทันทีถ้าข้อสำคัญไม่ผ่าน สงสัยรถจมน้ำ มีปัญหาเอกสาร หรือคะแนนต่ำกว่า 60',
                        '"ควรระวัง" ถ้าสงสัยชนหนักหรือกรอไมล์ หรือคะแนนต่ำกว่า 85',
                        'ลูกค้าเห็นผลรายข้อหลังช่างส่งรายงานแล้วเท่านั้น และช่างปิดงานไม่ได้จนกว่าจะส่งรายงาน',
                      ],
                    ),
                    const SizedBox(height: FixGoSpacing.lg),
                    const _PrototypeNotice(),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ElevatedButton.icon(
                    onPressed: () => _book(data.category),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('จองนัดตรวจรถ'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.subService,
    required this.totalItems,
    required this.groupCount,
  });

  final SubService? subService;
  final int totalItems;
  final int groupCount;

  @override
  Widget build(BuildContext context) {
    final price = subService?.basePrice;
    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      decoration: BoxDecoration(
        gradient: fixGoBrandGradient,
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(categoryIconAsset('inspection'), height: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  subService?.name ?? 'ตรวจรถมือสองนอกสถานที่',
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (price != null)
                _Pill(
                  label:
                      '฿${formatThousands(price ~/ 100)} ราคาเดียวทุกประเภทรถ',
                  strong: true,
                ),
              _Pill(label: 'ตรวจ $totalItems รายการ'),
              _Pill(label: '$groupCount หมวด'),
              const _Pill(label: 'ใช้เวลาประมาณ 60–90 นาที'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'ช่างไปตรวจที่ตำแหน่งรถตามนัด ก่อนคุณตัดสินใจซื้อ '
            'รายงานพร้อมรูปหลักฐานส่งเข้าแอปทันทีที่ตรวจเสร็จ',
            style: TextStyle(
                fontSize: 13.5, height: 1.45, color: Color(0xFFDDF3E7)),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: strong ? FixGoColors.lime : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(FixGoRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          color: strong ? FixGoColors.navy : Colors.white,
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: FixGoColors.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: FixGoColors.accent,
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.index, required this.group});

  final int index;
  final InspectionDisplayGroup group;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: _NumberBadge(index),
        title: Text(
          group.title,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${group.items.length} รายการ'
          '${group.criticalCount > 0 ? ' · ข้อสำคัญ ${group.criticalCount}' : ''}',
          style:
              const TextStyle(fontSize: 12.5, color: FixGoColors.textSecondary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(group.description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final item in group.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.critical
                        ? Icons.priority_high_rounded
                        : Icons.check_rounded,
                    size: 18,
                    color: item.critical ? FixGoColors.error : FixGoColors.jade,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                    ),
                  ),
                  if (item.appliesTo != 'all')
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text(
                        'เฉพาะบางรุ่น',
                        style: TextStyle(
                            fontSize: 11, color: FixGoColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final int number;
  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _NumberBadge(number),
                const SizedBox(width: 12),
                Icon(icon, color: FixGoColors.accent),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $line',
                    style: const TextStyle(fontSize: 13.5, height: 1.45)),
              ),
          ],
        ),
      ),
    );
  }
}

/// ต้นฉบับ TRUSTCAR 360 เปิดตรวจสอบจากระบบไม่ได้ ห้ามแสดงราคา/พื้นที่/เงื่อนไขของต้นฉบับเป็นข้อมูลจริง
class _PrototypeNotice extends StatelessWidget {
  const _PrototypeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        border: Border.all(color: const Color(0xFFF1D9A6)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined,
                  color: FixGoColors.warning, size: 20),
              SizedBox(width: 6),
              Text(
                'ตรวจรถพิเศษ TRUSTCAR 360 · ต้นแบบ',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: FixGoColors.warning,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            'แพ็กเกจตรวจพิเศษนี้ยังเป็นต้นแบบ ราคา พื้นที่ให้บริการ และเงื่อนไข '
            'ยังรอยืนยันจากต้นฉบับ จึงยังไม่เปิดจอง ราคาและรายการตรวจด้านบนคือบริการ '
            'FixGo ที่เปิดใช้งานจริงในระบบ',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
          SizedBox(height: 6),
          Text(
            'พื้นที่ให้บริการ: ขึ้นกับว่ามีช่างตรวจรถออนไลน์ใกล้ตำแหน่งนัด ระบบจะแจ้งถ้ายังไม่มีช่างรับงาน',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}
