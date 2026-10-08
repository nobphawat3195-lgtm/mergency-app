import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'order_tracking_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  Future<List<Order>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppStateScope.of(context).api.listMyOrders();
  }

  Future<void> _reload() async {
    setState(() {
      _future = AppStateScope.of(context).api.listMyOrders();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: const Text('รายการของฉัน')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncStateView<List<Order>>(
          future: _future,
          onRetry: _reload,
          scrollable: true,
          loading: const SkeletonList(),
          isEmpty: (orders) => orders.isEmpty,
          empty: const EmptyStateView(
            icon: Icons.receipt_long_outlined,
            title: 'ยังไม่มีงาน',
            message: 'กดเรียกช่างได้ที่หน้าแรก งานที่เรียกจะแสดงที่นี่',
          ),
          builder: (context, orders) {
            return ListView.separated(
              padding: const EdgeInsets.all(FixGoSpacing.md),
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: FixGoSpacing.sm),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: FixGoSpacing.md,
                      vertical: FixGoSpacing.sm,
                    ),
                    title: Text(
                      order.subServiceName ?? order.categoryName ?? 'บริการ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: FixGoSpacing.xs),
                      child: Row(
                        children: [
                          OrderStatusChip(status: order.status),
                          const SizedBox(width: FixGoSpacing.sm),
                          Flexible(
                            child: Text(
                              order.orderNo,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Text(
                      formatSatang(order.priceFinal ?? order.priceEstimated),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderTrackingScreen(orderId: order.id),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
