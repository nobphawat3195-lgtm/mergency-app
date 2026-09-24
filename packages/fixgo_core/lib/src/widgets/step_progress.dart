import 'package:flutter/material.dart';

import '../theme.dart';

/// แถบบอกขั้นตอนของ booking wizard
/// ผู้ใช้ต้องเห็นตลอดว่าอยู่ขั้นไหนและเหลืออีกกี่ขั้น
class StepProgress extends StatelessWidget {
  const StepProgress({
    super.key,
    required this.labels,
    required this.currentIndex,
  });

  final List<String> labels;

  /// เริ่มจาก 0
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FixGoSpacing.md,
        vertical: FixGoSpacing.md,
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: index <= currentIndex
                        ? FixGoColors.accent
                        : FixGoColors.hairline,
                    borderRadius: BorderRadius.circular(FixGoRadius.pill),
                  ),
                ),
              ),
            _StepDot(
              label: labels[index],
              index: index,
              currentIndex: currentIndex,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.index,
    required this.currentIndex,
  });

  final String label;
  final int index;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final isDone = index < currentIndex;
    final isCurrent = index == currentIndex;
    final isActive = isDone || isCurrent;

    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? FixGoColors.accent : FixGoColors.hairline,
              boxShadow: isCurrent
                  ? const [
                      BoxShadow(
                        color: Color(0x40F26B1D),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: isDone
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          isActive ? Colors.white : FixGoColors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(height: FixGoSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? FixGoColors.navy : FixGoColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
