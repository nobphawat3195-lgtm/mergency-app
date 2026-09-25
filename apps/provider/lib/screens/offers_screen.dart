import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_state.dart';

/// หน้าหลักแอปช่าง (FixGo Fixer): สถานะพร้อมรับงาน งานเข้าใหม่ งานที่กำลังทำ
/// สรุปวันนี้ และเมนูหลัก ตัวเลขทุกตัวมาจาก API จริง ไม่มีค่าสมมติ
///
/// งานที่ระบบเสนอให้ช่างเป็นชุด ช่างคนแรกที่กดรับจะได้งาน
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key, this.onOpenTab});

  /// สลับแท็บใน shell: 1 = งานของฉัน, 2 = กระเป๋าเงิน, 3 = โปรไฟล์
  final ValueChanged<int>? onOpenTab;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<JobOffer> _offers = const [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  bool _restoredTrackingStarted = false;
  _TodaySummary? _summary;
  Order? _activeJob;
  StreamSubscription<PushEvent>? _pushSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null) return;
    unawaited(_syncOnlineStatus());
    // มีงานใหม่หรือสถานะงานเปลี่ยน: ดึงทันทีไม่ต้องรอรอบ 10 วิ
    final push = PushNotifications.instance;
    _pushSub = push.onAny.listen((_) => unawaited(_refresh()));
    // ดึงงานใหม่ทุก 10 วิ และให้ countdown เดินด้วย
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refresh());
    });
  }

  /// หลังล็อกอินใหม่ สถานะในแอปเริ่มที่ออฟไลน์ ต้องอ่านค่าจริงจาก backend ก่อน
  /// ไม่งั้นปุ่ม "พร้อมรับงาน" จะแสดงไม่ตรงกับที่ระบบ dispatch เห็น
  Future<void> _syncOnlineStatus() async {
    final state = ProviderAppScope.of(context);
    try {
      final profile = await state.api.getProviderProfile();
      if (!mounted) return;
      state.setOnline(profile['isOnline'] as bool? ?? false);
    } on ApiException {
      // ใช้ค่าที่มีอยู่ต่อไป
    }
    if (!mounted) return;
    if (state.isOnline && !_restoredTrackingStarted) {
      _restoredTrackingStarted = true;
      unawaited(_startTrackingLocation());
    }
    await _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    _pushSub?.cancel();
    super.dispose();
  }

  /// เริ่มส่งตำแหน่งขึ้น backend ต่อเนื่องขณะออนไลน์ — ระบบ auto-dispatch ใช้
  /// ตำแหน่งนี้คำนวณระยะทางแบบเรียลไทม์ ไม่ใช่แค่ตำแหน่งตอนสมัครสมาชิก
  /// อัปเดตเฉพาะตอนแอปเปิดอยู่ (foreground) เท่านั้น ยังไม่รองรับ background tracking
  Future<void> _startTrackingLocation() async {
    try {
      // ส่งตำแหน่งปัจจุบันทันทีก่อน ไม่ต้องรอขยับ 50 เมตรตามที่ stream กำหนดไว้
      final initial = await LocationService.getCurrentLocation();
      if (!mounted) return;
      await ProviderAppScope.of(context)
          .api
          .updateProviderLocation(initial.latitude, initial.longitude);
    } on LocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }

    _positionSub?.cancel();
    _positionSub = LocationService.watchPosition().listen((position) {
      if (!mounted) return;
      ProviderAppScope.of(context)
          .api
          .updateProviderLocation(position.latitude, position.longitude)
          .catchError((_) {
        // เน็ตหลุดชั่วคราวระหว่างวิ่งงาน ไม่ต้องรบกวนช่างด้วย error ทุกครั้ง
        // รอบถัดไปของ stream จะพยายามส่งใหม่เอง
      });
    });
  }

  void _stopTrackingLocation() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _refresh() async {
    try {
      final state = ProviderAppScope.of(context);
      if (state.isOnline) await state.api.sendProviderHeartbeat();
      final results = await Future.wait([
        state.api.listOffers(),
        state.api.listAssignedOrders(),
        state.api.listWalletEntries(),
        state.api.getWalletBalance(),
      ]);
      if (!mounted) return;
      final orders = results[1] as List<Order>;
      setState(() {
        _offers = results[0] as List<JobOffer>;
        _activeJob = orders
            .where(
              (order) =>
                  order.status == OrderStatus.matched ||
                  order.status == OrderStatus.enRoute ||
                  order.status == OrderStatus.inProgress,
            )
            .firstOrNull;
        _summary = _TodaySummary.from(
          orders: orders,
          entries: results[2] as List<WalletEntry>,
          balance: results[3] as int,
        );
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _toggleOnline(bool value) async {
    try {
      await ProviderAppScope.of(context).api.setOnline(value);
      if (!mounted) return;
      ProviderAppScope.of(context).setOnline(value);

      if (value) {
        await _startTrackingLocation();
      } else {
        _stopTrackingLocation();
      }

      if (!mounted) return;
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _accept(JobOffer offer) async {
    try {
      await ProviderAppScope.of(context).api.acceptOffer(offer.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รับงานแล้ว ดูรายละเอียดในแท็บงานของฉัน')),
      );
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      await _refresh();
    }
  }

  Future<void> _reject(JobOffer offer) async {
    try {
      await ProviderAppScope.of(context).api.rejectOffer(offer.orderId);
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ProviderAppScope.of(context).isOnline;
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: FixGoSpacing.xl),
          children: [
            _FixerHeader(isOnline: isOnline, onToggle: _toggleOnline),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FixGoSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionCard(
                      icon: Icons.location_on,
                      title: 'งานเข้ามาใหม่ ใกล้คุณ',
                      trailing:
                          _offers.isEmpty ? null : '${_offers.length} งาน',
                      child: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(FixGoSpacing.lg),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _offers.isEmpty
                              ? _EmptyOffers(
                                  message: _error ??
                                      (isOnline
                                          ? 'ยังไม่มีงานเข้ามาตอนนี้ ระบบเช็กงานใหม่ทุก 10 วินาที'
                                          : 'เปิด "พร้อมรับงาน" ด้านบนเพื่อเริ่มรับงาน'),
                                )
                              : Column(
                                  children: [
                                    for (final (index, offer)
                                        in _offers.indexed) ...[
                                      if (index > 0) const Divider(height: 32),
                                      _OfferCard(
                                        offer: offer,
                                        onAccept: () => _accept(offer),
                                        onReject: () => _reject(offer),
                                      ),
                                    ],
                                  ],
                                ),
                    ),
                    const SizedBox(height: FixGoSpacing.md),
                    _SectionCard(
                      icon: Icons.route_outlined,
                      title: 'ความคืบหน้างาน',
                      actionLabel:
                          _activeJob == null ? null : 'ดูรายละเอียดงาน',
                      onAction: () => widget.onOpenTab?.call(1),
                      child: _JobProgress(order: _activeJob),
                    ),
                    const SizedBox(height: FixGoSpacing.md),
                    _SectionCard(
                      icon: Icons.insights_outlined,
                      title: 'สรุปผลงานวันนี้',
                      actionLabel: 'กระเป๋าเงิน',
                      onAction: () => widget.onOpenTab?.call(2),
                      child: _SummaryRow(summary: _summary),
                    ),
                    const SizedBox(height: FixGoSpacing.md),
                    _MainMenu(onOpenTab: widget.onOpenTab),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ตัวเลขสรุปวันนี้ คำนวณจากข้อมูลจริงเท่านั้น
/// - งานเสร็จวันนี้: ออเดอร์ของช่างที่ completedAt เป็นวันนี้
/// - รายได้วันนี้: รายได้สุทธิหลังหักค่าธรรมเนียมของงานที่ยืนยันการชำระวันนี้ ทั้งพร้อมเพย์และเงินสด
/// ไม่มี "เวลาออนไลน์" เพราะ backend ยังไม่เก็บประวัติเวลาออนไลน์
class _TodaySummary {
  const _TodaySummary({
    required this.completedToday,
    required this.earnedToday,
    required this.balance,
  });

  final int completedToday;
  final int earnedToday;
  final int balance;

  static bool _isToday(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  /// รายได้สุทธิของช่างจากรายการในกระเป๋า
  /// - ORDER_EARNING (พร้อมเพย์): ยอดที่เข้ากระเป๋า
  /// - COMMISSION_DUE (เงินสด): ช่างถือเงินสดเต็มจำนวน รายได้สุทธิ = ยอดงาน - ค่าธรรมเนียม
  static int _netEarning(WalletEntry entry, List<Order> orders) {
    switch (entry.type) {
      case 'ORDER_EARNING':
        return entry.amount;
      case 'COMMISSION_DUE':
        final order =
            orders.where((order) => order.id == entry.orderId).firstOrNull;
        if (order == null) return 0;
        return (order.priceFinal ?? order.priceEstimated) + entry.amount;
      default:
        return 0;
    }
  }

  factory _TodaySummary.from({
    required List<Order> orders,
    required List<WalletEntry> entries,
    required int balance,
  }) {
    return _TodaySummary(
      completedToday: orders
          .where(
            (order) =>
                order.status == OrderStatus.completed &&
                order.completedAt != null &&
                _isToday(order.completedAt!),
          )
          .length,
      earnedToday: entries
          .where((entry) => _isToday(entry.createdAt))
          .fold(0, (sum, entry) => sum + _netEarning(entry, orders)),
      balance: balance,
    );
  }
}

class _FixerHeader extends StatelessWidget {
  const _FixerHeader({required this.isOnline, required this.onToggle});

  final bool isOnline;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FixGoColors.navy, FixGoColors.accent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(fixerLogoAsset, height: 36),
                        ),
                        const SizedBox(width: 8),
                        const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: 'FixGo '),
                              TextSpan(
                                text: 'Fixer',
                                style: TextStyle(color: FixGoColors.lime),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'แอปสำหรับช่าง FixGo',
                      style: TextStyle(fontSize: 13, color: Color(0xFFC9DDD4)),
                    ),
                  ],
                ),
              ),
              _OnlineToggle(isOnline: isOnline, onToggle: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineToggle extends StatelessWidget {
  const _OnlineToggle({required this.isOnline, required this.onToggle});

  final bool isOnline;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: isOnline,
      label: 'สถานะพร้อมรับงาน',
      child: Material(
        color: isOnline ? const Color(0x33C7EE77) : const Color(0x1FFFFFFF),
        shape: StadiumBorder(
          side: BorderSide(
            color: isOnline ? FixGoColors.lime : const Color(0x66FFFFFF),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onToggle(!isOnline),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: isOnline ? FixGoColors.lime : const Color(0xFF9FB5AC),
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline ? 'พร้อมรับงาน' : 'ปิดรับงาน',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: isOnline,
                  onChanged: onToggle,
                  activeTrackColor: FixGoColors.lime,
                  activeThumbColor: FixGoColors.navy,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0x40FFFFFF),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        boxShadow: fixGoCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: FixGoColors.accent, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FixGoColors.textSecondary,
                  ),
                ),
              if (actionLabel != null)
                InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(FixGoRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Text(
                          actionLabel!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: FixGoColors.accent,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: FixGoColors.accent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyOffers extends StatelessWidget {
  const _EmptyOffers({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: FixGoColors.accentSoft,
        borderRadius: BorderRadius.circular(FixGoRadius.md),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 32,
            color: FixGoColors.accent,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: FixGoColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 4 ขั้นตอนหลักของงานตรงกับสถานะ backend ที่ลูกค้าเห็นในหน้าติดตามงานด้วย
class _JobProgress extends StatelessWidget {
  const _JobProgress({required this.order});

  final Order? order;

  static const _steps = [
    (icon: Icons.assignment_turned_in_outlined, label: 'รับงาน'),
    (icon: Icons.directions_car_outlined, label: 'เดินทาง'),
    (icon: Icons.build_outlined, label: 'กำลังซ่อม'),
    (icon: Icons.check_rounded, label: 'ปิดงาน'),
  ];

  int get _current {
    switch (order?.status) {
      case OrderStatus.matched:
        return 0;
      case OrderStatus.enRoute:
        return 1;
      case OrderStatus.inProgress:
        return 2;
      default:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final order = this.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order == null)
          const Text(
            'ยังไม่มีงานที่กำลังทำ',
            style: TextStyle(fontSize: 14, color: FixGoColors.textSecondary),
          )
        else
          Text(
            '${order.subServiceName ?? order.categoryName ?? 'งาน'} · '
            '${orderStatusLabel(order.status)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (index, step) in _steps.indexed) ...[
              if (index > 0)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 22),
                    color: index <= current
                        ? FixGoColors.accent
                        : FixGoColors.hairline,
                  ),
                ),
              Column(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < current
                          ? FixGoColors.accentSoft
                          : index == current
                              ? FixGoColors.accent
                              : FixGoColors.surface,
                      border: Border.all(
                        color: index <= current
                            ? FixGoColors.accent
                            : FixGoColors.hairline,
                      ),
                    ),
                    child: Icon(
                      index < current ? Icons.check_rounded : step.icon,
                      size: 20,
                      color: index == current
                          ? Colors.white
                          : index < current
                              ? FixGoColors.accent
                              : FixGoColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          index == current ? FontWeight.w800 : FontWeight.w500,
                      color: index <= current
                          ? FixGoColors.textPrimary
                          : FixGoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final _TodaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.task_alt_rounded,
            label: 'งานเสร็จวันนี้',
            value: summary == null ? '–' : '${summary.completedToday}',
            unit: 'งาน',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'รายได้วันนี้',
            value: summary == null ? '–' : formatSatang(summary.earnedToday),
            unit: 'ยืนยันแล้ว',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.savings_outlined,
            label: 'ยอดถอนได้',
            value: summary == null ? '–' : formatSatang(summary.balance),
            unit: 'คงเหลือ',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FixGoRadius.md),
        border: Border.all(color: FixGoColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 30,
            width: 30,
            decoration: const BoxDecoration(
              color: FixGoColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: FixGoColors.accent),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: FixGoColors.textSecondary,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: FixGoColors.navy,
              ),
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 11,
              color: FixGoColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MainMenu extends StatelessWidget {
  const _MainMenu({required this.onOpenTab});

  final ValueChanged<int>? onOpenTab;

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.build_circle_outlined, label: 'งานของฉัน', tab: 1),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: 'กระเป๋าเงิน',
        tab: 2
      ),
      (icon: Icons.person_outline, label: 'โปรไฟล์', tab: 3),
    ];
    return Row(
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: FixGoColors.background,
              borderRadius: BorderRadius.circular(FixGoRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(FixGoRadius.lg),
                onTap: () => onOpenTab?.call(item.tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    children: [
                      Icon(item.icon, color: FixGoColors.accent, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({
    required this.offer,
    required this.onAccept,
    required this.onReject,
  });

  final JobOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.offer.expiresAt.difference(DateTime.now());
    final expired = remaining.isNegative;
    final minutes = remaining.inMinutes.clamp(0, 99);
    final seconds = (remaining.inSeconds % 60).clamp(0, 59);

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.offer.subServiceName ??
                      widget.offer.categoryName ??
                      'งานซ่อม',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FixGoSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: expired ? FixGoColors.hairline : FixGoColors.accent,
                  borderRadius: BorderRadius.circular(FixGoRadius.pill),
                ),
                child: Text(
                  expired
                      ? 'หมดเวลา'
                      : 'เหลือ ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: expired ? FixGoColors.textPrimary : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FixGoSpacing.sm),
          Row(
            children: [
              const Icon(Icons.near_me_outlined,
                  size: 18, color: FixGoColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                  'ห่างจากคุณ ${widget.offer.distanceKm.toStringAsFixed(1)} กม.'),
            ],
          ),
          if (widget.offer.pickupAddress != null) ...[
            const SizedBox(height: FixGoSpacing.xs),
            Text(
              widget.offer.pickupAddress!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: FixGoSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FixGoColors.accentSoft,
              borderRadius: BorderRadius.circular(FixGoRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ราคาประเมินของงาน (ก่อนหักค่าธรรมเนียม)',
                  style: TextStyle(
                    fontSize: 12,
                    color: FixGoColors.textSecondary,
                  ),
                ),
                Text(
                  formatSatang(widget.offer.priceEstimated),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: FixGoColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FixGoSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: expired ? null : widget.onAccept,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('รับงาน'),
                ),
              ),
              const SizedBox(width: FixGoSpacing.sm),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: expired ? null : widget.onReject,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('ปฏิเสธ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
