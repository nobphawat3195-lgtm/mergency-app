import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

/// จอเต็มแบบนาฬิกาปลุกตอนมีงานใหม่: พื้นกระพริบแดง/เขียว ปุ่ม "รับงาน" ใหญ่ และเวลาที่เหลือ
///
/// กระพริบ 1 ครั้งต่อวินาที (ต่ำกว่า 3 ครั้งต่อวินาทีตามแนวทางกันอาการแพ้แสง)
/// หน้าหลักเอาออกเองเมื่อช่างรับ/ปฏิเสธ/ปิดเสียง หรืองานหมดเวลา
class OfferAlarmOverlay extends StatefulWidget {
  const OfferAlarmOverlay({
    super.key,
    required this.offer,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onSilence,
  });

  final JobOffer offer;

  /// กำลังส่งคำตอบ: ปิดปุ่มกันกดซ้ำ
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onSilence;

  @override
  State<OfferAlarmOverlay> createState() => _OfferAlarmOverlayState();
}

class _OfferAlarmOverlayState extends State<OfferAlarmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);
  late Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final left = offer.expiresAt.difference(clock.now());
    final expired = left.isNegative || left == Duration.zero;
    final seconds = expired ? 0 : left.inSeconds;
    final countdown =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final enabled = !expired && !widget.busy;

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) => ColoredBox(
        color: Color.lerp(
          FixGoColors.error,
          FixGoColors.accent,
          _flash.value,
        )!,
        child: child,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FixGoSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.notifications_active,
                color: Colors.white,
                size: 72,
              ),
              const SizedBox(height: FixGoSpacing.sm),
              const Text(
                'งานใหม่!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              Text(
                offer.subServiceName ?? offer.categoryName ?? 'งานซ่อมรถ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ห่าง ${offer.distanceKm.toStringAsFixed(1)} กม. · '
                'ราคาประเมิน ${formatSatang(offer.priceEstimated)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: FixGoSpacing.lg),
              Text(
                expired ? 'หมดเวลา' : 'เหลือเวลา $countdown',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 76,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FixGoColors.accent,
                    disabledBackgroundColor: Colors.white70,
                    textStyle: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: enabled ? widget.onAccept : null,
                  icon: widget.busy
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 32),
                  label: const Text('รับงาน'),
                ),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white, width: 2),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: enabled ? widget.onReject : null,
                      child: const Text('ปฏิเสธ'),
                    ),
                  ),
                  const SizedBox(width: FixGoSpacing.sm),
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: widget.onSilence,
                      icon: const Icon(Icons.volume_off),
                      label: const Text('ปิดเสียง'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
