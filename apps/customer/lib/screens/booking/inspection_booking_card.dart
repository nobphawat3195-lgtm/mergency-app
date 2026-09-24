import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ข้อมูลรถที่ลูกค้าจะให้ช่างไปตรวจก่อนซื้อ แสดงในขั้นยืนยันของงานตรวจรถมือสอง
///
/// ข้อมูลนี้ช่างใช้เตรียมตัวก่อนไป (เปิดดูประกาศ โทรนัดผู้ขาย) ส่วนข้อมูลจริงจาก
/// เล่มทะเบียน/ตัวรถ ช่างจะกรอกเองหน้างาน
class InspectionBookingCard extends StatefulWidget {
  const InspectionBookingCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final InspectionBooking value;
  final ValueChanged<InspectionBooking> onChanged;

  @override
  State<InspectionBookingCard> createState() => _InspectionBookingCardState();
}

class _InspectionBookingCardState extends State<InspectionBookingCard> {
  late final _brand = TextEditingController(text: widget.value.brand);
  late final _model = TextEditingController(text: widget.value.model);
  late final _year =
      TextEditingController(text: widget.value.year?.toString() ?? '');
  late final _listing = TextEditingController(text: widget.value.listingUrl);
  late final _sellerName = TextEditingController(text: widget.value.sellerName);
  late final _sellerPhone =
      TextEditingController(text: widget.value.sellerPhone);

  @override
  void dispose() {
    for (final controller in [
      _brand,
      _model,
      _year,
      _listing,
      _sellerName,
      _sellerPhone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit({DateTime? appointmentAt}) {
    widget.onChanged(
      InspectionBooking(
        brand: _brand.text,
        model: _model.text,
        year: int.tryParse(_year.text),
        listingUrl: _listing.text,
        sellerName: _sellerName.text,
        sellerPhone: _sellerPhone.text,
        appointmentAt: appointmentAt ?? widget.value.appointmentAt,
      ),
    );
  }

  Future<void> _pickAppointment() async {
    final now = DateTime.now();
    final initial =
        widget.value.appointmentAt ?? now.add(const Duration(hours: 3));
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
      initialDate: initial,
      helpText: 'เลือกวันนัดตรวจรถ',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'เลือกเวลานัด',
    );
    if (time == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(now.add(const Duration(hours: 1)))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('กรุณานัดล่วงหน้าอย่างน้อย 1 ชั่วโมง ให้ช่างเดินทางทัน'),
        ),
      );
      return;
    }
    _emit(appointmentAt: picked);
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.value.appointmentAt;

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
            Row(
              children: [
                Image.asset(categoryIconAsset('inspection'), height: 56),
                const SizedBox(width: FixGoSpacing.sm),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รถที่จะให้ตรวจ',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'ตรวจ 134 จุด เช็กรถจมน้ำ ชนหนัก กรอไมล์ ใช้เวลา 60–90 นาที',
                        style: TextStyle(
                          fontSize: 12,
                          color: FixGoColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.md),
            Material(
              color: appointment == null
                  ? FixGoColors.accentSoft
                  : FixGoColors.surface,
              borderRadius: BorderRadius.circular(FixGoRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(FixGoRadius.md),
                onTap: _pickAppointment,
                child: Padding(
                  padding: const EdgeInsets.all(FixGoSpacing.md),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_available_outlined,
                        color: FixGoColors.accent,
                      ),
                      const SizedBox(width: FixGoSpacing.sm),
                      Expanded(
                        child: Text(
                          appointment == null
                              ? 'เลือกวันและเวลานัดตรวจ *'
                              : 'นัดตรวจ ${formatThaiDateTime(appointment)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: FixGoSpacing.md),
            pair(
              TextField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'ยี่ห้อ'),
                onChanged: (_) => _emit(),
              ),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'รุ่น'),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration:
                  const InputDecoration(labelText: 'ปีรถ (ค.ศ.) เช่น 2019'),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _listing,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'ลิงก์ประกาศขาย (ถ้ามี)',
                hintText: 'https://',
              ),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            pair(
              TextField(
                controller: _sellerName,
                decoration:
                    const InputDecoration(labelText: 'ชื่อผู้ขาย/เต็นท์'),
                onChanged: (_) => _emit(),
              ),
              TextField(
                controller: _sellerPhone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(labelText: 'เบอร์ผู้ขาย'),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            Text(
              'ตำแหน่งนัดตรวจใช้ตำแหน่ง GPS ปัจจุบันของคุณ ถ้ารถอยู่ที่อื่น '
              'ให้ระบุที่อยู่ของรถในช่องหมายเหตุด้านล่าง',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
