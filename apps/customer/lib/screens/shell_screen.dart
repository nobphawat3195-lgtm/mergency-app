import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'home_screen.dart';
import 'orders_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  late final List<Widget> _pages = const [
    HomeScreen(),
    OrdersScreen(),
    _ProfileTab(),
  ];

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
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'หน้าหลัก',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'รายการ',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'โปรไฟล์',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: ListView(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        children: [
          const _AccountHeader(),
          const Divider(),
          AccountSettingsTiles(
            api: AppStateScope.of(context).api,
            onDeleted: AppStateScope.of(context).signOut,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('ออกจากระบบ'),
            onTap: () => AppStateScope.of(context).signOut(),
          ),
        ],
      ),
    );
  }
}

/// บอกว่าเข้าบัญชีไหนอยู่ (ชื่อหรือเบอร์ และเข้าด้วย LINE หรือเบอร์โทร)
class _AccountHeader extends StatefulWidget {
  const _AccountHeader();

  @override
  State<_AccountHeader> createState() => _AccountHeaderState();
}

class _AccountHeaderState extends State<_AccountHeader> {
  Future<({String? name, String? phone, bool viaLine})>? _account;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??= AppStateScope.of(context).api.getMyAccount();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String? name, String? phone, bool viaLine})>(
      future: _account,
      builder: (context, snapshot) {
        final account = snapshot.data;
        final String subtitle;
        if (snapshot.hasError) {
          subtitle = 'โหลดข้อมูลบัญชีไม่สำเร็จ';
        } else if (account == null) {
          subtitle = 'กำลังโหลด...';
        } else {
          subtitle = account.viaLine
              ? 'เข้าสู่ระบบด้วย LINE'
              : 'เข้าสู่ระบบด้วยเบอร์โทร';
        }
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: FixGoColors.accentSoft,
            foregroundColor: FixGoColors.accent,
            child: Icon(Icons.person),
          ),
          title: Text(
            account?.name ?? account?.phone ?? 'บัญชีของฉัน',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(subtitle),
          trailing: snapshot.hasError
              ? TextButton(
                  onPressed: () => setState(() {
                    _account = AppStateScope.of(context).api.getMyAccount();
                  }),
                  child: const Text('ลองใหม่'),
                )
              : null,
        );
      },
    );
  }
}
