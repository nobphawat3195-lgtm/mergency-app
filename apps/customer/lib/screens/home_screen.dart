import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'booking/booking_flow.dart';

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

  ServiceCategory? _findCategory(List<ServiceCategory> categories, String key) {
    for (final category in categories) {
      if (category.iconKey == key) return category;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _categoriesFuture =
                  AppStateScope.of(context).api.listCategories();
            });
            await _categoriesFuture;
          },
          child: FutureBuilder<List<ServiceCategory>>(
            future: _categoriesFuture,
            builder: (context, snapshot) {
              final categories = snapshot.data ?? const <ServiceCategory>[];
              final tow = _findCategory(categories, 'tow');
              final battery = _findCategory(categories, 'battery');

              return ListView(
                padding: const EdgeInsets.only(bottom: FixGoSpacing.xl),
                children: [
                  _LocationHeader(
                    location: _location,
                    loading: _locationLoading,
                    error: _locationError,
                    onTap: _fetchLocation,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FixGoSpacing.md,
                    ),
                    // ปุ่มฉุกเฉินต้องใหญ่ที่สุดและอยู่ตำแหน่งที่นิ้วโป้งกดถึงง่าย
                    // ผู้ใช้ที่ตกใจไม่ต้องเลือกหมวดก่อน กดแล้วเข้า wizard ได้ทันที
                    child: SizedBox(
                      height: 236,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 11,
                            child: _EmergencyHeroCard(
                              onTap: () => _startBooking(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 10,
                            child: Column(
                              children: [
                                Expanded(
                                  child: _QuickServiceCard(
                                    title: 'รถสไลด์/รถยก',
                                    subtitle: 'ยกรถไปอู่',
                                    iconAsset: categoryIconAsset('tow'),
                                    onTap: () => _startBooking(category: tow),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _QuickServiceCard(
                                    title: 'แบตหมด',
                                    subtitle: 'สตาร์ทไม่ติด',
                                    iconAsset: categoryIconAsset('battery'),
                                    onTap: () =>
                                        _startBooking(category: battery),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FixGoSpacing.lg),
                  const _PromoCarousel(),
                  const SizedBox(height: FixGoSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FixGoSpacing.md,
                    ),
                    child: _CategorySection(
                      snapshot: snapshot,
                      onSelected: (category) =>
                          _startBooking(category: category),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({
    required this.location,
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final LocationResult? location;
  final bool loading;
  final String? error;
  final VoidCallback onTap;

  String get _subtitle {
    if (loading) return 'กำลังค้นหาตำแหน่ง...';
    if (error != null) return error!;
    if (location == null) return 'แตะเพื่อค้นหาตำแหน่งของคุณ';
    return location!.address ??
        '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FixGoSpacing.md,
        FixGoSpacing.sm,
        FixGoSpacing.md,
        FixGoSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(FixGoRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: FixGoSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: error != null
                            ? FixGoColors.error
                            : FixGoColors.accent,
                      ),
                      child: loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.location_on_outlined,
                              color: Colors.white,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ตำแหน่งของคุณ',
                            style: TextStyle(
                              fontSize: 12,
                              color: FixGoColors.textSecondary,
                            ),
                          ),
                          Text(
                            _subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: error != null
                                  ? FixGoColors.error
                                  : FixGoColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: FixGoColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: FixGoSpacing.sm),
          const _Support24Badge(),
        ],
      ),
    );
  }
}

/// ป้าย "24 ชม." มุมขวาบน ย้ำว่าเรียกได้ตลอดเวลา
class _Support24Badge extends StatelessWidget {
  const _Support24Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(FixGoRadius.pill),
        boxShadow: fixGoCardShadow,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: FixGoColors.success),
          SizedBox(width: 6),
          Text(
            '24 ชม.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmergencyHeroCard extends StatelessWidget {
  const _EmergencyHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FixGoRadius.lg),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8A3D), FixGoColors.accent, Color(0xFFE0500C)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40F26B1D),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FixGoRadius.lg),
          child: Stack(
            children: [
              Positioned(
                right: -6,
                bottom: 34,
                child: Image.asset(emergencyIconAsset, height: 92),
              ),
              Padding(
                padding: const EdgeInsets.all(FixGoSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(FixGoRadius.pill),
                      ),
                      child: const Text(
                        'ด่วน 24 ชม.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'เรียกช่าง\nฉุกเฉิน',
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ช่างใกล้คุณ\nซ่อมถึงที่',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFFFFE6D6),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(FixGoRadius.pill),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'เรียกเลย',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: FixGoColors.accentActive,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: FixGoColors.accentActive,
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
}

class _QuickServiceCard extends StatelessWidget {
  const _QuickServiceCard({
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
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: FixGoColors.background,
          borderRadius: BorderRadius.circular(FixGoRadius.lg),
          boxShadow: fixGoCardShadow,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FixGoRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Image.asset(iconAsset, height: 52, width: 52),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: FixGoColors.textSecondary,
                        ),
                      ),
                    ],
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

/// แบนเนอร์เลื่อนได้ใต้การ์ดด่วน — ใช้สื่อจุดขายหลัก ไม่ใช่โฆษณาภายนอก
class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel();

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  static const _slides = [
    (
      title: 'รถเสีย ไม่ต้องรอ',
      body: 'ช่างใกล้คุณ ไปถึงไว\nบริการทั่วถึง 24 ชั่วโมง',
      icon: technicianIconAsset,
    ),
    (
      title: 'รู้ราคาก่อนเรียก',
      body: 'ช่างแจ้งราคาจริงให้ยืนยัน\nก่อนเริ่มซ่อมทุกครั้ง',
      icon: 'packages/fixgo_core/assets/icons/inspection.png',
    ),
  ];

  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 132,
          child: PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FixGoRadius.lg),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A3242), FixGoColors.navy],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slide.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFF9A55),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              slide.body,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Color(0xFFD5DAE3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Image.asset(slide.icon, height: 92),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < _slides.length; index++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                width: index == _page ? 20 : 6,
                decoration: BoxDecoration(
                  color: index == _page
                      ? FixGoColors.accent
                      : const Color(0xFFD5D8DE),
                  borderRadius: BorderRadius.circular(FixGoRadius.pill),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.snapshot, required this.onSelected});

  final AsyncSnapshot<List<ServiceCategory>> snapshot;
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
      content = const Padding(
        padding: EdgeInsets.all(FixGoSpacing.md),
        child: Text(
          'โหลดรายการบริการไม่สำเร็จ ดึงหน้าจอลงเพื่อลองใหม่',
          style: TextStyle(color: FixGoColors.error),
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
