import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'booking/booking_flow.dart';
import 'inspection_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<ServiceCategory>>? _categoriesFuture;

  LocationResult? _location;
  bool _locationLoading = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // อ่าน InheritedWidget ใน initState ไม่ได้ ต้องทำที่นี่ และกันไม่ให้ยิงซ้ำทุกครั้งที่ rebuild
    _categoriesFuture ??= AppStateScope.of(context).api.listCategories();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });
    try {
      final result = await LocationService.getCurrentLocation();
      if (!mounted) return;
      setState(() => _location = result);
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() => _locationError = error.message);
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  void _startBooking({ServiceCategory? category}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingFlow(
          initialCategory: category,
          pickupLocation: _location,
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _categoriesFuture = AppStateScope.of(context).api.listCategories();
    });
    await Future.wait([_categoriesFuture!, _fetchLocation()]);
  }

  ServiceCategory? _findCategory(List<ServiceCategory> categories, String key) {
    for (final category in categories) {
      if (category.iconKey == key) return category;
    }
    return null;
  }

  void _startJumpStart(ServiceCategory? battery) {
    // กฎเดิม: เมนูจั๊มแบตต้องเข้าขั้นจองทันที ไม่ให้ผู้ใช้เลือกบริการย่อยซ้ำ
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingFlow(
          initialCategory: battery,
          pickupLocation: _location,
          initialSubServiceKeyword: battery == null ? null : 'จั๊ม',
        ),
      ),
    );
  }

  void _openInspection(ServiceCategory? inspection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InspectionDetailScreen(
          category: inspection,
          pickupLocation: _location,
        ),
      ),
    );
  }

  final _allServicesKey = GlobalKey();

  void _scrollToAllServices() {
    final target = _allServicesKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ServiceCategory>>(
          future: _categoriesFuture,
          builder: (context, snapshot) {
            final categories = snapshot.data ?? const <ServiceCategory>[];
            final inspection = _findCategory(categories, 'inspection');
            final battery = _findCategory(categories, 'battery');

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: FixGoSpacing.xl),
              children: [
                // หัวเขียวเข้ม + การ์ดเรียกช่างด่วนลอยทับ: ปุ่มฉุกเฉินต้องเด่นที่สุดบนจอ
                Stack(
                  children: [
                    const Positioned.fill(
                      bottom: 120,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: fixGoBrandGradient,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          _HomeHeader(
                            location: _location,
                            loading: _locationLoading,
                            error: _locationError,
                            onTap: _fetchLocation,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: FixGoSpacing.md,
                            ),
                            child: _EmergencyCallCard(
                              onTap: () => _startBooking(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FixGoSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FixGoSpacing.md,
                  ),
                  child: _HeroBanner(
                    onShowSteps: () => _showHowItWorks(context),
                  ),
                ),
                const SizedBox(height: FixGoSpacing.lg),
                _SectionHeader(
                  title: 'บริการยอดนิยม',
                  actionLabel: 'ดูทั้งหมด',
                  onAction: _scrollToAllServices,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FixGoSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, tile) in [
                        (
                          key: 'mechanic',
                          title: 'ช่างซ่อมรถ',
                          subtitle: 'ซ่อมถึงที่',
                        ),
                        (
                          key: 'battery',
                          title: 'จั๊มแบต',
                          subtitle: 'สตาร์ทไม่ติด',
                        ),
                        (
                          key: 'tire',
                          title: 'ยางรั่ว',
                          subtitle: 'ปะ/เปลี่ยนยาง',
                        ),
                        (
                          key: 'tow',
                          title: 'รถยก',
                          subtitle: 'ยกไปอู่',
                        ),
                      ].indexed) ...[
                        if (index > 0) const SizedBox(width: FixGoSpacing.sm),
                        Expanded(
                          child: _PopularServiceTile(
                            title: tile.title,
                            subtitle: tile.subtitle,
                            iconAsset: categoryIconAsset(tile.key),
                            onTap: tile.key == 'battery'
                                ? () => _startJumpStart(battery)
                                : () => _startBooking(
                                      category:
                                          _findCategory(categories, tile.key),
                                    ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: FixGoSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FixGoSpacing.md,
                  ),
                  child: _InspectionPromoCard(
                    category: inspection,
                    onTap: () => _openInspection(inspection),
                  ),
                ),
                const SizedBox(height: FixGoSpacing.lg),
                Padding(
                  key: _allServicesKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FixGoSpacing.md,
                  ),
                  child: _CategorySection(
                    snapshot: snapshot,
                    onRetry: _refresh,
                    onSelected: (category) {
                      if (category.iconKey == 'inspection') {
                        _openInspection(category);
                      } else if (category.iconKey == 'battery') {
                        _startJumpStart(category);
                      } else {
                        _startBooking(category: category);
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ขั้นตอนใช้งานจริงของระบบ (ตรงกับสถานะออเดอร์ใน backend)
void _showHowItWorks(BuildContext context) {
  const steps = [
    (
      icon: Icons.touch_app_outlined,
      title: 'เลือกบริการและประเภทรถ',
      body: 'เห็นราคาประเมินก่อนกดเรียก ระบบใช้ตำแหน่ง GPS ของคุณ',
    ),
    (
      icon: Icons.person_search_outlined,
      title: 'ระบบหาช่างที่ใกล้ที่สุด',
      body: 'ช่างที่ออนไลน์และอยู่ใกล้จะได้รับงานก่อน',
    ),
    (
      icon: Icons.request_quote_outlined,
      title: 'ช่างแจ้งราคาให้คุณยืนยัน',
      body: 'ช่างเริ่มซ่อมหลังคุณกดยืนยันราคาเท่านั้น',
    ),
    (
      icon: Icons.qr_code_2_rounded,
      title: 'ซ่อมเสร็จ ชำระเงินและให้คะแนน',
      body: 'สแกนพร้อมเพย์หรือจ่ายเงินสดกับช่าง แล้วให้คะแนนบริการ',
    ),
  ];
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ขั้นตอนบริการ FixGo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: FixGoSpacing.md),
            for (final (index, step) in steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: const BoxDecoration(
                        color: FixGoColors.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(step.icon, color: FixGoColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${step.title}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            step.body,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// หัวหน้าแรก: โลโก้ FixGo + ตำแหน่งปัจจุบัน (ข้อมูลจริงจาก GPS)
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.location,
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final LocationResult? location;
  final bool loading;
  final String? error;
  final VoidCallback onTap;

  String get _label {
    if (loading) return 'กำลังหาตำแหน่ง...';
    if (error != null) return 'แตะเพื่อเปิดตำแหน่ง';
    if (location == null) return 'แตะเพื่อหาตำแหน่ง';
    return location!.address ??
        '${location!.latitude.toStringAsFixed(4)}, ${location!.longitude.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FixGoSpacing.md,
        FixGoSpacing.md,
        FixGoSpacing.md,
        FixGoSpacing.lg,
      ),
      child: Row(
        children: [
          Image.asset(brandSymbolWhiteAsset, height: 34),
          const SizedBox(width: 8),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Fix', style: TextStyle(color: Colors.white)),
                TextSpan(
                  text: 'Go',
                  style: TextStyle(color: FixGoColors.lime),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: FixGoSpacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.white.withValues(alpha: 0.14),
                shape: const StadiumBorder(
                  side: BorderSide(color: Color(0x40FFFFFF)),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (loading)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(
                            error != null
                                ? Icons.location_off_outlined
                                : Icons.location_on,
                            size: 18,
                            color:
                                error != null ? FixGoColors.lime : Colors.white,
                          ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดเรียกช่างด่วน — องค์ประกอบที่เด่นที่สุดของหน้าจอ ปุ่มสูง 64 กดง่ายด้วยนิ้วโป้ง
class _EmergencyCallCard extends StatelessWidget {
  const _EmergencyCallCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29122821),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เรียกช่างด่วน',
            style: TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: FixGoColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'รถเสีย สตาร์ทไม่ติด ยางแตก เรียกช่างมาถึงที่',
            style: TextStyle(fontSize: 15, color: FixGoColors.textSecondary),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _CheckLabel('ช่างใกล้คุณ'),
              _CheckLabel('รู้ราคาก่อนซ่อม'),
              _CheckLabel('เรียกได้ 24 ชม.'),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: 'เรียกช่างด่วน',
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius:
                    BorderRadius.all(Radius.circular(FixGoRadius.pill)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x4D0B5F45),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  height: 64,
                  decoration: const BoxDecoration(gradient: fixGoBrandGradient),
                  child: InkWell(
                    onTap: onTap,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Container(
                          height: 48,
                          width: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_rounded,
                            color: FixGoColors.accent,
                            size: 26,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'เรียกช่างด่วน',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: FixGoColors.lime,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckLabel extends StatelessWidget {
  const _CheckLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 18, color: FixGoColors.jade),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// แบนเนอร์ภาพจริง: ภาพไม่มีข้อความในตัว ข้อความ/ปุ่มวาดด้วย Flutter บนพื้นเขียวฝั่งซ้าย
/// ใช้สัดส่วนเท่าภาพต้นฉบับ (1672×941) จึงไม่ถูกครอบ ใบหน้าและตัวรถเห็นครบทุกขนาดจอ
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onShowSteps});

  final VoidCallback onShowSteps;

  static const _aspect = 1672 / 941;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(FixGoRadius.lg),
      child: AspectRatio(
        aspectRatio: _aspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // ฝั่งซ้ายของภาพเป็นพื้นเขียวราว 40% ของความกว้าง ให้ข้อความอยู่ในโซนนี้
            final textWidth = width * 0.47;
            final scale = (width / 360).clamp(0.85, 1.4);
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/home_hero.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  semanticLabel: 'ช่าง FixGo ตรวจเครื่องยนต์ให้ลูกค้าข้างทาง',
                ),
                Positioned(
                  left: 16 * scale,
                  top: 14 * scale,
                  bottom: 14 * scale,
                  width: textWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'รถมีปัญหา\nให้ FixGo ช่วย',
                        style: TextStyle(
                          fontSize: 19 * scale,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4 * scale),
                      Text(
                        'ช่างมาถึงที่ แจ้งราคาก่อนซ่อม',
                        style: TextStyle(
                          fontSize: 12 * scale,
                          height: 1.35,
                          color: const Color(0xFFDDF3E7),
                        ),
                      ),
                      SizedBox(height: 10 * scale),
                      Material(
                        color: FixGoColors.lime,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: onShowSteps,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12 * scale,
                              vertical: 7 * scale,
                            ),
                            child: Text(
                              'ดูขั้นตอนบริการ',
                              style: TextStyle(
                                fontSize: 12.5 * scale,
                                fontWeight: FontWeight.w800,
                                color: FixGoColors.navy,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PopularServiceTile extends StatelessWidget {
  const _PopularServiceTile({
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String iconAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        boxShadow: fixGoCardShadow,
      ),
      child: Material(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FixGoRadius.lg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
            child: Column(
              children: [
                Image.asset(iconAsset, height: 52, width: 52),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: FixGoColors.textSecondary,
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

/// การ์ดตรวจรถมือสอง: ราคาและจำนวนจุดตรวจดึงจากระบบจริง ไม่ใช้ตัวเลขจากภาพ mockup
class _InspectionPromoCard extends StatefulWidget {
  const _InspectionPromoCard({required this.category, required this.onTap});

  final ServiceCategory? category;
  final VoidCallback onTap;

  @override
  State<_InspectionPromoCard> createState() => _InspectionPromoCardState();
}

class _InspectionPromoCardState extends State<_InspectionPromoCard> {
  Future<({int? price, int points})>? _future;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant _InspectionPromoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final category = widget.category;
    if (category == null || _loadedFor == category.id) return;
    _loadedFor = category.id;
    final api = AppStateScope.of(context).api;
    _future = () async {
      final results = await Future.wait([
        api.listSubServices(category.id),
        api.getInspectionChecklist(),
      ]);
      final subs = results[0] as List<SubService>;
      final checklist = results[1] as InspectionChecklist;
      return (
        price: subs.isEmpty ? null : subs.first.basePrice,
        points: checklist.totalItems,
      );
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({int? price, int points})>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FixGoRadius.lg),
            boxShadow: fixGoCardShadow,
          ),
          child: Material(
            color: FixGoColors.background,
            borderRadius: BorderRadius.circular(FixGoRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(FixGoRadius.lg),
              child: Padding(
                padding: const EdgeInsets.all(FixGoSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: FixGoColors.accentSoft,
                              borderRadius:
                                  BorderRadius.circular(FixGoRadius.pill),
                            ),
                            child: const Text(
                              'มั่นใจก่อนซื้อ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: FixGoColors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ตรวจรถมือสอง',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data == null
                                ? 'ช่างไปตรวจรถถึงที่ก่อนตัดสินใจซื้อ'
                                : 'ตรวจ ${data.points} รายการ พร้อมรูปหลักฐานและเกรดสรุป',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: FixGoColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: widget.onTap,
                            style: FilledButton.styleFrom(
                              backgroundColor: FixGoColors.accent,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontFamily: fixGoFontFamily,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('ดูรายละเอียด'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: FixGoSpacing.sm),
                    Column(
                      children: [
                        if (data?.price != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: FixGoColors.lime,
                              borderRadius:
                                  BorderRadius.circular(FixGoRadius.md),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'ราคาเดียวทุกประเภทรถ',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: FixGoColors.navy,
                                  ),
                                ),
                                Text(
                                  '฿${formatThousands(data!.price! ~/ 100)}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: FixGoColors.navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Image.asset(categoryIconAsset('inspection'),
                            height: 84),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.snapshot,
    required this.onSelected,
    required this.onRetry,
  });

  final AsyncSnapshot<List<ServiceCategory>> snapshot;
  final Future<void> Function() onRetry;
  final ValueChanged<ServiceCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (snapshot.connectionState == ConnectionState.waiting) {
      content = const Padding(
        padding: EdgeInsets.all(FixGoSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (snapshot.hasError) {
      content = Padding(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        child: Column(
          children: [
            const Text(
              'โหลดรายการบริการไม่สำเร็จ',
              style: TextStyle(color: FixGoColors.error),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    } else {
      final categories = snapshot.data ?? const [];
      content = GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: FixGoSpacing.md,
          crossAxisSpacing: FixGoSpacing.xs,
          childAspectRatio: 0.72,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryTile(
            category: category,
            onTap: () => onSelected(category),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      decoration: BoxDecoration(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        boxShadow: fixGoCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'หมวดหมู่บริการ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: FixGoSpacing.md),
          content,
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FixGoRadius.md),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FixGoColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            // ไอคอน 3D สีในตัว วางบนพื้นเทาอ่อนให้ขนาดดูเท่ากันทุกช่อง
            child: Image.asset(categoryIconAsset(category.iconKey)),
          ),
          const SizedBox(height: 6),
          // ไอคอนต้องมี label เสมอ กลุ่มผู้ใช้ไม่มีความรู้เรื่องรถ ต้องไม่ต้องตีความเอง
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }
}
