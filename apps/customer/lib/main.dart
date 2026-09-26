import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/order_tracking_screen.dart';
import 'screens/shell_screen.dart';

Future<void> main() async {
  await runWithErrorReporting(appName: 'fixgo-customer', () async {
    WidgetsFlutterBinding.ensureInitialized();
    await PushNotifications.instance.init();
    final appState = AppState(
      api: FixGoApiClient(baseUrl: AppConfig.apiBaseUrl),
    );
    await appState.restoreSession();
    runApp(FixGoCustomerApp(appState: appState));
  });
}

class FixGoCustomerApp extends StatefulWidget {
  const FixGoCustomerApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<FixGoCustomerApp> createState() => _FixGoCustomerAppState();
}

class _FixGoCustomerAppState extends State<FixGoCustomerApp> {
  AppState get _appState => widget.appState;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<PushEvent>? _pushOpened;
  StreamSubscription<PushEvent>? _pushReceived;

  @override
  void initState() {
    super.initState();
    final push = PushNotifications.instance;
    _pushOpened = push.onOpened.listen(_openOrder);
    _pushReceived = push.onReceived.listen(_showPushBanner);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launch = push.takeLaunchEvent();
      if (launch != null) _openOrder(launch);
    });
  }

  /// แตะแจ้งเตือนแล้วเปิดหน้าติดตามงานนั้น (หน้าติดตามดึงสถานะล่าสุดจาก API เอง)
  void _openOrder(PushEvent event) {
    if (!_appState.isSignedIn) return;
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => OrderTrackingScreen(orderId: event.orderId),
      ),
    );
  }

  void _showPushBanner(PushEvent event) {
    if (event.title == null) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          [event.title, if (event.body != null) event.body].join('\n'),
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'ดู',
          onPressed: () => _openOrder(event),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pushOpened?.cancel();
    _pushReceived?.cancel();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _appState,
      child: MaterialApp(
        title: 'FixGo',
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        debugShowCheckedModeBanner: false,
        theme: buildFixGoTheme(),
        home: AnimatedBuilder(
          animation: _appState,
          builder: (context, _) {
            return _appState.isSignedIn
                ? const ShellScreen()
                : const LoginScreen();
          },
        ),
      ),
    );
  }
}
