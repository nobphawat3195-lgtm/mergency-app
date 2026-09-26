import 'dart:async';

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
  final SecureTokenStore _tokenStore =
      const SecureTokenStore('fixgo_provider_access_token');

  bool _hasProfile = false;
  bool _isOnline = false;

  bool get isSignedIn => api.accessToken != null;

  /// ช่างที่ยังไม่ได้กรอกแบบฟอร์มลงทะเบียนจะเข้าได้แค่หน้าสมัคร
  bool get hasProfile => _hasProfile;
  bool get isOnline => _isOnline;

  void signIn(String token, {required bool hasProfile}) {
    api.accessToken = token;
    _hasProfile = hasProfile;
    unawaited(_tokenStore.write(token));
    if (hasProfile) unawaited(PushNotifications.instance.attach(api));
    notifyListeners();
  }

  /// หลังส่งใบสมัคร backend ออก token ที่มี id ช่างจริงแล้ว จึงลงทะเบียน push ได้
  void markProfileCreated() {
    _hasProfile = true;
    unawaited(PushNotifications.instance.attach(api));
    notifyListeners();
  }

  void setOnline(bool value) {
    _isOnline = value;
    notifyListeners();
  }

  void signOut() {
    // ต้องถอนโทเคน push ก่อนล้าง accessToken
    unawaited(PushNotifications.instance.detach(api));
    api.accessToken = null;
    _hasProfile = false;
    _isOnline = false;
    unawaited(_tokenStore.clear());
    notifyListeners();
  }

  /// เรียกก่อน runApp ห้าม throw เด็ดขาด ไม่งั้นแอปค้างจอขาวตั้งแต่เปิด
  Future<void> restoreSession() async {
    final String? token;
    try {
      token = await _tokenStore.read();
    } catch (_) {
      // อ่าน secure storage ไม่ได้ (เช่น เบราว์เซอร์บล็อก) ให้เริ่มแบบยังไม่ล็อกอิน
      return;
    }
    if (token == null || token.isEmpty) return;
    api.accessToken = token;
    try {
      final profile = await api.getProviderProfile();
      _hasProfile = true;
      _isOnline = profile['isOnline'] as bool? ?? false;
      unawaited(PushNotifications.instance.attach(api));
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        _hasProfile = false;
        return;
      }
      if (error.statusCode == 401) {
        api.accessToken = null;
        await _tokenStore.clear();
      }
    } catch (_) {
      // ออฟไลน์ตอนเปิดแอป: ช่างที่มี token แล้วเคยสมัครมาก่อนแน่นอน
      // ให้เข้าหน้าหลักได้เลย ไม่บังคับไปหน้าสมัครซ้ำ
      _hasProfile = true;
    }
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
