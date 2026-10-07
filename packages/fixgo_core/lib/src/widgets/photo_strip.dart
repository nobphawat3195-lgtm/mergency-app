import 'package:flutter/material.dart';

import '../theme.dart';

/// แถวรูปย่อเลื่อนแนวนอน แตะเพื่อดูเต็มจอ ถ้าส่ง [onRemove] จะมีปุ่มลบมุมรูป
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.urls,
    this.label,
    this.size = 72,
    this.onRemove,
  });

  final List<String> urls;
  final String? label;
  final double size;
  final ValueChanged<int>? onRemove;

  static void open(BuildContext context, String url) {
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
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: FixGoSpacing.xs),
        ],
        SizedBox(
          height: size,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: FixGoSpacing.xs),
            itemBuilder: (context, index) => Stack(
              children: [
                GestureDetector(
                  onTap: () => open(context, urls[index]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FixGoRadius.sm),
                    child: Image.network(
                      urls[index],
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      semanticLabel: 'รูปที่ ${index + 1} แตะเพื่อดูเต็มจอ',
                      errorBuilder: (_, __, ___) => Container(
                        width: size,
                        height: size,
                        color: FixGoColors.accentSoft,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
                if (onRemove != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onRemove!(index),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                            semanticLabel: 'ลบรูป',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
