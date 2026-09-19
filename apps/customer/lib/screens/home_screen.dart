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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // อ่าน InheritedWidget ใน initState ไม่ได้ ต้องทำที่นี่ และกันไม่ให้ยิงซ้ำทุกครั้งที่ rebuild
    _categoriesFuture ??= AppStateScope.of(context).api.listCategories();
  }

  void _startBooking({ServiceCategory? category}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingFlow(initialCategory: category),
      ),
    );
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
          child: ListView(
            padding: const EdgeInsets.only(bottom: FixGoSpacing.xl),
            children: [
              const _LocationHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FixGoSpacing.md,
                ),
                child: _EmergencyHeroCard(onTap: () => _startBooking()),
              ),
              const SizedBox(height: FixGoSpacing.lg),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: FixGoSpacing.md),
                child: Text(
                  'หมวดหมู่บริการ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: FixGoSpacing.md),
              FutureBuilder<List<ServiceCategory>>(
                future: _categoriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(FixGoSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(FixGoSpacing.md),
                      child: Text(
                        'โหลดรายการบริการไม่สำเร็จ: ${snapshot.error}',
                        style: const TextStyle(color: FixGoColors.error),
                      ),
                    );
                  }

                  final categories = snapshot.data ?? const [];
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FixGoSpacing.md,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: FixGoSpacing.md,
                      crossAxisSpacing: FixGoSpacing.sm,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _CategoryTile(
                        category: category,
                        onTap: () => _startBooking(category: category),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            // BMW ใช้มุมเหลี่ยมคมทุกจุด ไม่มีวงกลม
            color: FixGoColors.accent,
            child: const Icon(Icons.location_on, color: Colors.white),
          ),
          const SizedBox(width: FixGoSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ตำแหน่งของคุณ',
                  style: TextStyle(
                    fontSize: 12,
                    color: FixGoColors.textSecondary,
                  ),
                ),
                Text(
                  'เลือกตำแหน่งของคุณ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_down),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(FixGoSpacing.lg),
        // BMW ใช้มุมเหลี่ยมคมทุกจุด ไม่มีมุมมน
        color: FixGoColors.navy,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FixGoSpacing.sm,
                      vertical: FixGoSpacing.xs,
                    ),
                    color: FixGoColors.accent,
                    child: const Text(
                      'แนะนำ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: FixGoSpacing.sm),
                  const Text(
                    'เรียกช่างฉุกเฉิน',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: FixGoSpacing.xs),
                  const Text(
                    'ซ่อมรถยนต์นอกสถานที่ ช่างใกล้คุณที่สุด',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FixGoSpacing.md),
            const Icon(
              Icons.car_repair,
              size: 56,
              color: FixGoColors.accent,
            ),
          ],
        ),
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
      child: Container(
        // BMW ใช้มุมเหลี่ยมคมทุกจุด ไม่มีเงา แยกพื้นที่ด้วยเส้นขอบบางแทน
        decoration: BoxDecoration(
          color: FixGoColors.background,
          border: Border.all(color: FixGoColors.hairline),
        ),
        padding: const EdgeInsets.symmetric(vertical: FixGoSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ไอคอน 3D สีสันในตัวเอง ไม่ต้องมีพื้นหลังสีอีก (Microsoft Fluent Emoji, MIT)
            Image.asset(
              categoryIconAsset(category.iconKey),
              height: 48,
              width: 48,
            ),
            const SizedBox(height: FixGoSpacing.xs),
            // ไอคอนต้องมี label เสมอ กลุ่มผู้ใช้ไม่มีความรู้เรื่องรถ ต้องไม่ต้องตีความเอง
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
