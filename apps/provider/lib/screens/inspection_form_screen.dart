import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';

/// แบบฟอร์มตรวจรถมือสองสำหรับช่าง
///
/// - รายการตรวจดึงจาก backend ทั้งหมด (134 จุด แยก 11 หมวด)
/// - บันทึกอัตโนมัติทุกครั้งที่หยุดกรอก 1.5 วินาที สัญญาณหลุดกลางทางก็ไม่เสียงาน
/// - ข้อที่มีค่าวัด (ความหนาสี ดอกยาง ฯลฯ) ระบบตัดสินผ่าน/ไม่ผ่านจากเกณฑ์ให้เอง
class InspectionFormScreen extends StatefulWidget {
  const InspectionFormScreen({super.key, required this.order});

  final Order order;

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  InspectionChecklist? _checklist;
  InspectionReport? _report;
  String? _loadError;

  final Map<String, InspectionItemResult> _results = {};
  final Set<String> _dirtyItems = {};
  final Map<String, dynamic> _dirtyVehicle = {};
  Timer? _saveTimer;
  bool _saving = false;
  bool _submitting = false;
  String? _uploadingItem;

  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _color = TextEditingController();
  final _plateNo = TextEditingController();
  final _plateProvince = TextEditingController();
  final _vin = TextEditingController();
  final _engineNo = TextEditingController();
  final _mileage = TextEditingController();
  final _summary = TextEditingController();
  String? _powertrain;
  String? _transmission;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checklist == null && _loadError == null) unawaited(_load());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final controller in [
      _brand,
      _model,
      _year,
      _color,
      _plateNo,
      _plateProvince,
      _vin,
      _engineNo,
      _mileage,
      _summary,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ProviderAppScope.of(context).api;
    try {
      final results = await Future.wait([
        api.getInspectionChecklist(),
        api.getInspection(widget.order.id),
      ]);
      if (!mounted) return;
      final checklist = results[0] as InspectionChecklist;
      final report = results[1] as InspectionReport;
      setState(() {
        _checklist = checklist;
        _report = report;
        for (final item in report.items) {
          _results[item.itemCode] = item;
        }
        _brand.text = report.brand ?? '';
        _model.text = report.model ?? '';
        _year.text = report.year?.toString() ?? '';
        _color.text = report.color ?? '';
        _plateNo.text = report.plateNo ?? '';
        _plateProvince.text = report.plateProvince ?? '';
        _vin.text = report.vin ?? '';
        _engineNo.text = report.engineNo ?? '';
        _mileage.text = report.mileageKm?.toString() ?? '';
        _summary.text = report.summary ?? '';
        _powertrain = report.powertrain;
        _transmission = report.transmission;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    }
  }

  bool get _readOnly => _report?.isSubmitted ?? false;

  List<ChecklistItem> get _applicableItems => [
        for (final section
            in _checklist?.sections ?? const <ChecklistSection>[])
          for (final item in section.items)
            if (item.appliesToVehicle(
              powertrain: _powertrain,
              transmission: _transmission,
            ))
              item,
      ];

  bool _isAnswered(ChecklistItem item) =>
      _results[item.code]?.effectiveStatus(item) != null;

  // ---------- บันทึกอัตโนมัติ ----------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), _saveNow);
  }

  Future<bool> _saveNow() async {
    _saveTimer?.cancel();
    if (_dirtyItems.isEmpty && _dirtyVehicle.isEmpty) return true;
    final items = _dirtyItems.map((code) => _results[code]!).toList();
    final vehicle = Map<String, dynamic>.of(_dirtyVehicle);
    _dirtyItems.clear();
    _dirtyVehicle.clear();
    setState(() => _saving = true);
    try {
      await ProviderAppScope.of(context)
          .api
          .updateInspection(widget.order.id, vehicle: vehicle, items: items);
      return true;
    } on ApiException catch (error) {
      // เก็บรายการที่ยังไม่ได้บันทึกกลับเข้าคิว รอบหน้าจะส่งใหม่
      _dirtyItems.addAll(items.map((item) => item.itemCode));
      _dirtyVehicle.addAll(vehicle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: ${error.message}')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateItem(
      String code, InspectionItemResult Function(InspectionItemResult) change) {
    setState(() {
      final current = _results[code] ?? InspectionItemResult(itemCode: code);
      _results[code] = change(current);
      _dirtyItems.add(code);
    });
    _scheduleSave();
  }

  void _setVehicleField(String key, dynamic value) {
    _dirtyVehicle[key] = value;
    _scheduleSave();
  }

  Future<void> _attachPhoto(ChecklistItem item) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingItem = item.code);
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final url = await ProviderAppScope.of(context).api.uploadImage(
            bytes: bytes,
            fileName: picked.name,
            contentType: 'image/jpeg',
            scope: 'INSPECTION',
          );
      _updateItem(
        item.code,
        (current) => current.copyWith(photoUrls: [...current.photoUrls, url]),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _uploadingItem = null);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      if (!await _saveNow()) return;
      if (!mounted) return;
      final report = await ProviderAppScope.of(context)
          .api
          .submitInspection(widget.order.id);
      if (!mounted) return;
      setState(() => _report = report);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ส่งรายงานแล้ว'),
          content: Text(
            'คะแนน ${report.score}/100 เกรด ${report.grade}\n'
            '${report.verdict == null ? '' : inspectionVerdictLabel(report.verdict!)}\n\n'
            'ลูกค้าเห็นรายงานในแอปแล้ว กลับไปกดปิดงานได้เลย',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยังส่งรายงานไม่ได้'),
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('กลับไปแก้ไข'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final checklist = _checklist;
    final report = _report;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_saveNow());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ตรวจรถมือสอง'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: FixGoSpacing.md),
              child: Center(
                child: Text(
                  _saving ? 'กำลังบันทึก...' : 'บันทึกอัตโนมัติ',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
        body: checklist == null || report == null
            ? Center(
                child: _loadError != null
                    ? Text(_loadError!,
                        style: const TextStyle(color: FixGoColors.error))
                    : const CircularProgressIndicator(),
              )
            : _buildBody(checklist, report),
        bottomNavigationBar: checklist == null || _readOnly
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(FixGoSpacing.md),
                  child: FixGoButton(
                    label: 'ส่งรายงานให้ลูกค้า',
                    icon: Icons.send_outlined,
                    loading: _submitting,
                    onPressed: _submit,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody(InspectionChecklist checklist, InspectionReport report) {
    final applicable = _applicableItems;
    final answered = applicable.where(_isAnswered).length;
    final progress = applicable.isEmpty ? 0.0 : answered / applicable.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FixGoSpacing.md,
        FixGoSpacing.sm,
        FixGoSpacing.md,
        FixGoSpacing.xl,
      ),
      children: [
        _ProgressHeader(
          answered: answered,
          total: applicable.length,
          progress: progress,
          report: report,
        ),
        const SizedBox(height: FixGoSpacing.md),
        _buildVehicleCard(),
        const SizedBox(height: FixGoSpacing.md),
        for (final section in checklist.sections)
          if (section.items.any(
            (item) => item.appliesToVehicle(
              powertrain: _powertrain,
              transmission: _transmission,
            ),
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: FixGoSpacing.sm),
              child: _buildSection(section),
            ),
        const SizedBox(height: FixGoSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(FixGoSpacing.md),
            child: TextField(
              controller: _summary,
              enabled: !_readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'สรุปความเห็นช่าง (ลูกค้าจะเห็นข้อความนี้)',
                alignLabelWithHint: true,
              ),
              onChanged: (value) => _setVehicleField('summary', value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleCard() {
    Widget field(
      TextEditingController controller,
      String label,
      String key, {
      bool number = false,
      TextCapitalization caps = TextCapitalization.none,
    }) {
      return TextField(
        controller: controller,
        enabled: !_readOnly,
        textCapitalization: caps,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters:
            number ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label),
        onChanged: (value) {
          final trimmed = value.trim();
          _setVehicleField(
            key,
            trimmed.isEmpty
                ? null
                : number
                    ? int.tryParse(trimmed)
                    : trimmed,
          );
        },
      );
    }

    Widget pair(Widget left, Widget right) => Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: FixGoSpacing.sm),
            Expanded(child: right),
          ],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ข้อมูลรถ',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            pair(field(_brand, 'ยี่ห้อ *', 'brand'),
                field(_model, 'รุ่น *', 'model')),
            const SizedBox(height: FixGoSpacing.sm),
            pair(field(_year, 'ปีรถ (ค.ศ.) *', 'year', number: true),
                field(_color, 'สี', 'color')),
            const SizedBox(height: FixGoSpacing.sm),
            pair(field(_plateNo, 'ทะเบียน *', 'plateNo'),
                field(_plateProvince, 'จังหวัด', 'plateProvince')),
            const SizedBox(height: FixGoSpacing.sm),
            field(_vin, 'เลขตัวถัง (VIN) *', 'vin',
                caps: TextCapitalization.characters),
            const SizedBox(height: FixGoSpacing.sm),
            pair(
              field(_engineNo, 'เลขเครื่องยนต์', 'engineNo',
                  caps: TextCapitalization.characters),
              field(_mileage, 'เลขไมล์ (กม.) *', 'mileageKm', number: true),
            ),
            const SizedBox(height: FixGoSpacing.md),
            const Text('ระบบขับเคลื่อน *'),
            const SizedBox(height: FixGoSpacing.xs),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'combustion', label: Text('น้ำมัน')),
                ButtonSegment(value: 'hybrid', label: Text('ไฮบริด')),
                ButtonSegment(value: 'electrified', label: Text('EV')),
              ],
              emptySelectionAllowed: true,
              selected: {if (_powertrain != null) _powertrain!},
              onSelectionChanged: _readOnly
                  ? null
                  : (value) {
                      setState(() => _powertrain = value.firstOrNull);
                      _setVehicleField('powertrain', _powertrain);
                    },
            ),
            const SizedBox(height: FixGoSpacing.md),
            const Text('ระบบเกียร์ *'),
            const SizedBox(height: FixGoSpacing.xs),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'automatic', label: Text('อัตโนมัติ')),
                ButtonSegment(value: 'manual', label: Text('ธรรมดา')),
              ],
              emptySelectionAllowed: true,
              selected: {if (_transmission != null) _transmission!},
              onSelectionChanged: _readOnly
                  ? null
                  : (value) {
                      setState(() => _transmission = value.firstOrNull);
                      _setVehicleField('transmission', _transmission);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ChecklistSection section) {
    final items = section.items
        .where((item) => item.appliesToVehicle(
              powertrain: _powertrain,
              transmission: _transmission,
            ))
        .toList();
    final answered = items.where(_isAnswered).length;
    final issues = items.where((item) {
      final status = _results[item.code]?.effectiveStatus(item);
      return status == InspectionItemStatus.fail ||
          status == InspectionItemStatus.attention;
    }).length;
    final done = answered == items.length;

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? FixGoColors.success : FixGoColors.textSecondary,
        ),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'ตรวจแล้ว $answered/${items.length}'
          '${issues > 0 ? ' · พบจุดที่ต้องระวัง $issues' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: issues > 0 ? FixGoColors.warning : FixGoColors.textSecondary,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          FixGoSpacing.md,
          0,
          FixGoSpacing.md,
          FixGoSpacing.md,
        ),
        children: [
          Text(section.description,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: FixGoSpacing.sm),
          if (!_readOnly)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  for (final item in items) {
                    if (!_isAnswered(item) && item.measurement == null) {
                      _updateItem(
                        item.code,
                        (current) =>
                            current.copyWith(status: InspectionItemStatus.pass),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('ข้อที่เหลือผ่านทั้งหมด'),
              ),
            ),
          for (final item in items) ...[
            const Divider(height: FixGoSpacing.lg),
            _ItemRow(
              item: item,
              result: _results[item.code],
              readOnly: _readOnly,
              uploading: _uploadingItem == item.code,
              onStatus: (status) => _updateItem(
                item.code,
                (current) => current.copyWith(
                  status: status,
                  clearStatus: status == null,
                ),
              ),
              onMeasurement: (value) => _updateItem(
                item.code,
                (current) => current.copyWith(
                  measurement: value,
                  clearMeasurement: value == null,
                  // เปลี่ยนค่าวัด = ให้ระบบคำนวณผลใหม่ตามเกณฑ์
                  clearStatus: true,
                ),
              ),
              onNote: (value) => _updateItem(
                item.code,
                (current) => current.copyWith(note: value),
              ),
              onAddPhoto: () => _attachPhoto(item),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.answered,
    required this.total,
    required this.progress,
    required this.report,
  });

  final int answered;
  final int total;
  final double progress;
  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D3F33), FixGoColors.navy],
        ),
      ),
      child: Row(
        children: [
          Image.asset(categoryIconAsset('inspection'), height: 64),
          const SizedBox(width: FixGoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.vehicleTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (report.appointmentAt != null)
                  Text(
                    'นัดตรวจ ${formatThaiDateTime(report.appointmentAt!)}',
                    style:
                        const TextStyle(color: Color(0xFFC9DDD4), fontSize: 12),
                  ),
                const SizedBox(height: FixGoSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FixGoRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    color: FixGoColors.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report.isSubmitted
                      ? 'ส่งรายงานแล้ว · คะแนน ${report.score} เกรด ${report.grade}'
                      : 'ตรวจแล้ว $answered จาก $total จุด',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.result,
    required this.readOnly,
    required this.uploading,
    required this.onStatus,
    required this.onMeasurement,
    required this.onNote,
    required this.onAddPhoto,
  });

  final ChecklistItem item;
  final InspectionItemResult? result;
  final bool readOnly;
  final bool uploading;
  final ValueChanged<InspectionItemStatus?> onStatus;
  final ValueChanged<double?> onMeasurement;
  final ValueChanged<String> onNote;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final status = result?.effectiveStatus(item);
    final hasIssue = status == InspectionItemStatus.fail ||
        status == InspectionItemStatus.attention;
    final needsPhoto =
        item.photoOnIssue && hasIssue && (result?.photoUrls.isEmpty ?? true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${item.code}  ',
                      style: const TextStyle(
                        fontSize: 11,
                        color: FixGoColors.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: item.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            if (item.critical)
              Container(
                margin: const EdgeInsets.only(left: FixGoSpacing.xs),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: FixGoColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(FixGoRadius.pill),
                ),
                child: const Text(
                  'สำคัญ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FixGoColors.error,
                  ),
                ),
              ),
          ],
        ),
        if (item.hint != null) ...[
          const SizedBox(height: 2),
          Text(item.hint!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: FixGoSpacing.sm),
        if (item.measurement != null) ...[
          SizedBox(
            width: 180,
            child: TextFormField(
              initialValue: result?.measurement?.toString() ?? '',
              enabled: !readOnly,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'ค่าที่วัดได้',
                suffixText: item.measurement!.unit,
              ),
              onChanged: (value) => onMeasurement(double.tryParse(value)),
            ),
          ),
          const SizedBox(height: FixGoSpacing.sm),
        ],
        Wrap(
          spacing: FixGoSpacing.xs,
          runSpacing: FixGoSpacing.xs,
          children: [
            for (final option in InspectionItemStatus.values)
              ChoiceChip(
                label: Text(inspectionItemStatusLabel(option)),
                selected: status == option,
                selectedColor: _statusColor(option).withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      status == option ? FontWeight.w700 : FontWeight.w400,
                  color: status == option
                      ? _statusColor(option)
                      : FixGoColors.textPrimary,
                ),
                showCheckmark: false,
                onSelected: readOnly
                    ? null
                    : (selected) => onStatus(selected ? option : null),
              ),
          ],
        ),
        if (hasIssue) ...[
          const SizedBox(height: FixGoSpacing.sm),
          TextFormField(
            initialValue: result?.note ?? '',
            enabled: !readOnly,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'อธิบายสิ่งที่พบ',
            ),
            onChanged: onNote,
          ),
          const SizedBox(height: FixGoSpacing.sm),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  foregroundColor:
                      needsPhoto ? FixGoColors.error : FixGoColors.textPrimary,
                ),
                onPressed: readOnly || uploading ? null : onAddPhoto,
                icon: uploading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(
                  needsPhoto
                      ? 'ต้องถ่ายรูปประกอบ'
                      : 'ถ่ายรูป (${result?.photoUrls.length ?? 0})',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Color _statusColor(InspectionItemStatus status) {
  switch (status) {
    case InspectionItemStatus.pass:
      return FixGoColors.success;
    case InspectionItemStatus.attention:
      return FixGoColors.warning;
    case InspectionItemStatus.fail:
      return FixGoColors.error;
    case InspectionItemStatus.notApplicable:
      return FixGoColors.textSecondary;
  }
}
