import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/widgets.dart';

abstract final class AppConfig {
  /// ตั้งค่าตอน build ด้วย --dart-define=API_BASE_URL=https://api.fixgo.co.th
  /// ค่า default ใช้ 10.0.2.2 เพราะเป็น localhost ของเครื่องแม่เมื่อรันบน Android emulator
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}

class AppState extends ChangeNotifier {
  AppState({required this.api});

  final FixGoApiClient api;
  final SecureTokenStore _tokenStore =
      const SecureTokenStore('fixgo_customer_access_token');

  bool get isSignedIn => api.accessToken != null;

  void signIn(String token) {
    api.accessToken = token;
    unawaited(_tokenStore.write(token));
    notifyListeners();
  }

  void signOut() {
    api.accessToken = null;
    unawaited(_tokenStore.clear());
    notifyListeners();
  }

  Future<void> restoreSession() async {
    final token = await _tokenStore.read();
    if (token == null || token.isEmpty) return;
    api.accessToken = token;
    try {
      // ตรวจว่า token ยังใช้ได้และเป็นบัญชีที่เข้าถึงข้อมูลของตัวเองได้
      await api.listMyOrders();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        api.accessToken = null;
        await _tokenStore.clear();
      }
    }
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope?.notifier != null, 'ไม่พบ AppStateScope ใน widget tree');
    return scope!.notifier!;
  }
}
