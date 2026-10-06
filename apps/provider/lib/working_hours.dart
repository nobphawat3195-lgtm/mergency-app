import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

/// เวลารับงานของช่าง เก็บเป็นนาทีนับจากเที่ยงคืน 0-1439 ใช้ทุกวัน
/// ระบบส่งงาน (backend isWithinWorkingHours) ให้งานเฉพาะในช่วงนี้ นับนาทีเลิกด้วย
/// เริ่ม > เลิก = ข้ามเที่ยงคืน เช่น 18:00-06:00 และ 00:00-23:59 = ตลอดเวลา
const allDayOpenMinute = 0;
const allDayCloseMinute = 23 * 60 + 59;

/// นาทีของวันตามเวลาไทย (UTC+7) ให้ตรงกับที่ backend ใช้ ไม่ขึ้นกับเขตเวลาของเครื่อง
int bangkokMinuteOfDay([DateTime? now]) {
  final bangkok = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
  return bangkok.hour * 60 + bangkok.minute;
}

bool isWithinWorkingHours(int open, int close, int minuteOfDay) {
  if (open > close) return minuteOfDay >= open || minuteOfDay <= close;
  return minuteOfDay >= open && minuteOfDay <= close;
}

bool isAllDay(int open, int close) =>
    open == allDayOpenMinute && close == allDayCloseMinute;

