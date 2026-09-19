import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';

/// งานที่ช่างรับไว้แล้ว พร้อมปุ่มอัปเดตสถานะทีละขั้น
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  Future<List<Order>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ProviderAppScope.of(context).api.listAssignedOrders();
  }

  Future<void> _reload() async {
    setState(() {
      _future = ProviderAppScope.of(context).api.listAssignedOrders();
    });
    await _future;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _complete(Order order) async {
    final controller = TextEditingController(
      text: (order.priceEstimated / 100).toStringAsFixed(0),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ปิดงาน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('กรอกราคาสุดท้ายที่ตกลงกับลูกค้า (บาท)'),
            const SizedBox(height: FixGoSpacing.md),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(prefixText: '฿ '),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ปิดงาน'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final baht = double.tryParse(controller.text.trim());
    if (baht == null || baht < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรอกราคาไม่ถูกต้อง')),
      );
      return;
    }

    await _run(
      () => ProviderAppScope.of(context)
          .api
          .completeJob(order.id, bahtToSatang(baht)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: const Text('งานของฉัน')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Order>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = snapshot.data ?? const <Order>[];
            if (orders.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      'ยังไม่มีงานที่รับไว้',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(FixGoSpacing.md),
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: FixGoSpacing.sm),
              itemBuilder: (context, index) {
                final order = orders[index];
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
                                order.subServiceName ??
                                    order.categoryName ??
                                    'งานซ่อม',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              formatSatang(
                                order.priceFinal ?? order.priceEstimated,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: FixGoSpacing.xs),
                        Text(
                          '${order.orderNo} · ${orderStatusLabel(order.status)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: FixGoSpacing.md),
                        if (order.status == OrderStatus.matched)
                          FixGoButton(
                            label: 'เริ่มเดินทาง',
                            icon: Icons.directions_car,
                            onPressed: () => _run(
                              () => ProviderAppScope.of(context)
                                  .api
                                  .markEnRoute(order.id),
                            ),
                          )
                        else if (order.status == OrderStatus.enRoute)
                          FixGoButton(
                            label: 'ถึงหน้างาน เริ่มซ่อม',
                            icon: Icons.build,
                            onPressed: () => _run(
                              () => ProviderAppScope.of(context)
                                  .api
                                  .startJob(order.id),
                            ),
                          )
                        else if (order.status == OrderStatus.inProgress)
                          FixGoButton(
                            label: 'ปิดงาน',
                            icon: Icons.check_circle_outline,
                            onPressed: () => _complete(order),
                          ),
                      ],
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
