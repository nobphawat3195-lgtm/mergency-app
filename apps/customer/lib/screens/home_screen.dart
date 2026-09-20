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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: FixGoSpacing.xl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FixGoSpacing.md,
                      FixGoSpacing.md,
                      FixGoSpacing.md,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandHeader(),
                        const SizedBox(height: FixGoSpacing.md),
                        _LocationCard(
                          location: _location,
                          loading: _locationLoading,
                          error: _locationError,
                          onTap: _fetchLocation,
                        ),
                        const SizedBox(height: FixGoSpacing.md),
                        _EmergencyHeroCard(onTap: () => _startBooking()),
                        const SizedBox(height: FixGoSpacing.md),
                        const _TrustStrip(),
                        const SizedBox(height: FixGoSpacing.lg),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'เลือกบริการที่ต้องการ',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'แจ้งอาการและแชร์ตำแหน่งให้ช่างใกล้คุณ',
                                    style: TextStyle(
                                      color: FixGoColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _startBooking(),
                              child: const Text('ดูทั้งหมด'),
                            ),
                          ],
                        ),
                        const SizedBox(height: FixGoSpacing.md),
                        FutureBuilder<List<ServiceCategory>>(
                          future: _categoriesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(FixGoSpacing.xl),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return _LoadError(onRetry: _refresh);
                            }

                            final categories = snapshot.data ?? const [];
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 760
                                    ? 4
                                    : constraints.maxWidth >= 520
                                        ? 3
                                        : 2;
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisSpacing: FixGoSpacing.sm,
                                    crossAxisSpacing: FixGoSpacing.sm,
                                    childAspectRatio: 1.16,
                                  ),
                                  itemCount: categories.length,
                                  itemBuilder: (context, index) {
                                    final category = categories[index];
                                    return _CategoryTile(
                                      category: category,
                                      onTap: () =>
                                          _startBooking(category: category),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [FixGoColors.brandBlue, FixGoColors.navy],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white),
        ),
        const SizedBox(width: FixGoSpacing.sm),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FixGo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: FixGoColors.navy,
                ),
              ),
              Text(
                'Roadside assistance',
                style: TextStyle(
                  fontSize: 11,
                  color: FixGoColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF8F2),
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Row(
            children: [
              Icon(Icons.circle, size: 8, color: FixGoColors.success),
              SizedBox(width: 6),
              Text(
                'พร้อมช่วย 24 ชม.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: FixGoColors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
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
    if (location == null) return 'แตะเพื่อแชร์ตำแหน่งของคุณ';
    return location!.address ??
        '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: error != null
                      ? const Color(0xFFFFE9EC)
                      : const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.near_me_rounded,
                        color: error != null
                            ? FixGoColors.error
                            : FixGoColors.brandBlue,
                      ),
              ),
              const SizedBox(width: FixGoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'จุดที่ต้องการความช่วยเหลือ',
                      style: TextStyle(
                        fontSize: 12,
                        color: FixGoColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
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
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [FixGoColors.navy, Color(0xFF153F75)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: FixGoColors.navy.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FixGoSpacing.lg),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รถมีปัญหาอยู่ใช่ไหม?',
                        style: TextStyle(
                          color: Color(0xFFBFD2F0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'เรียกช่างใกล้คุณ\nได้ทันที',
                        style: TextStyle(
                          fontSize: 27,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: FixGoSpacing.md),
                      _HeroAction(),
                    ],
                  ),
                ),
                const SizedBox(width: FixGoSpacing.md),
                Container(
                  height: 94,
                  width: 94,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Icon(
                    Icons.car_repair_rounded,
                    size: 52,
                    color: FixGoColors.accent,
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

class _HeroAction extends StatelessWidget {
  const _HeroAction();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FixGoColors.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'เริ่มเรียกช่าง',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
        ],
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: FixGoSpacing.sm,
      children: [
        _TrustItem(icon: Icons.verified_user_outlined, label: 'ตรวจสอบช่าง'),
        _TrustItem(icon: Icons.location_searching, label: 'ติดตามตำแหน่ง'),
        _TrustItem(icon: Icons.price_check_outlined, label: 'ยืนยันราคาก่อน'),
      ],
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: FixGoColors.success),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: FixGoColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FixGoSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: FixGoColors.surface,
                  borderRadius: BorderRadius.circular(17),
                ),
                padding: const EdgeInsets.all(7),
                child: Image.asset(categoryIconAsset(category.iconKey)),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: FixGoColors.textSecondary,
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, color: FixGoColors.error),
            const SizedBox(height: FixGoSpacing.sm),
            const Text('โหลดรายการบริการไม่สำเร็จ'),
            TextButton(onPressed: onRetry, child: const Text('ลองอีกครั้ง')),
          ],
        ),
      ),
    );
  }
}
