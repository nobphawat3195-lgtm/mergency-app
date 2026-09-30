import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'public_profile_screen.dart';
import 'jobs_screen.dart';
import 'offers_screen.dart';
import 'wallet_screen.dart';

class ProviderShellScreen extends StatefulWidget {
  const ProviderShellScreen({super.key});

  @override
  State<ProviderShellScreen> createState() => _ProviderShellScreenState();
}

class _ProviderShellScreenState extends State<ProviderShellScreen> {
  int _index = 0;
  Timer? _heartbeatTimer;
  StreamSubscription<PushEvent>? _pushOpened;
  StreamSubscription<PushEvent>? _pushReceived;
  late final List<Widget> _pages = [
    OffersScreen(onOpenTab: (tab) => setState(() => _index = tab)),
    const JobsScreen(),
    const WalletScreen(),
    const _ProviderProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    final push = PushNotifications.instance;
    _pushOpened = push.onOpened.listen(_openFromPush);
    _pushReceived = push.onReceived.listen(_showPushBanner);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launch = push.takeLaunchEvent();
      if (launch != null && mounted) _openFromPush(launch);
    });
  }

  /// งานใหม่อยู่หน้าหลัก สถานะงานที่รับแล้ว/การชำระเงินอยู่หน้างานของฉัน
  int _tabFor(PushEvent event) => switch (event.type) {
        'OFFER' || 'ACCOUNT' => 0,
        'WALLET' => 2,
        _ => 1,
      };

  void _openFromPush(PushEvent event) {
    setState(() => _index = _tabFor(event));
  }

  void _showPushBanner(PushEvent event) {
    if (!mounted || event.title == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [event.title, if (event.body != null) event.body].join('\n'),
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'ดู',
          onPressed: () => _openFromPush(event),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _heartbeatTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final state = ProviderAppScope.of(context);
      if (state.isOnline) {
        unawaited(state.api.sendProviderHeartbeat().catchError((_) {
          // เน็ตหลุดชั่วคราว: รอบ heartbeat ถัดไปจะลองใหม่
        }));
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _pushOpened?.cancel();
    _pushReceived?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: FixGoColors.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: _NavIcon(uiIconHome),
              selectedIcon: _NavIcon(uiIconHome, selected: true),
              label: 'หน้าหลัก',
            ),
            NavigationDestination(
              icon: _NavIcon(uiIconRepair),
              selectedIcon: _NavIcon(uiIconRepair, selected: true),
              label: 'งานของฉัน',
            ),
            NavigationDestination(
              icon: _NavIcon(uiIconMoneyBag),
              selectedIcon: _NavIcon(uiIconMoneyBag, selected: true),
              label: 'กระเป๋าเงิน',
            ),
            NavigationDestination(
              icon: _NavIcon(technicianIconAsset),
              selectedIcon: _NavIcon(technicianIconAsset, selected: true),
              label: 'โปรไฟล์',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderProfileTab extends StatefulWidget {
  const _ProviderProfileTab();

  @override
  State<_ProviderProfileTab> createState() => _ProviderProfileTabState();
}

class _ProviderProfileTabState extends State<_ProviderProfileTab> {
  Future<Map<String, dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ProviderAppScope.of(context).api.getProviderProfile();
  }

  Future<void> _editPublicProfile(Map<String, dynamic> profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(profile: profile),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      _future = ProviderAppScope.of(context).api.getProviderProfile();
    });
  }

  Future<void> _editPayoutInfo(Map<String, dynamic> profile) async {
    final bankNameController =
        TextEditingController(text: profile['bankName'] as String? ?? '');
    final accountNameController = TextEditingController(
        text: profile['bankAccountName'] as String? ?? '');
    final accountNumberController = TextEditingController(
      text: profile['bankAccountNumber'] as String? ?? '',
    );
    final promptPayController =
        TextEditingController(text: profile['promptPayId'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ข้อมูลรับเงิน'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bankNameController,
                decoration: const InputDecoration(labelText: 'ธนาคาร'),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              TextField(
                controller: accountNameController,
                decoration: const InputDecoration(labelText: 'ชื่อบัญชี'),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              TextField(
                controller: accountNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'เลขบัญชี'),
              ),
              const SizedBox(height: FixGoSpacing.sm),
              TextField(
                controller: promptPayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'พร้อมเพย์'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    try {
      await ProviderAppScope.of(context).api.updatePayoutInfo(
            bankName: bankNameController.text.trim(),
            bankAccountName: accountNameController.text.trim(),
            bankAccountNumber: accountNumberController.text.trim(),
            promptPayId: promptPayController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _future = ProviderAppScope.of(context).api.getProviderProfile();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(FixGoSpacing.md),
            children: [
              if (profile != null) ...[
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    '${profile['realName']} (${profile['nickname']})',
                  ),
                  subtitle: Text(profile['phone'] as String),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('สถานะบัญชี'),
                  subtitle: Text(_statusLabel(profile['status'] as String)),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('ข้อมูลที่ลูกค้าเห็น'),
                  subtitle: Text(
                    profile['photoUrl'] != null &&
                            profile['vehiclePlate'] != null
                        ? 'รูปและทะเบียนรถครบแล้ว'
                        : 'ใส่รูปและทะเบียนรถ ลูกค้าจะมั่นใจขึ้น',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editPublicProfile(profile),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('ข้อมูลรับเงิน'),
                  subtitle: Text(
                    profile['promptPayId'] != null ||
                            profile['bankAccountNumber'] != null
                        ? 'บันทึกแล้ว'
                        : 'ยังไม่ได้กรอก — ต้องกรอกก่อนกดเบิกเงิน',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editPayoutInfo(profile),
                ),
                const Divider(),
              ],
              AccountSettingsTiles(
                api: ProviderAppScope.of(context).api,
                onDeleted: ProviderAppScope.of(context).signOut,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('ออกจากระบบ'),
                onTap: () => ProviderAppScope.of(context).signOut(),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return 'รอทีมงานอนุมัติ';
      case 'VERIFIED':
        return 'อนุมัติแล้ว พร้อมรับงาน';
      case 'REJECTED':
        return 'ใบสมัครยังไม่ผ่าน ดูรายละเอียดที่หน้าหลัก';
      case 'SUSPENDED':
        return 'ถูกระงับการใช้งาน';
      default:
        return status;
    }
  }
}

/// ไอคอน 3D ของแถบเมนูล่าง: แท็บที่ไม่ได้เลือกแสดงจางลงและเล็กกว่าเล็กน้อย
class _NavIcon extends StatelessWidget {
  const _NavIcon(this.asset, {this.selected = false});

  final String asset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 30.0 : 26.0;
    return Opacity(
      opacity: selected ? 1 : 0.55,
      child: Image.asset(asset, width: size, height: size),
    );
  }
}
