import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../working_hours.dart';
import 'public_profile_screen.dart';
import 'jobs_screen.dart';
import 'offers_screen.dart';
import 'payout_info_form.dart';
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
      // แท็บงาน/กระเป๋าเงินรู้ว่าตัวเองถูกเปิดอยู่ เพื่อโหลดใหม่ตอนเปิดและ poll ระหว่างเปิด
      body: IndexedStack(
        index: _index,
        children: [
          OffersScreen(onOpenTab: (tab) => setState(() => _index = tab)),
          JobsScreen(active: _index == 1),
          WalletScreen(active: _index == 2),
          const _ProviderProfileTab(),
        ],
      ),
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

  Future<void> _editHours(Map<String, dynamic> profile) async {
    final api = ProviderAppScope.of(context).api;
    final saved = await showWorkingHoursSheet(
      context,
      api: api,
      open: profile['openMinute'] as int? ?? allDayOpenMinute,
      close: profile['closeMinute'] as int? ?? allDayCloseMinute,
    );
    if (saved == null || !mounted) return;
    setState(() => _future = api.getProviderProfile());
  }

  /// เล่นเสียงปลุก + เสียงพูด 1 รอบให้ช่างเช็กว่าเครื่องดังจริง (บนเว็บการแตะนี้ปลดล็อกเสียงไปด้วย)
  void _testAlarm() {
    unawaited(ProviderAppScope.of(context).offerAlarm.test());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'กำลังเล่นเสียงแจ้งเตือนและเสียงพูด ถ้าไม่ได้ยิน ให้เพิ่มเสียงเครื่องหรือปิดโหมดเงียบ',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _editPayoutInfo(Map<String, dynamic> profile) async {
    final api = ProviderAppScope.of(context).api;
    final saved = await showPayoutInfoForm(context, api: api, profile: profile);
    if (!saved || !mounted) return;
    setState(() => _future = api.getProviderProfile());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          // โหลดใหม่หลังแก้ข้อมูล: แสดงข้อมูลเดิมต่อ ไม่กระพริบเป็น spinner
          if (profile == null &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingStateView();
          }
          return ListView(
            padding: const EdgeInsets.all(FixGoSpacing.md),
            children: [
              // โหลดไม่ได้: ยังออกจากระบบ/ลบบัญชีได้ตามปกติ
              if (snapshot.hasError) ...[
                ErrorStateView(
                  compact: true,
                  error: snapshot.error,
                  title: 'โหลดข้อมูลโปรไฟล์ไม่สำเร็จ',
                  onRetry: () => setState(
                    () => _future =
                        ProviderAppScope.of(context).api.getProviderProfile(),
                  ),
                ),
                const SizedBox(height: FixGoSpacing.md),
              ],
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
                  leading: const Icon(Icons.schedule),
                  title: const Text('เวลารับงาน'),
                  subtitle: Text(
                    workingHoursSentence(
                      profile['openMinute'] as int? ?? allDayOpenMinute,
                      profile['closeMinute'] as int? ?? allDayCloseMinute,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editHours(profile),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('ข้อมูลรับเงิน'),
                  subtitle: Text(
                    hasPayoutInfo(profile)
                        ? 'บันทึกแล้ว'
                        : 'ยังไม่ได้กรอก — ต้องกรอกก่อนกดเบิกเงิน',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editPayoutInfo(profile),
                ),
                const Divider(),
              ],
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('ทดสอบเสียงแจ้งเตือน'),
                subtitle:
                    const Text('เสียงปลุกและเสียงพูดที่ดังตอนมีงานใหม่เข้ามา'),
                onTap: _testAlarm,
              ),
              const Divider(),
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
