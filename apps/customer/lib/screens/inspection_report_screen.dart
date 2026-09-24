import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';

/// รายงานตรวจรถมือสองสำหรับลูกค้า
///
/// เรียงข้อมูลตามสิ่งที่ผู้ซื้ออยากรู้ก่อน: ควรซื้อไหม → เสี่ยงน้ำท่วม/ชนหนัก/ไมล์ไหม
/// → จุดที่พบปัญหาพร้อมรูป → คะแนนรายหมวด → ผลตรวจครบทุกข้อ
class InspectionReportScreen extends StatefulWidget {
  const InspectionReportScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<InspectionReportScreen> createState() => _InspectionReportScreenState();
}

class _InspectionReportScreenState extends State<InspectionReportScreen> {
  Future<(InspectionChecklist, InspectionReport)>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<(InspectionChecklist, InspectionReport)> _load() async {
    final api = AppStateScope.of(context).api;
    final results = await Future.wait([
      api.getInspectionChecklist(),
      api.getInspection(widget.orderId),
    ]);
    return (
      results[0] as InspectionChecklist,
      results[1] as InspectionReport,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('รายงานตรวจรถ')),
      body: FutureBuilder<(InspectionChecklist, InspectionReport)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error is ApiException
                    ? (snapshot.error as ApiException).message
                    : 'โหลดรายงานไม่สำเร็จ',
                style: const TextStyle(color: FixGoColors.error),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (checklist, report) = snapshot.data!;
          if (!report.isSubmitted) {
            return _PendingView(report: report);
          }
          return _ReportView(checklist: checklist, report: report);
        },
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({required this.report});

  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(categoryIconAsset('inspection'), height: 120),
            const SizedBox(height: FixGoSpacing.md),
            Text(
              report.vehicleTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            const Text(
              'ช่างกำลังตรวจรถ รายงานจะแสดงที่นี่ทันทีที่ตรวจครบ 134 จุด',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.checklist, required this.report});

  final InspectionChecklist checklist;
  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    final byCode = {for (final item in report.items) item.itemCode: item};
    final issues =
        <(ChecklistItem, InspectionItemResult, InspectionItemStatus)>[];
    for (final section in checklist.sections) {
      for (final item in section.items) {
        final result = byCode[item.code];
        final status = result?.effectiveStatus(item);
        if (result != null &&
            (status == InspectionItemStatus.fail ||
                status == InspectionItemStatus.attention)) {
          issues.add((item, result, status!));
        }
      }
    }
    // ข้อไม่ผ่านขึ้นก่อน แล้วค่อยข้อควรระวัง
    issues.sort((a, b) => a.$3.index.compareTo(b.$3.index) * -1);

