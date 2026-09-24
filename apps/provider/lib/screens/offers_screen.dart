import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_state.dart';

/// งานที่ระบบเสนอให้ช่างเป็นชุด ช่างคนแรกที่กดรับจะได้งาน
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null) return;
    unawaited(_refresh());
    final state = ProviderAppScope.of(context);
    if (state.isOnline && !_restoredTrackingStarted) {
      _restoredTrackingStarted = true;
      unawaited(_startTrackingLocation());
    }
    // ดึงงานใหม่ทุก 10 วิ และให้ countdown เดินด้วย
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
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
      final offers = await state.api.listOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
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
      appBar: AppBar(
        title: const Text('งานที่เข้ามา'),
        actions: [
          Row(
            children: [
              Text(
                isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isOnline
                      ? FixGoColors.success
                      : FixGoColors.textSecondary,
                ),
              ),
              Switch(value: isOnline, onChanged: _toggleOnline),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _offers.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _error ??
                              (isOnline
                                  ? 'ยังไม่มีงานเข้ามาตอนนี้'
                                  : 'เปิดสถานะออนไลน์เพื่อเริ่มรับงาน'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(FixGoSpacing.md),
                    itemCount: _offers.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: FixGoSpacing.md),
                    itemBuilder: (context, index) => _OfferCard(
                      offer: _offers[index],
                      onAccept: () => _accept(_offers[index]),
                      onReject: () => _reject(_offers[index]),
                    ),
                  ),
      ),
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
            Text(
              formatSatang(widget.offer.priceEstimated),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: FixGoColors.navy,
              ),
            ),
            const SizedBox(height: FixGoSpacing.md),
            FixGoButton(
              label: 'รับงานนี้',
              onPressed: expired ? null : widget.onAccept,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            FixGoSecondaryButton(
              label: 'ปฏิเสธ',
              onPressed: expired ? null : widget.onReject,
            ),
          ],
        ),
      ),
    );
  }
}
