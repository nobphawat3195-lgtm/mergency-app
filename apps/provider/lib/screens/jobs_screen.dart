import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'inspection_form_screen.dart';

/// งานที่ช่างรับไว้แล้ว พร้อมปุ่มอัปเดตสถานะทีละขั้น
///
/// เว็บไม่มี push จึง poll ทุก 10 วินาทีระหว่างแท็บนี้เปิดอยู่ และโหลดใหม่ทันทีเมื่อเปิดแท็บ
/// หรือเมื่อหน้าอื่นแจ้งว่างานเปลี่ยน ([ProviderAppState.jobsRevision])
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, this.active = true});

  /// แท็บนี้กำลังแสดงอยู่หรือไม่ (IndexedStack เก็บทุกแท็บไว้พร้อมกัน)
  final bool active;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  static const _pollInterval = Duration(seconds: 10);

  List<Order>? _orders;
  String? _error;
  Timer? _poll;
  StreamSubscription<PushEvent>? _pushSub;
  ValueNotifier<int>? _jobsRevision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = ProviderAppScope.of(context).jobsRevision;
    if (_jobsRevision != revision) {
      _jobsRevision?.removeListener(_reloadQuietly);
      _jobsRevision = revision..addListener(_reloadQuietly);
    }
    if (_orders == null && _error == null) unawaited(_reload());
    final push = PushNotifications.instance;
    _pushSub ??= push.onAny.where((event) => event.type != 'OFFER').listen((_) {
      if (mounted) unawaited(_reload());
    });
    _syncPolling();
  }

  @override
  void didUpdateWidget(JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) unawaited(_reload());
    _syncPolling();
  }

  void _syncPolling() {
    if (widget.active) {
      _poll ??= Timer.periodic(_pollInterval, (_) => _reloadQuietly());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _jobsRevision?.removeListener(_reloadQuietly);
    _pushSub?.cancel();
    super.dispose();
  }

  void _reloadQuietly() {
    if (mounted) unawaited(_reload());
  }

  /// โหลดเงียบๆ เก็บรายการเดิมไว้ระหว่างรอ ไม่ให้จอกระพริบทุกรอบ poll
  Future<void> _reload() async {
    try {
      final orders =
          await ProviderAppScope.of(context).api.listAssignedOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      // มีรายการเดิมอยู่แล้วก็แสดงต่อไป รอบถัดไปจะลองใหม่เอง
      if (_orders == null) setState(() => _error = error.message);
    }
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

  /// งานที่ช่างต้องเดินทาง/ติดต่อลูกค้าอยู่
  static bool _isActive(Order order) =>
      order.status == OrderStatus.matched ||
      order.status == OrderStatus.enRoute ||
      order.status == OrderStatus.inProgress;

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
        child: Builder(
          builder: (context) {
            final orders = _orders;
            if (orders == null && _error != null) {
              return ListView(
                padding: const EdgeInsets.all(FixGoSpacing.lg),
                children: [
                  const SizedBox(height: 80),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: FixGoColors.error),
                  ),
                  const SizedBox(height: FixGoSpacing.md),
                  FixGoSecondaryButton(label: 'ลองใหม่', onPressed: _reload),
                ],
              );
            }
            if (orders == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (orders.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 100),
                  Image.asset(technicianIconAsset, height: 96),
                  const SizedBox(height: FixGoSpacing.md),
                  const Text(
                    'ยังไม่มีงานที่รับไว้',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'กดรับงานที่หน้าหลัก งานที่รับแล้วจะแสดงที่นี่\nพร้อมปุ่มออกเดินทาง ส่งราคา และปิดงาน',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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
                            style: _isActive(order)
                                ? const TextStyle(fontWeight: FontWeight.w600)
                                : Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (_isActive(order)) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          _ContactActions(order: order),
                        ],
                        if (_isActive(order) && order.photoUrls.isNotEmpty) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          _ProblemPhotos(urls: order.photoUrls),
                        ],
                        if (order.isInspection && order.inspection != null) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          _InspectionInfo(report: order.inspection!),
                        ],
                        if (order.note != null && order.note!.isNotEmpty) ...[
                          const SizedBox(height: FixGoSpacing.sm),
                          Text('หมายเหตุลูกค้า: ${order.note!}'),
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

/// ปุ่มนำทางไปจุดนัดหมายและโทรหาลูกค้า (เบอร์มาจาก backend เฉพาะงานที่ยังไม่จบ)
class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.order});

  final Order order;

  Future<void> _navigate(BuildContext context) async {
    final opened = await LocationService.openInMaps(
      order.pickupLat,
      order.pickupLng,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('เปิดแผนที่ไม่ได้')));
    }
  }

  Future<void> _call(BuildContext context, String phone) async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('โทรไม่ได้ เบอร์ลูกค้า $phone')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = order.customerPhone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order.customerName != null && order.customerName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FixGoSpacing.xs),
            child: Text(
              'ลูกค้า: ${order.customerName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _navigate(context),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('นำทาง'),
              ),
            ),
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(width: FixGoSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => _call(context, phone),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('โทรหาลูกค้า'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// รูปอาการรถที่ลูกค้าแนบตอนเรียกช่าง แตะเพื่อดูเต็มจอ
class _ProblemPhotos extends StatelessWidget {
  const _ProblemPhotos({required this.urls});

  final List<String> urls;

  void _open(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(FixGoSpacing.md),
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(FixGoSpacing.lg),
              child: Text('โหลดรูปไม่ได้'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('รูปอาการรถ', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: FixGoSpacing.xs),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: FixGoSpacing.xs),
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => _open(context, urls[index]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(FixGoRadius.sm),
                child: Image.network(
                  urls[index],
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    color: FixGoColors.accentSoft,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
