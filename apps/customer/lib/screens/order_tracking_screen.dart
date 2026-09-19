import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pollTimer != null) return;
    unawaited(_refresh());
    // TODO: เปลี่ยนเป็น WebSocket เมื่อต่อ real-time tracking ตอนนี้ poll ไปก่อน
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
      final charge = await AppStateScope.of(context)
          .api
          .createPromptPayCharge(widget.orderId);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('สแกนจ่ายด้วยพร้อมเพย์'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TODO: แสดง QR จริงหลังต่อ payment gateway (ตอนนี้ backend คืน payload ทดสอบ)
              const Icon(Icons.qr_code_2, size: 120),
              const SizedBox(height: FixGoSpacing.md),
              Text(
                formatSatang(charge.amount),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
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
                if (order.provider != null) _ProviderCard(order: order),
                const SizedBox(height: FixGoSpacing.md),
                _PriceCard(order: order),
                const SizedBox(height: FixGoSpacing.lg),
                if (order.status == OrderStatus.completed)
                  FixGoButton(
                    label: 'ชำระเงินผ่านพร้อมเพย์',
                    icon: Icons.qr_code_2,
                    onPressed: _pay,
                  ),
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
                fontWeight: FontWeight.w900,
                color: FixGoColors.navy,
              ),
            ),
            if (order.status == OrderStatus.noMatch) ...[
              const SizedBox(height: FixGoSpacing.sm),
              const Text(
                'ยังไม่มีช่างว่างรับงานในขณะนี้ ทีมงานกำลังติดต่อช่างให้คุณ',
                style: TextStyle(color: FixGoColors.warning),
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
                height: 20,
                width: 20,
                color: done ? FixGoColors.accent : const Color(0xFFE5E7EB),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? FixGoColors.accent : const Color(0xFFE5E7EB),
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
              color: FixGoColors.navy,
              child: const Icon(Icons.engineering, color: FixGoColors.accent),
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
                          size: 16, color: FixGoColors.accent),
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
              onPressed: () {
                // TODO: ต่อ url_launcher เพื่อโทรออกจริง
              },
              icon: const Icon(Icons.phone),
              style: IconButton.styleFrom(
                backgroundColor: FixGoColors.accent,
                foregroundColor: FixGoColors.navy,
              ),
            ),
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
                    isFinal ? 'ราคาสุทธิ' : 'ราคาประเมิน',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              formatSatang(order.priceFinal ?? order.priceEstimated),
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
