import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// ป้ายสถานะงานแบบสี ผู้ใช้กวาดตาดูรายการแล้วรู้ทันทีว่างานไหนยังค้าง
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  Color get _color {
    switch (status) {
      case OrderStatus.completed:
        return FixGoColors.success;
      case OrderStatus.cancelled:
        return FixGoColors.textSecondary;
      case OrderStatus.noMatch:
        return FixGoColors.error;
      case OrderStatus.created:
      case OrderStatus.searching:
        return FixGoColors.warning;
      case OrderStatus.matched:
      case OrderStatus.enRoute:
      case OrderStatus.inProgress:
        return FixGoColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FixGoRadius.pill),
      ),
      child: Text(
        orderStatusLabel(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