String formatMinuteOfDay(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:'
    '${(minute % 60).toString().padLeft(2, '0')}';

/// "ตลอดเวลา" หรือ "08:00-20:00"
String workingHoursLabel(int open, int close) => isAllDay(open, close)
    ? 'ตลอดเวลา'
    : '${formatMinuteOfDay(open)}-${formatMinuteOfDay(close)}';

/// ข้อความเต็มของช่วงที่เลือก เช่น "รับงาน 20:30 ถึง 06:00 (ข้ามเที่ยงคืน)"
String workingHoursSentence(int open, int close) {
  if (isAllDay(open, close)) return 'รับงานตลอดเวลา';
  final overnight = open > close ? ' (ข้ามเที่ยงคืน)' : '';
  return 'รับงาน ${formatMinuteOfDay(open)} ถึง ${formatMinuteOfDay(close)}$overnight';
}

enum WorkingHoursPreset {
  allDay('ตลอดเวลา', allDayOpenMinute, allDayCloseMinute),
  day('กลางวัน 08:00-20:00', 8 * 60, 20 * 60),
  night('กลางคืน 18:00-06:00', 18 * 60, 6 * 60),
  custom('กำหนดเอง', null, null);

  const WorkingHoursPreset(this.label, this.open, this.close);

  final String label;
  final int? open;
  final int? close;

  static WorkingHoursPreset of(int open, int close) => values.firstWhere(
        (preset) => preset.open == open && preset.close == close,
        orElse: () => custom,
      );
}

/// ปุ่มลัด "รับงานต่ออีก N ชม." / "ถึงเที่ยงคืน": เลิกรับงานตามเวลาที่เลือกนับจากตอนนี้
/// ถ้าตอนนี้อยู่ในช่วงเดิม (และไม่ใช่ตลอดเวลา) คงเวลาเริ่มไว้ ไม่งั้นเริ่มตั้งแต่ตอนนี้
({int open, int close}) extendWorkingHours({
  required int open,
  required int close,
  Duration? by,
  DateTime? now,
}) {
  final minute = bangkokMinuteOfDay(now);
  final keepOpen =
      !isAllDay(open, close) && isWithinWorkingHours(open, close, minute);
  final newClose =
      by == null ? allDayCloseMinute : (minute + by.inMinutes) % (24 * 60);
  return (open: keepOpen ? open : minute, close: newClose);
}

/// ตัวเลือกเวลารับงาน: ตลอดเวลา / กลางวัน / กลางคืน / กำหนดเอง (นาฬิกา 24 ชม.)
/// ใช้ทั้งหน้าสมัครและ bottom sheet แก้เวลา
class WorkingHoursFields extends StatelessWidget {
  const WorkingHoursFields({
    super.key,
    required this.open,
    required this.close,
    required this.custom,
    required this.onChanged,
    this.enabled = true,
  });

  final int open;
  final int close;

  /// เลือก "กำหนดเอง" อยู่ (แม้เวลาจะบังเอิญตรงกับตัวเลือกสำเร็จรูป)
  final bool custom;
  final void Function(int open, int close, {required bool custom}) onChanged;
  final bool enabled;

  WorkingHoursPreset get _selected =>
      custom ? WorkingHoursPreset.custom : WorkingHoursPreset.of(open, close);

  Future<void> _pickTime(BuildContext context, {required bool isOpen}) async {
    final current = isOpen ? open : close;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: isOpen ? 'เริ่มรับงาน' : 'เลิกรับงาน',
      // พิมพ์ตัวเลขตรงๆ แบบ 24 ชม. ง่ายกว่าหมุนหน้าปัดบนมือถือ
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    onChanged(isOpen ? minute : open, isOpen ? close : minute, custom: true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: FixGoSpacing.sm,
          runSpacing: FixGoSpacing.sm,
          children: [
            for (final preset in WorkingHoursPreset.values)
              ChoiceChip(
                label: Text(preset.label),
                selected: selected == preset,
                onSelected: !enabled
                    ? null
                    : (_) {
                        if (preset == WorkingHoursPreset.custom) {
                          // เริ่มจากช่วงเดิม ถ้าเดิมเป็นตลอดเวลาให้เริ่มที่ 08:00-20:00
                          final allDay = isAllDay(open, close);
                          onChanged(
                            allDay ? 8 * 60 : open,
                            allDay ? 20 * 60 : close,
                            custom: true,
                          );
                        } else {
                          onChanged(preset.open!, preset.close!, custom: false);
                        }
                      },
              ),
          ],
        ),
        if (selected == WorkingHoursPreset.custom) ...[
          const SizedBox(height: FixGoSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'เริ่มรับงาน',
                  minute: open,
                  onTap:
                      enabled ? () => _pickTime(context, isOpen: true) : null,
                ),
              ),
              const SizedBox(width: FixGoSpacing.sm),
              Expanded(
                child: _TimeField(
                  label: 'เลิกรับงาน',
                  minute: close,
                  onTap:
                      enabled ? () => _pickTime(context, isOpen: false) : null,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: FixGoSpacing.sm),
        Text(
          workingHoursSentence(open, close),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: FixGoColors.navy,
          ),
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minute,
    required this.onTap,
  });

  final String label;
  final int minute;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          formatMinuteOfDay(minute),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// bottom sheet แก้เวลารับงาน: ปุ่มลัดบันทึกทันทีในแตะเดียว ตัวเลือกอื่นกด "บันทึก"
/// คืนช่วงเวลาใหม่เมื่อบันทึกสำเร็จ หรือ null ถ้าปิดไปเฉยๆ
Future<({int open, int close})?> showWorkingHoursSheet(
  BuildContext context, {
  required FixGoApiClient api,
  required int open,
  required int close,
}) {
  return showModalBottomSheet<({int open, int close})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WorkingHoursSheet(api: api, open: open, close: close),
  );
}

class _WorkingHoursSheet extends StatefulWidget {
  const _WorkingHoursSheet({
    required this.api,
    required this.open,
    required this.close,
  });

  final FixGoApiClient api;
  final int open;
  final int close;

  @override
  State<_WorkingHoursSheet> createState() => _WorkingHoursSheetState();
}

class _WorkingHoursSheetState extends State<_WorkingHoursSheet> {
  late int _open = widget.open;
  late int _close = widget.close;
  late bool _custom = WorkingHoursPreset.of(widget.open, widget.close) ==
      WorkingHoursPreset.custom;
  bool _saving = false;
  String? _error;

  Future<void> _save(int open, int close) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api
          .updateProviderHours(openMinute: open, closeMinute: close);
      if (!mounted) return;
      Navigator.of(context)
          .pop((open: saved.openMinute, close: saved.closeMinute));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  void _extend(Duration? by) {
    final next = extendWorkingHours(open: _open, close: _close, by: by);
    _save(next.open, next.close);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FixGoSpacing.md,
          0,
          FixGoSpacing.md,
          FixGoSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('เวลารับงาน', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'ระบบส่งงานให้เฉพาะในช่วงนี้ และต้องเปิด "พร้อมรับงาน" ด้วย',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.md),
            const Text('ปุ่มลัด (บันทึกทันที)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: FixGoSpacing.xs),
            Wrap(
              spacing: FixGoSpacing.sm,
              runSpacing: FixGoSpacing.sm,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.more_time, size: 18),
                  label: const Text('รับงานต่ออีก 2 ชม.'),
                  onPressed:
                      _saving ? null : () => _extend(const Duration(hours: 2)),
                ),
                ActionChip(
                  avatar: const Icon(Icons.more_time, size: 18),
                  label: const Text('ต่ออีก 4 ชม.'),
                  onPressed:
                      _saving ? null : () => _extend(const Duration(hours: 4)),
                ),
                ActionChip(
                  avatar: const Icon(Icons.nights_stay_outlined, size: 18),
                  label: const Text('ถึงเที่ยงคืน'),
                  onPressed: _saving ? null : () => _extend(null),
                ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: FixGoSpacing.md),
            WorkingHoursFields(
              open: _open,
              close: _close,
              custom: _custom,
              enabled: !_saving,
              onChanged: (open, close, {required custom}) => setState(() {
                _open = open;
                _close = close;
                _custom = custom;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: FixGoSpacing.sm),
              Text(_error!, style: const TextStyle(color: FixGoColors.error)),
            ],
            const SizedBox(height: FixGoSpacing.md),
            FilledButton(
              onPressed: _saving ? null : () => _save(_open, _close),
              child: Text(_saving ? 'กำลังบันทึก...' : 'บันทึกเวลารับงาน'),
            ),
          ],
        ),
      ),
    );
  }
}
