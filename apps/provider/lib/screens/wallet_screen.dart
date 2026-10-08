import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'payout_info_form.dart';
import 'wallet_debt_card.dart';

/// กระเป๋าเงินช่าง — ยอดคงเหลือหลังหักค่าบริการแพลตฟอร์มแล้ว กดขอเบิกได้ตลอดเวลา
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.active = true});

  /// แท็บนี้กำลังแสดงอยู่หรือไม่ เปิดแท็บเมื่อไหร่โหลดยอดล่าสุดทันที
  final bool active;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  int? _balance;
  WalletDebt? _debt;
  List<WalletEntry> _entries = const [];
  bool _loading = true;
  Object? _error;
  bool _withdrawing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_balance == null && _loading) {
      _reload();
    }
  }

  @override
  void didUpdateWidget(WalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  Future<void> _reload() async {
    try {
      final api = ProviderAppScope.of(context).api;
      final balance = await api.getWalletBalance();
      final entries = await api.listWalletEntries();
      // ยอดค้างเป็นข้อมูลเสริม โหลดไม่ได้ก็ยังแสดงกระเป๋าเงินตามปกติ
      final debt =
          await api.getWalletDebt().then<WalletDebt?>((d) => d).catchError(
                (_) => null,
                test: (error) => error is ApiException,
              );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _debt = debt;
        _entries = entries;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _withdraw() async {
    if (_withdrawing) return;
    setState(() => _withdrawing = true);
    try {
      await _requestWithdrawal();
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  Future<void> _requestWithdrawal() async {
    final balance = _balance ?? 0;
    if (balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มียอดเงินให้เบิก')),
      );
      return;
    }

    // ยังไม่มีบัญชีรับเงิน: เปิดฟอร์มให้กรอกก่อน แล้วค่อยขอเบิกต่อ
    final api = ProviderAppScope.of(context).api;
    try {
      final profile = await api.getProviderProfile();
      if (!mounted) return;
      if (!hasPayoutInfo(profile)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรอกข้อมูลรับเงินก่อนขอเบิก')),
        );
        final saved =
            await showPayoutInfoForm(context, api: api, profile: profile);
        if (!saved || !mounted) return;
      }
    } catch (error) {
      if (!mounted) return;
      showResultSnackBar(context, error: error);
      return;
    }
    if (!mounted) return;

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
    } catch (error) {
      if (!mounted) return;
      showResultSnackBar(context, error: error);
    }
  }

  /// รายการเบิกเงินบอกสถานะตามที่แอดมินทำ ไม่ใช่แค่ "กันยอด"
  String _entryTitle(WalletEntry entry) {
    if (entry.type == 'WITHDRAWAL') {
      return switch (entry.withdrawalStatus) {
        'TRANSFERRED' => 'เบิกเงิน · โอนแล้ว',
        'REJECTED' => 'เบิกเงิน · ไม่อนุมัติ',
        'REQUESTED' => 'เบิกเงิน · รอโอน',
        _ => entry.memo ?? 'เบิกเงิน',
      };
    }
    return entry.memo ?? entry.type;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.surface,
      appBar: AppBar(title: const Text('กระเป๋าเงิน')),
      body: _loading
          ? const LoadingStateView(message: 'กำลังโหลดกระเป๋าเงิน')
          // โหลดครั้งแรกไม่สำเร็จ: ห้ามโชว์ยอด ฿0 ให้เข้าใจผิด
          : _balance == null && _error != null
              ? ErrorStateView(
                  error: _error,
                  title: 'โหลดกระเป๋าเงินไม่สำเร็จ',
                  onRetry: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    unawaited(_reload());
                  },
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(FixGoSpacing.md),
                    children: [
                      // มีข้อมูลเก่าแต่โหลดใหม่ไม่ได้: แสดงของเดิมพร้อมบอกว่าอาจไม่ใช่ล่าสุด
                      if (_error != null) ...[
                        StaleDataBanner(error: _error, onRetry: _reload),
                        const SizedBox(height: FixGoSpacing.md),
                      ],
                      Container(
                        padding: const EdgeInsets.all(FixGoSpacing.lg),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(FixGoRadius.lg),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1D3F33), FixGoColors.navy],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ยอดติดลบ = ค่าบริการที่ค้างจากงานเงินสด แสดงเป็นยอดค้างสีแดง
                                  Text(
                                    (_balance ?? 0) < 0
                                        ? 'ยอดติดลบ (ค่าบริการค้าง)'
                                        : 'ยอดคงเหลือ',
                                    style: const TextStyle(
                                        color: Color(0xFFC9DDD4)),
                                  ),
                                  const SizedBox(height: FixGoSpacing.xs),
                                  Text(
                                    (_balance ?? 0) < 0
                                        ? '-${formatSatang(-_balance!)}'
                                        : formatSatang(_balance ?? 0),
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      color: (_balance ?? 0) < 0
                                          ? const Color(0xFFFFB4A8)
                                          : const Color(0xFFC7EE77),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(uiIconMoneyBag, width: 64, height: 64),
                          ],
                        ),
                      ),
                      if ((_debt?.owed ?? 0) > 0) ...[
                        const SizedBox(height: FixGoSpacing.md),
                        WalletDebtCard(
                          debt: _debt!,
                          api: ProviderAppScope.of(context).api,
                          onChanged: _reload,
                        ),
                      ],
                      if ((_balance ?? 0) > 0) ...[
                        const SizedBox(height: FixGoSpacing.md),
                        FixGoButton(
                          label: 'ขอเบิกเงิน',
                          icon: Icons.account_balance_wallet_outlined,
                          loading: _withdrawing,
                          onPressed: _withdraw,
                        ),
                      ],
                      const SizedBox(height: FixGoSpacing.lg),
                      const Text(
                        'รายการล่าสุด',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: FixGoSpacing.sm),
                      if (_entries.isEmpty)
                        Text(
                          'ยังไม่มีรายการ รายได้จากงานที่ปิดแล้วจะแสดงที่นี่',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        for (final entry in _entries)
                          Card(
                            margin:
                                const EdgeInsets.only(bottom: FixGoSpacing.sm),
                            child: ListTile(
                              title: Text(_entryTitle(entry)),
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