    return ListView(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      children: [
        _VerdictCard(report: report),
        const SizedBox(height: FixGoSpacing.md),
        _RiskRow(report: report),
        const SizedBox(height: FixGoSpacing.md),
        _VehicleCard(report: report),
        if (report.summary != null && report.summary!.trim().isNotEmpty) ...[
          const SizedBox(height: FixGoSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(FixGoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ความเห็นช่าง',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: FixGoSpacing.xs),
                  Text(report.summary!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: FixGoSpacing.lg),
        Text(
          issues.isEmpty
              ? 'ไม่พบจุดที่ต้องระวัง'
              : 'จุดที่พบ ${issues.length} รายการ',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: FixGoSpacing.sm),
        for (final (item, result, status) in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: FixGoSpacing.sm),
            child: _IssueCard(item: item, result: result, status: status),
          ),
        const SizedBox(height: FixGoSpacing.md),
        const Text(
          'ผลตรวจรายหมวด',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: FixGoSpacing.sm),
        for (final section in checklist.sections)
          _SectionResult(
            section: section,
            report: report,
            byCode: byCode,
          ),
        const SizedBox(height: FixGoSpacing.md),
        Text(
          'รายงานนี้เป็นผลตรวจสภาพ ณ วันที่ ${formatThaiDateTime(report.submittedAt!)} '
          'ด้วยสายตาและเครื่องมือโดยไม่ถอดชิ้นส่วน ไม่ใช่การรับประกันสภาพรถ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.report});

  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    final verdict = report.verdict ?? InspectionVerdict.caution;
    final color = switch (verdict) {
      InspectionVerdict.recommended => FixGoColors.success,
      InspectionVerdict.caution => FixGoColors.warning,
      InspectionVerdict.notRecommended => FixGoColors.error,
    };
    final score = report.score ?? 0;

    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A3242), FixGoColors.navy],
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            height: 96,
            width: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 9,
                  backgroundColor: Colors.white12,
                  color: color,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        report.grade ?? '-',
                        style: const TextStyle(
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '$score/100',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFD5DAE3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: FixGoSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(FixGoRadius.pill),
                  ),
                  child: Text(
                    inspectionVerdictLabel(verdict),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: FixGoSpacing.sm),
                Text(
                  report.vehicleTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (report.mileageKm != null)
                  Text(
                    'เลขไมล์ ${formatThousands(report.mileageKm!)} กม.',
                    style: const TextStyle(color: Color(0xFFD5DAE3)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.report});

  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    final risks = [
      (Icons.water_drop_outlined, 'รถจมน้ำ', report.floodSuspected),
      (Icons.car_crash_outlined, 'ชนหนัก', report.accidentSuspected),
      (Icons.speed_outlined, 'กรอไมล์', report.odometerSuspected),
      (Icons.description_outlined, 'เอกสาร', report.legalIssue),
    ];
    return Row(
      children: [
        for (final (icon, label, suspected) in risks)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: FixGoSpacing.sm),
              decoration: BoxDecoration(
                color: (suspected ? FixGoColors.error : FixGoColors.success)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(FixGoRadius.md),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    color: suspected ? FixGoColors.error : FixGoColors.success,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    suspected ? 'พบร่องรอย' : 'ไม่พบ',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          suspected ? FixGoColors.error : FixGoColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.report});

  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      (
        'ทะเบียน',
        [report.plateNo, report.plateProvince].whereType<String>().join(' ')
      ),
      ('เลขตัวถัง', report.vin),
      ('เลขเครื่อง', report.engineNo),
      ('สี', report.color),
      (
        'ระบบขับเคลื่อน',
        switch (report.powertrain) {
          'electrified' => 'ไฟฟ้า (EV)',
          'hybrid' => 'ไฮบริด',
          'combustion' => 'เครื่องยนต์',
          _ => null,
        },
      ),
      (
        'เกียร์',
        switch (report.transmission) {
          'manual' => 'ธรรมดา',
          'automatic' => 'อัตโนมัติ',
          _ => null,
        },
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          children: [
            for (final (label, value) in rows)
              if (value != null && value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.item,
    required this.result,
    required this.status,
  });

  final ChecklistItem item;
  final InspectionItemResult result;
  final InspectionItemStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status == InspectionItemStatus.fail
        ? FixGoColors.error
        : FixGoColors.warning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  status == InspectionItemStatus.fail
                      ? Icons.cancel
                      : Icons.error_outline,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: FixGoSpacing.sm),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  inspectionItemStatusLabel(status),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (result.measurement != null && item.measurement != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Text(
                  'วัดได้ ${result.measurement} ${item.measurement!.unit}',
                ),
              ),
            if (result.note != null && result.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Text(result.note!),
              ),
            if (result.photoUrls.isNotEmpty) ...[
              const SizedBox(height: FixGoSpacing.sm),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: result.photoUrls.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: FixGoSpacing.sm),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(FixGoRadius.sm),
                    child: GestureDetector(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(
                          child: InteractiveViewer(
                            child: Image.network(result.photoUrls[index]),
                          ),
                        ),
                      ),
                      child: Image.network(
                        result.photoUrls[index],
                        width: 110,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionResult extends StatelessWidget {
  const _SectionResult({
    required this.section,
    required this.report,
    required this.byCode,
  });

  final ChecklistSection section;
  final InspectionReport report;
  final Map<String, InspectionItemResult> byCode;

  @override
  Widget build(BuildContext context) {
    final items = section.items
        .where((item) => item.appliesToVehicle(
              powertrain: report.powertrain,
              transmission: report.transmission,
            ))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    var earned = 0.0;
    var possible = 0.0;
    for (final item in items) {
      final status = byCode[item.code]?.effectiveStatus(item);
      if (status == null || status == InspectionItemStatus.notApplicable) {
        continue;
      }
      final weight = item.critical ? 3.0 : 1.0;
      possible += weight;
      earned += switch (status) {
            InspectionItemStatus.pass => 1.0,
            InspectionItemStatus.attention => 0.5,
            _ => 0.0,
          } *
          weight;
    }
    final score = possible == 0 ? 100 : (earned / possible * 100).round();
    final color = score >= 85
        ? FixGoColors.success
        : score >= 60
            ? FixGoColors.warning
            : FixGoColors.error;

    return Card(
      margin: const EdgeInsets.only(bottom: FixGoSpacing.sm),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FixGoRadius.pill),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              color: color,
              backgroundColor: FixGoColors.hairline,
            ),
          ),
        ),
        trailing: Text(
          '$score',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          FixGoSpacing.md,
          0,
          FixGoSpacing.md,
          FixGoSpacing.md,
        ),
        children: [
          for (final item in items)
            _ItemLine(item: item, result: byCode[item.code]),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item, required this.result});

  final ChecklistItem item;
  final InspectionItemResult? result;

  @override
  Widget build(BuildContext context) {
    final status = result?.effectiveStatus(item);
    final (icon, color) = switch (status) {
      InspectionItemStatus.pass => (Icons.check_circle, FixGoColors.success),
      InspectionItemStatus.attention => (Icons.error, FixGoColors.warning),
      InspectionItemStatus.fail => (Icons.cancel, FixGoColors.error),
      _ => (Icons.remove_circle_outline, FixGoColors.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: FixGoSpacing.sm),
          Expanded(
              child: Text(item.label, style: const TextStyle(fontSize: 14))),
          if (result?.measurement != null && item.measurement != null)
            Text(
              '${result!.measurement} ${item.measurement!.unit}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
