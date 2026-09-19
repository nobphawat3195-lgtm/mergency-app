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

  bool get isSignedIn => api.accessToken != null;

  void signIn(String token) {
    api.accessToken = token;
    notifyListeners();
  }

  void signOut() {
    api.accessToken = null;
    notifyListeners();
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
