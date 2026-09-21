import 'package:flutter/material.dart';

const _spriteAsset =
    'packages/fixgo_core/assets/icons/mechnow-service-icons.jpeg';

/// ไอคอนบริการ MechNow ชุดน้ำเงิน–ส้มจากภาพต้นแบบเดียวกัน
/// เพื่อให้ทุกหมวดมีสัดส่วน แสง และสไตล์ภาพที่สม่ำเสมอ
class CategoryIconArt extends StatelessWidget {
  const CategoryIconArt({
    super.key,
    required this.iconKey,
    this.size = 58,
  });

  final String iconKey;
  final double size;

  (int, int) get _cell => switch (iconKey) {
        'mechanic' => (2, 2),
        'electrical' => (1, 2),
        'battery' => (1, 0),
        'tire' => (2, 0),
        'key' => (3, 0),
        'tow' => (0, 2),
        'inspection' => (0, 0),
        _ => (3, 2),
      };

  @override
  Widget build(BuildContext context) {
    final (column, row) = _cell;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -column * size,
              top: -row * size,
              width: size * 4,
              height: size * 3,
              child: Image.asset(
                _spriteAsset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
