import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';

/// กระเป๋าเงินช่าง — ยอดคงเหลือหลังหักค่าธรรมเนียม 35% แล้ว กดขอเบิกได้ตลอดเวลา
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  int? _balance;
  List<WalletEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_balance == null && _loading) {
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final api = ProviderAppScope.of(context).api;
      final balance = await api.getWalletBalance();
      final entries = await api.listWalletEntries();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _entries = entries;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _withdraw() async {
    final balance = _balance ?? 0;
    if (balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มียอดเงินให้เบิก')),
      );
      return;
    }

    final controller = TextEditingController(
      text: (balance / 100).toStringAsFixed(0),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ขอเบิกเงิน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ยอดคงเหลือ ${formatSatang(balance)}'),
            const SizedBox(height: FixGoSpacing.md),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '฿ ',
                labelText: 'จำนวนที่ต้องการเบิก',
              ),
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
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final baht = double.tryParse(controller.text.trim());
    if (baht == null || baht <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('จำนวนเงินไม่ถูกต้อง')),
      );
      return;
    }

    try {
      await ProviderAppScope.of(context)
          .api
          .requestWithdrawal(bahtToSatang(baht));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งคำขอแล้ว ทีมงานจะโอนให้เร็วที่สุด')),
      );
      await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: const Text('กระเป๋าเงิน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(FixGoSpacing.md),
                children: [
                  Container(
                    padding: const EdgeInsets.all(FixGoSpacing.lg),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(FixGoRadius.lg),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2A3242), FixGoColors.navy],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ยอดคงเหลือ',
                          style: TextStyle(color: Color(0xFFCBD5E1)),
                        ),
                        const SizedBox(height: FixGoSpacing.xs),
                        Text(
                          formatSatang(_balance ?? 0),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF9A55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: FixGoSpacing.md),
                    Text(_error!,
                        style: const TextStyle(color: FixGoColors.error)),
                  ],
                  const SizedBox(height: FixGoSpacing.md),
                  FixGoButton(
                    label: 'ขอเบิกเงิน',
                    icon: Icons.account_balance_wallet_outlined,
                    onPressed: _withdraw,
                  ),
                  const SizedBox(height: FixGoSpacing.lg),
                  const Text(
                    'รายการล่าสุด',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: FixGoSpacing.sm),
                  if (_entries.isEmpty)
                    Text(
                      'ยังไม่มีรายการ',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    for (final entry in _entries)
                      Card(
                        margin: const EdgeInsets.only(bottom: FixGoSpacing.sm),
                        child: ListTile(
                          title: Text(entry.memo ?? entry.type),
                          subtitle: Text(
                            '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}',
                          ),
                          trailing: Text(
                            '${entry.amount >= 0 ? '+' : '-'}${formatSatang(entry.amount.abs())}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: entry.amount >= 0
                                  ? FixGoColors.success
                                  : FixGoColors.error,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
