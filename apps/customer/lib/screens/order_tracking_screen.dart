import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'inspection_report_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Order? _order;
  String? _error;
  Timer? _pollTimer;
  bool _respondingToQuote = false;
  StreamSubscription<PushEvent>? _pushSub;
  StreamSubscription<String>? _liveSub;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// ต่อ event stream ติดอยู่: ดึงข้อมูลใหม่เมื่อมี event และ poll ช้าลงเป็นตัวสำรอง
  bool _live = false;
  int _pollTick = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pollTimer != null) return;
    unawaited(_refresh());
    _pushSub = PushNotifications.instance.onAny
        .where((event) => event.orderId == widget.orderId)
        .listen((_) => unawaited(_refresh()));
    _connectLive();
    // ตัวสำรองเมื่อ stream หลุดหรืออยู่บนเว็บ: ทุก 5 วินาที, ถ้า stream ติดอยู่ ทุก 30 วินาที
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollTick++;
      if (_live && _pollTick % 6 != 0) return;
      unawaited(_refresh());
    });
  }

  bool get _finished {
    final order = _order;
    if (order == null) return false;
    return order.status == OrderStatus.cancelled ||
        (order.status == OrderStatus.completed &&
            order.isPaid &&
            order.ratingScore != null);
  }

  /// Server-Sent Events จาก backend: เห็นช่างรับงาน/ขยับ/เสนอราคาทันทีโดยไม่ต้องรอรอบ poll
  void _connectLive() {
    // browser client ของเว็บไม่ส่งข้อมูลทีละส่วน ใช้ poll อย่างเดียว
    if (kIsWeb || !mounted || _finished) return;
    unawaited(_liveSub?.cancel());
    _liveSub = AppStateScope.of(context).api.orderEvents(widget.orderId).listen(
      (type) {
        _live = true;
        _reconnectAttempt = 0;
        if (type != 'PING') unawaited(_refresh());
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    _live = false;
    if (!mounted || _finished) return;
    _reconnectTimer?.cancel();
    // 2, 4, 8, 16, 30 วินาที
    final seconds = [2, 4, 8, 16, 30][_reconnectAttempt.clamp(0, 4)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), _connectLive);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _pushSub?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final order =
          await AppStateScope.of(context).api.getOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยกเลิกการเรียกช่าง'),
        content: const Text('ต้องการยกเลิกรายการนี้ใช่ไหม'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ไม่ใช่'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยกเลิกรายการ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AppStateScope.of(context).api.cancelOrder(widget.orderId);
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _pay() async {
    try {
      final api = AppStateScope.of(context).api;
      final charge = await api.createPromptPayCharge(widget.orderId);
      if (!mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        builder: (_) => _PromptPayDialog(
          api: api,
          orderId: widget.orderId,
          qrPayload: charge.qrPayload,
          amount: charge.amount,
          expiresAt: charge.expiresAt,
          requiresSlip: charge.requiresSlip,
          payeeName: charge.payeeName,
          slipAlreadySubmitted: _order?.awaitingSlipReview ?? false,
        ),
      );
      // ดึงสถานะใหม่เสมอ แต่ถือว่าจ่ายแล้วเฉพาะเมื่อ backend ตอบ PAID
      await _refresh();
      if (paid == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ชำระเงินเรียบร้อย ขอบคุณที่ใช้บริการ')),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _respondToQuote(bool approved) async {
    setState(() => _respondingToQuote = true);
    try {
      final api = AppStateScope.of(context).api;
      if (approved) {
        await api.approveQuote(widget.orderId);
      } else {
        await api.rejectQuote(widget.orderId);
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'ยืนยันราคาแล้ว ช่างสามารถเริ่มงานได้'
                : 'ปฏิเสธราคาแล้ว กรุณาพูดคุยกับช่างเพื่อรับราคาใหม่',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _respondingToQuote = false);
    }
  }

  void _showCashInstructions() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ชำระเงินสดกับช่าง'),
        content: const Text(
          'ชำระตามราคาที่คุณยืนยันไว้ และให้ช่างกด “ได้รับเงินสดแล้ว” '
          'สถานะการชำระเงินจะอัปเดตในหน้านี้อัตโนมัติ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('เข้าใจแล้ว'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: const Text('ติดตามงาน')),
      body: order == null
          ? Center(
              child: _error != null
                  ? Text(_error!,
                      style: const TextStyle(color: FixGoColors.error))
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(FixGoSpacing.md),
              children: [
                _StatusCard(order: order),
                const SizedBox(height: FixGoSpacing.md),
                if (order.isInspection && order.inspection != null) ...[
                  _InspectionCard(order: order),
                  const SizedBox(height: FixGoSpacing.md),
                ],
                if (order.provider != null) _ProviderCard(order: order),
                const SizedBox(height: FixGoSpacing.md),
                if (order.quoteStatus != QuoteStatus.notRequested) ...[
                  _QuoteCard(
                    order: order,
                    responding: _respondingToQuote,
                    onApprove: () => _respondToQuote(true),
                    onReject: () => _respondToQuote(false),
                  ),
                  const SizedBox(height: FixGoSpacing.md),
                ],
                _PriceCard(order: order),
                const SizedBox(height: FixGoSpacing.lg),
                if (order.status == OrderStatus.completed && order.isPaid)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(FixGoSpacing.md),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: FixGoColors.success,
                          ),
                          SizedBox(width: FixGoSpacing.sm),
                          Text(
                            'ชำระเงินเรียบร้อยแล้ว',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (order.status == OrderStatus.completed) ...[
                  if (order.awaitingSlipReview)
                    const _SlipReviewBanner()
                  else if (order.paymentSlipRejectReason != null)
                    _SlipRejectedBanner(reason: order.paymentSlipRejectReason!)
                  else
                    const _PaymentPendingBanner(),
                  const SizedBox(height: FixGoSpacing.md),
                  FixGoButton(
                    label: order.awaitingSlipReview
                        ? 'ดู QR / แนบสลิปใหม่'
                        : 'ชำระเงินผ่านพร้อมเพย์',
                    icon: Icons.qr_code_2,
                    onPressed: _pay,
                  ),
                  const SizedBox(height: FixGoSpacing.sm),
                  FixGoSecondaryButton(
                    label: 'ชำระเงินสดกับช่าง',
                    onPressed: _showCashInstructions,
                  ),
                ],
                if (order.status == OrderStatus.completed) ...[
                  const SizedBox(height: FixGoSpacing.md),
                  _FeedbackCard(
                    order: order,
                    onSubmitted: _refresh,
                  ),
                ],
                if (order.status == OrderStatus.searching ||
                    order.status == OrderStatus.created ||
                    order.status == OrderStatus.matched) ...[
                  const SizedBox(height: FixGoSpacing.sm),
                  FixGoSecondaryButton(
                    label: 'ยกเลิกการเรียกช่าง',
                    destructive: true,
                    onPressed: _cancel,
                  ),
                ],
              ],
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final Order order;

  static const _timeline = [
    OrderStatus.searching,
    OrderStatus.matched,
    OrderStatus.enRoute,
    OrderStatus.inProgress,
    OrderStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _timeline.indexOf(order.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เลขที่งาน ${order.orderNo}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: FixGoSpacing.xs),
            Text(
              orderStatusLabel(order.status),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: FixGoColors.accent,
              ),
            ),
            if (order.status == OrderStatus.noMatch) ...[
              const SizedBox(height: FixGoSpacing.sm),
              const Text(
                'ยังไม่มีช่างว่างรับงานในขณะนี้ ทีมงานกำลังติดต่อช่างให้คุณ',
                style: TextStyle(color: FixGoColors.warning),
              ),
            ],
            if (order.status == OrderStatus.cancelled &&
                order.cancelReason != null) ...[
              const SizedBox(height: FixGoSpacing.sm),
              Text(
                order.cancelReason!,
                style: const TextStyle(color: FixGoColors.textSecondary),
              ),
            ],
            const SizedBox(height: FixGoSpacing.md),
            for (var index = 0; index < _timeline.length; index++)
              _TimelineRow(
                label: orderStatusLabel(_timeline[index]),
                done: currentIndex >= index && currentIndex != -1,
                isLast: index == _timeline.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.done,
    required this.isLast,
  });

  final String label;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? FixGoColors.accent : FixGoColors.hairline,
                ),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? FixGoColors.accent : FixGoColors.hairline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: FixGoSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(bottom: FixGoSpacing.md),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: done ? FontWeight.w700 : FontWeight.w400,
                color:
                    done ? FixGoColors.textPrimary : FixGoColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final provider = order.provider!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Row(
          children: [
            Container(
              height: 56,
              width: 56,
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: FixGoColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Image.asset(technicianIconAsset),
            ),
            const SizedBox(width: FixGoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${provider.realName} (${provider.nickname})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: FixGoSpacing.xs),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 16, color: FixGoColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        provider.ratingAvg > 0
                            ? provider.ratingAvg.toStringAsFixed(1)
                            : 'ช่างใหม่',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton.filled(
              tooltip: 'โทรหาช่าง',
              onPressed: () async {
                final uri = Uri(scheme: 'tel', path: provider.phone);
                if (!await launchUrl(uri) && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('ไม่สามารถเปิดแอปโทรศัพท์ได้')),
                  );
                }
              },
              icon: const Icon(Icons.phone),
              style: IconButton.styleFrom(
                backgroundColor: FixGoColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.order,
    required this.responding,
    required this.onApprove,
    required this.onReject,
  });

  final Order order;
  final bool responding;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final proposed = order.priceProposed;
    final isPending = order.quoteStatus == QuoteStatus.pending;
    final isApproved = order.quoteStatus == QuoteStatus.approved;

    return Card(
      color: isPending ? const Color(0xFFFFF4DC) : null,
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isApproved
                      ? Icons.verified_outlined
                      : isPending
                          ? Icons.request_quote_outlined
                          : Icons.info_outline,
                  color: isApproved
                      ? FixGoColors.success
                      : isPending
                          ? FixGoColors.warning
                          : FixGoColors.error,
                ),
                const SizedBox(width: FixGoSpacing.sm),
                Expanded(
                  child: Text(
                    isApproved
                        ? 'คุณยืนยันราคานี้แล้ว'
                        : isPending
                            ? 'ช่างส่งราคาให้ยืนยัน'
                            : 'คุณปฏิเสธราคานี้แล้ว',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (proposed != null)
                  Text(
                    formatSatang(proposed),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            if (order.quoteNote != null && order.quoteNote!.isNotEmpty) ...[
              const SizedBox(height: FixGoSpacing.sm),
              Text(order.quoteNote!),
            ],
            if (isPending) ...[
              const SizedBox(height: FixGoSpacing.md),
              const Text(
                'ตรวจสอบรายการให้ครบก่อนกดยืนยัน ช่างจะเริ่มงานได้หลังจากคุณยืนยันเท่านั้น',
              ),
              const SizedBox(height: FixGoSpacing.md),
              FixGoButton(
                label: 'ยืนยันราคาและให้เริ่มงาน',
                loading: responding,
                onPressed: onApprove,
              ),
              const SizedBox(height: FixGoSpacing.sm),
              FixGoSecondaryButton(
                label: 'ยังไม่ยืนยัน ขอคุยกับช่าง',
                destructive: true,
                onPressed: responding ? null : onReject,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final isFinal = order.priceFinal != null;
    final displayPrice = order.priceFinal ??
        (order.quoteStatus == QuoteStatus.approved
            ? order.priceProposed
            : null) ??
        order.priceEstimated;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.subServiceName ?? order.categoryName ?? 'บริการ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: FixGoSpacing.xs),
                  Text(
                    isFinal
                        ? 'ราคาสุทธิ'
                        : order.quoteStatus == QuoteStatus.approved
                            ? 'ราคาที่คุณยืนยัน'
                            : 'ราคาประเมิน',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              formatSatang(displayPrice),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: FixGoColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final report = order.inspection!;
    final submitted = report.isSubmitted;
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.vehicleTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (report.appointmentAt != null)
                        Text(
                          'นัดตรวจ ${formatThaiDateTime(report.appointmentAt!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (submitted && report.grade != null)
                        Text(
                          'เกรด ${report.grade} · ${report.score}/100 · '
                          '${inspectionVerdictLabel(report.verdict!)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: FixGoColors.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FixGoSpacing.md),
            FixGoButton(
              label: submitted ? 'ดูรายงานตรวจรถ' : 'รอช่างตรวจให้ครบ 134 จุด',
              icon: Icons.fact_check_outlined,
              onPressed: submitted
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              InspectionReportScreen(orderId: order.id),
                        ),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// สถานะรอยืนยันยอดเงิน: การแสดง QR หรือการกดปุ่มไม่ถือว่าชำระสำเร็จ
/// เปลี่ยนเป็น "ชำระแล้ว" ได้เมื่อ backend บันทึก PAID เท่านั้น
/// ลูกค้าแนบสลิปแล้ว รอทีมงานตรวจยอดเข้าบัญชี (ยังไม่ถือว่าชำระแล้ว)
class _SlipReviewBanner extends StatelessWidget {
  const _SlipReviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FixGoColors.accentSoft,
        borderRadius: BorderRadius.circular(FixGoRadius.md),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, color: FixGoColors.accent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ได้รับสลิปแล้ว ทีมงานกำลังตรวจสอบยอดเงินเข้าบัญชี '
              'สถานะจะเปลี่ยนเป็น "ชำระแล้ว" หลังตรวจเสร็จ',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlipRejectedBanner extends StatelessWidget {
  const _SlipRejectedBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(FixGoRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: FixGoColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'สลิปยังไม่ผ่านการตรวจ: $reason\nกรุณาตรวจยอดแล้วแนบสลิปใหม่',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentPendingBanner extends StatelessWidget {
  const _PaymentPendingBanner({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(FixGoRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: FixGoColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'รอยืนยันยอดเงิน',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: FixGoColors.warning,
                  ),
                ),
                Text(
                  compact
                      ? 'หลังโอนแล้ว สถานะจะเปลี่ยนเมื่อระบบได้รับการยืนยันยอดเงินเท่านั้น'
                      : 'ยังไม่ได้รับการยืนยันการชำระเงิน สถานะจะเปลี่ยนเป็น "ชำระแล้ว" '
                          'เมื่อผู้ให้บริการรับชำระยืนยันยอด หรือช่างยืนยันรับเงินสด',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ให้คะแนนและความเห็นหลังรับบริการ ส่งได้ครั้งเดียวต่อออเดอร์ (backend บังคับ)
class _FeedbackCard extends StatefulWidget {
  const _FeedbackCard({required this.order, required this.onSubmitted});

  final Order order;
  final Future<void> Function() onSubmitted;

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  int _score = 0;
  bool _submitting = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final comment = _comment.text.trim();
      await AppStateScope.of(context).api.rateOrder(
            widget.order.id,
            _score,
            comment: comment.isEmpty ? null : comment,
          );
      await widget.onSubmitted();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ขอบคุณสำหรับความเห็นของคุณ')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _stars(int value, {ValueChanged<int>? onTap}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i ดาว',
            onPressed: onTap == null ? null : () => onTap(i),
            iconSize: 36,
            icon: Icon(
              i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i <= value
                  ? const Color(0xFFE5A100)
                  : FixGoColors.textSecondary,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rated = widget.order.ratingScore;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              rated == null ? 'ให้คะแนนบริการครั้งนี้' : 'คะแนนที่คุณให้',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (rated != null) ...[
              _stars(rated),
              if (widget.order.ratingComment != null)
                Text(
                  '“${widget.order.ratingComment}”',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ] else ...[
              _stars(_score, onTap: (value) => setState(() => _score = value)),
              TextField(
                controller: _comment,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'เล่าให้ฟังหน่อย ช่างมาตรงเวลาไหม งานเรียบร้อยไหม',
                ),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              ElevatedButton(
                onPressed: _score == 0 || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_score == 0 ? 'แตะดาวเพื่อให้คะแนน' : 'ส่งความเห็น'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// QR พร้อมเพย์: ตรวจสถานะจาก backend ทุก 4 วินาที ปิดเองเมื่อผู้ให้บริการรับชำระยืนยันยอดแล้ว
class _PromptPayDialog extends StatefulWidget {
  const _PromptPayDialog({
    required this.api,
    required this.orderId,
    required this.qrPayload,
    required this.amount,
    required this.expiresAt,
    this.requiresSlip = false,
    this.payeeName,
    this.slipAlreadySubmitted = false,
  });

  final FixGoApiClient api;
  final String orderId;
  final String qrPayload;
  final int amount;
  final DateTime? expiresAt;

  /// โอนเข้าบัญชีบริษัท: ต้องแนบสลิปให้ทีมงานตรวจ
  final bool requiresSlip;
  final String? payeeName;
  final bool slipAlreadySubmitted;

  @override
  State<_PromptPayDialog> createState() => _PromptPayDialogState();
}

class _PromptPayDialogState extends State<_PromptPayDialog> {
  Timer? _timer;
  bool _checking = false;
  late bool _slipSubmitted = widget.slipAlreadySubmitted;
  bool _uploadingSlip = false;

  Future<void> _attachSlip() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    setState(() => _uploadingSlip = true);
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final url = await widget.api.uploadImage(
        bytes: bytes,
        fileName: file.name,
        contentType: name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg',
        scope: 'PAYMENT_SLIP',
      );
      await widget.api.submitPaymentSlip(widget.orderId, url);
      if (mounted) setState(() => _slipSubmitted = true);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดสลิปไม่สำเร็จ กรุณาลองใหม่')),
      );
    } finally {
      if (mounted) setState(() => _uploadingSlip = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final order = await widget.api.getOrder(widget.orderId);
      if (order.isPaid && mounted) Navigator.of(context).pop(true);
    } on ApiException {
      // เน็ตหลุดชั่วคราว รอบหน้าลองใหม่
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final expires = widget.expiresAt;
    return AlertDialog(
      title: const Text('สแกนจ่ายด้วยพร้อมเพย์'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PaymentPendingBanner(compact: true),
            const SizedBox(height: FixGoSpacing.md),
            QrImageView(
              data: widget.qrPayload,
              size: 200,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: FixGoSpacing.md),
            Text(
              formatSatang(widget.amount),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            if (widget.payeeName != null) ...[
              const SizedBox(height: 4),
              Text(
                'โอนเข้าบัญชี: ${widget.payeeName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                'ตรวจชื่อบัญชีในแอปธนาคารให้ตรงก่อนกดโอน',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (expires != null)
              Text(
                'QR ใช้ได้ถึง ${expires.hour.toString().padLeft(2, '0')}:${expires.minute.toString().padLeft(2, '0')} น.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (widget.requiresSlip) ...[
              const SizedBox(height: FixGoSpacing.md),
              if (_slipSubmitted)
                const _SlipReviewBanner()
              else
                const Text(
                  'โอนเสร็จแล้ว แนบสลิปเพื่อให้ทีมงานตรวจยอด',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              const SizedBox(height: FixGoSpacing.sm),
              OutlinedButton.icon(
                onPressed: _uploadingSlip ? null : _attachSlip,
                icon: _uploadingSlip
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long_outlined),
                label: Text(_slipSubmitted ? 'แนบสลิปใหม่' : 'แนบสลิป'),
              ),
            ],
            const SizedBox(height: FixGoSpacing.sm),
            if (!widget.requiresSlip || _slipSubmitted)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('กำลังรอการยืนยันยอดเงิน...',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}
