import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/widgets.dart';

abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}

class ProviderAppState extends ChangeNotifier {
  ProviderAppState({required this.api});

  final FixGoApiClient api;

  bool _hasProfile = false;

  bool get isSignedIn => api.accessToken != null;

  /// ช่างที่ยังไม่ได้กรอกแบบฟอร์มลงทะเบียนจะเข้าได้แค่หน้าสมัคร
  bool get hasProfile => _hasProfile;

  void signIn(String token, {required bool hasProfile}) {
    api.accessToken = token;
    _hasProfile = hasProfile;
    notifyListeners();
  }

  void markProfileCreated() {
    _hasProfile = true;
    notifyListeners();
  }

  void signOut() {
    api.accessToken = null;
    _hasProfile = false;
    notifyListeners();
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }
}

class ProviderAppScope extends InheritedNotifier<ProviderAppState> {
  const ProviderAppScope({
    super.key,
    required ProviderAppState state,
    required super.child,
  }) : super(notifier: state);

  static ProviderAppState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ProviderAppScope>();
    assert(scope?.notifier != null, 'ไม่พบ ProviderAppScope ใน widget tree');
    return scope!.notifier!;
  }
}
