import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'inspection_form_screen.dart';

/// งานที่ช่างรับไว้แล้ว พร้อมปุ่มอัปเดตสถานะทีละขั้น
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  Future<List<Order>>? _future;
  StreamSubscription<PushEvent>? _pushSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ProviderAppScope.of(context).api.listAssignedOrders();
    final push = PushNotifications.instance;
    _pushSub ??= push.onAny
        .where((event) => event.type != 'OFFER')
        .listen((_) {
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = ProviderAppScope.of(context).api.listAssignedOrders();
    });
    await _future;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _proposeQuote(Order order) async {
    final controller = TextEditingController(
      text: ((order.priceProposed ?? order.priceEstimated) / 100)
          .toStringAsFixed(0),
    );
    final noteController = TextEditingController(text: order.quoteNote ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เสนอราคาให้ลูกค้ายืนยัน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'กรอกราคารวมก่อนเริ่มงาน ลูกค้าจะเห็นราคาและต้องกดยืนยันก่อน',
            ),
            const SizedBox(height: FixGoSpacing.md),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ราคารวม',
                prefixText: '฿ ',
              ),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'รายละเอียดงาน/อะไหล่ (ถ้ามี)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ส่งให้ลูกค้า'),
          ),
        ],
      ),
    );

    final rawPrice = controller.text.trim();
    final quoteNote = noteController.text.trim();
    controller.dispose();
    noteController.dispose();
    if (confirmed != true || !mounted) return;

    final baht = double.tryParse(rawPrice);
    if (baht == null || baht <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรอกราคาไม่ถูกต้อง')),
      );
      return;
    }

    await _run(
      () => ProviderAppScope.of(context)
          .api
          .proposeQuote(order.id, bahtToSatang(baht), note: quoteNote),
    );
  }

  Future<void> _complete(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันงานเสร็จ'),
        content: Text(
          'ปิดงานด้วยราคาที่ลูกค้ายืนยันแล้ว '
          '${formatSatang(order.priceProposed ?? order.priceEstimated)} ใช่ไหม',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยังไม่เสร็จ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยืนยันปิดงาน'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => ProviderAppScope.of(context).api.completeJob(order.id));
  }

  Future<void> _confirmCash(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันรับเงินสด'),
        content: Text(
          'คุณได้รับเงินสด ${formatSatang(order.priceFinal ?? order.priceProposed ?? 0)} '
          'จากลูกค้าเรียบร้อยแล้วใช่ไหม',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยังไม่ได้รับ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ได้รับแล้ว'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ProviderAppScope.of(context).api.confirmCashPayment(order.id),
    );
  }

  Future<void> _openInspection(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => InspectionFormScreen(order: order),
      ),
    );
    if (mounted) await _reload();
  }

  Widget _buildAction(Order order) {
    if (order.status == OrderStatus.matched) {
      return FixGoButton(
        label: 'เริ่มเดินทาง',
        icon: Icons.directions_car,
        onPressed: () => _run(
          () => ProviderAppScope.of(context).api.markEnRoute(order.id),
        ),
      );
    }

    if (order.status == OrderStatus.enRoute) {
      switch (order.quoteStatus) {
        case QuoteStatus.notRequested:
        case QuoteStatus.rejected:
          return FixGoButton(
            label: order.quoteStatus == QuoteStatus.rejected
                ? 'แก้ไขและส่งราคาใหม่'
                : 'ถึงหน้างาน เสนอราคา',
            icon: Icons.request_quote_outlined,
            onPressed: () => _proposeQuote(order),
          );
        case QuoteStatus.pending:
          return const FixGoButton(
            label: 'รอลูกค้ายืนยันราคา',
            icon: Icons.hourglass_top,
            onPressed: null,
          );
        case QuoteStatus.approved:
          return FixGoButton(
            label: 'ลูกค้ายืนยันแล้ว เริ่มงาน',
            icon: Icons.build,
            onPressed: () => _run(
              () => ProviderAppScope.of(context).api.startJob(order.id),
            ),
          );
      }
    }

    // งานตรวจรถ: ราคาเดียวยืนยันตั้งแต่ตอนจอง ต้องส่งรายงานก่อนปิดงาน
    if (order.isInspection && order.status == OrderStatus.inProgress) {
      if (order.inspection?.isSubmitted != true) {
        return FixGoButton(
          label: 'ทำรายงานตรวจรถ 134 จุด',
          icon: Icons.fact_check_outlined,
          onPressed: () => _openInspection(order),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FixGoButton(
            label: 'ส่งรายงานแล้ว ปิดงาน',
            icon: Icons.check_circle_outline,
            onPressed: () => _complete(order),
          ),
          const SizedBox(height: FixGoSpacing.sm),
          FixGoSecondaryButton(
            label: 'ดูรายงานที่ส่ง',
            onPressed: () => _openInspection(order),
          ),
        ],
      );
    }

    if (order.status == OrderStatus.inProgress) {
      return FixGoButton(
        label: 'งานเสร็จแล้ว ปิดงาน',
        icon: Icons.check_circle_outline,
        onPressed: () => _complete(order),
      );
    }

    if (order.status == OrderStatus.completed) {
      if (order.isPaid) {
        return const FixGoButton(
          label: 'รับชำระเงินแล้ว',
          icon: Icons.verified_outlined,
          onPressed: null,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'สถานะเงิน: ${paymentStatusLabel(order.paymentStatus)} '
            '(ลูกค้าสแกนพร้อมเพย์แล้วต้องรอระบบยืนยันยอด)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FixGoColors.warning,
            ),
          ),
          const SizedBox(height: FixGoSpacing.sm),
          FixGoButton(
            label: 'ยืนยันว่าได้รับเงินสดแล้ว',
            icon: Icons.payments_outlined,
            onPressed: () => _confirmCash(order),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: const Text('งานของฉัน')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Order>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = snapshot.data ?? const <Order>[];
            if (orders.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      'ยังไม่มีงานที่รับไว้',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(FixGoSpacing.md),
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: FixGoSpacing.sm),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FixGoSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.subServiceName ??
                                    order.categoryName ??
                                    'งานซ่อม',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              formatSatang(
                                order.priceFinal ??
                                    order.priceProposed ??
                                    order.priceEstimated,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: FixGoSpacing.xs),
                        Text(
                          '${order.orderNo} · ${orderStatusLabel(order.status)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (order.pickupAddress != null) ...[
                          const SizedBox(height: FixGoSpacing.xs),
                          Text(
                            order.pickupAddress!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (order.isInspection && order.inspection != null) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          _InspectionInfo(report: order.inspection!),
                        ],
                        if (order.note != null && order.note!.isNotEmpty) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          Text('หมายเหตุ: ${order.note!}'),
                        ],
                        if (order.quoteStatus == QuoteStatus.rejected) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          const Text(
                            'ลูกค้ายังไม่ยืนยันราคา กรุณาพูดคุยและส่งราคาใหม่',
                            style: TextStyle(color: FixGoColors.error),
                          ),
                        ],
                        const SizedBox(height: FixGoSpacing.md),
                        _buildAction(order),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InspectionInfo extends StatelessWidget {
  const _InspectionInfo({required this.report});

  final InspectionReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.sm),
      decoration: BoxDecoration(
        color: FixGoColors.accentSoft,
        borderRadius: BorderRadius.circular(FixGoRadius.md),
      ),
      child: Row(
        children: [
          Image.asset(categoryIconAsset('inspection'), height: 44),
          const SizedBox(width: FixGoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.vehicleTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (report.appointmentAt != null)
                  Text('นัด ${formatThaiDateTime(report.appointmentAt!)}'),
                if (report.sellerName != null || report.sellerPhone != null)
                  Text(
                    'ผู้ขาย ${report.sellerName ?? ''} ${report.sellerPhone ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
