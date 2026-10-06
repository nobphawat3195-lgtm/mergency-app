import 'dart:async';
import 'dart:convert';

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

  /// เข้าด้วย LINE แล้วยังไม่ได้สมัคร: โทเคนยังไม่มีเบอร์ ต้องกรอกเบอร์ติดต่อในใบสมัคร
  bool get needsContactPhone {
    final token = api.accessToken;
    if (token == null) return false;
    try {
      final parts = token.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return (payload['phone'] as String? ?? '').isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// ล็อกอิน LINE ไม่สำเร็จ (ผู้ใช้กดยกเลิก หรือตั๋วหมดอายุ) ให้หน้าเข้าสู่ระบบแจ้ง
  bool lineLoginFailed = false;

  /// ข้อความที่หน้าเข้าสู่ระบบแสดงครั้งเดียว เช่น ถูกพาออกเพราะบัญชีนี้สมัครแล้ว
  String? loginNotice;

  /// sub ของโทเคนที่ถืออยู่ (อ่านอย่างเดียว ไม่ได้ตรวจลายเซ็น)
  String? _tokenSubject(String token) {
    try {
      final payload = jsonDecode(utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1]))))
          as Map<String, dynamic>;
      final sub = payload['sub'];
      return sub is String ? sub : null;
    } catch (_) {
      return null;
    }
  }

  /// เข้าด้วย LINE แต่ยังไม่ได้สมัครตอนได้โทเคนนี้มา (sub = pending:line:<id>)
  bool get _holdsPendingLineToken {
    final token = api.accessToken;
    return token != null &&
        (_tokenSubject(token)?.startsWith('pending:line:') ?? false);
  }

  /// pending token ของ LINE ค้างอยู่ในเบราว์เซอร์นี้ แต่บัญชี LINE เดียวกันส่งใบสมัครไปแล้วจากที่อื่น
  /// (เช่น สมัครใน Safari แล้วเปิดในเบราว์เซอร์ของแอป LINE): ขอโทเคนบัญชีจริงมาแทน
  ///
  /// คืน true เมื่อได้โทเคนใหม่และเข้าหน้าหลักแล้ว false เมื่อยังไม่ได้สมัครหรือขอไม่สำเร็จ
  /// (โทเคนเดิมยังอยู่ ช่างส่งใบสมัครต่อได้)
  Future<bool> refreshPendingLineSession() async {
    if (!_holdsPendingLineToken) return false;
    final pending = api.accessToken;
    try {
      final session = await api.refreshPendingLineSession();
      if (!session.hasProfile) {
        api.accessToken = pending;
        return false;
      }
      signIn(session.accessToken, hasProfile: true);
      await _loadOnlineState();
      notifyListeners();
      return true;
    } catch (_) {
      api.accessToken = pending;
      return false;
    }
  }

  /// เว็บ: LINE พากลับมาพร้อม ?line_ticket= ให้แลกเป็นโทเคนแล้วลบออกจากแถบที่อยู่ทันที
  Future<bool> _completeLineLogin() async {
    final query = browserQueryParameters();
    final ticket = query['line_ticket'];
    if (ticket == null && query['line_error'] == null) return false;
    clearBrowserQuery();
    if (ticket == null) {
      lineLoginFailed = true;
      return false;
    }
    try {
      final session = await api.exchangeLineTicketSession(ticket);
      signIn(session.accessToken, hasProfile: session.hasProfile);
      if (session.hasProfile) await _loadOnlineState();
      return true;
    } catch (_) {
      api.accessToken = null;
      lineLoginFailed = true;
      return false;
    }
  }

  // Rendering hint only. Authorization remains enforced by the backend.
  bool _profileFromToken(String token) {
    final sub = _tokenSubject(token);
    return sub != null && sub.isNotEmpty && !sub.startsWith('pending:');
  }

  Future<void> _loadOnlineState() async {
    try {
      final profile = await api.getProviderProfile();
      _isOnline = profile['isOnline'] as bool? ?? false;
    } catch (_) {
      // โหลดสถานะไม่ได้ก็เริ่มแบบปิดรับงานไว้ก่อน หน้าหลักจะดึงใหม่อีกครั้ง
    }
  }

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

  /// เพิ่มขึ้นทุกครั้งที่งานของช่างเปลี่ยนจากหน้าอื่น (เช่น กดรับงานในหน้าแรก)
  /// หน้างานของฉันฟังค่านี้แล้วโหลดใหม่ทันที โดยไม่ต้อง rebuild ทั้งแอป
  final ValueNotifier<int> jobsRevision = ValueNotifier<int>(0);

  void notifyJobsChanged() => jobsRevision.value++;

  final Map<String, int> _chatUnread = {};

  /// จำจำนวนข้อความที่ยังไม่อ่านของแต่ละงาน คืน true เมื่อมีข้อความใหม่เพิ่มจากรอบก่อน
  /// หน้าหลักและหน้างานของฉัน poll พร้อมกันได้ แต่เสียงแจ้งเตือนดังครั้งเดียว
  bool trackChatUnread(Iterable<Order> orders) {
    var increased = false;
    for (final order in orders) {
      final before = _chatUnread[order.id];
      if (before != null && order.chatUnread > before) increased = true;
      _chatUnread[order.id] = order.chatUnread;
    }
    return increased;
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
    if (await _completeLineLogin()) return;
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
        // pending token เก่า แต่อาจสมัครไปแล้วจากเบราว์เซอร์อื่น ลองขอโทเคนบัญชีจริงก่อน
        if (await refreshPendingLineSession()) return;
        _hasProfile = false;
        return;
      }
      if (error.statusCode == 401) {
        api.accessToken = null;
        await _tokenStore.clear().catchError((_) {});
      } else if (error.statusCode == 408 || error.statusCode >= 500) {
        _hasProfile = _profileFromToken(token);
      }
    } catch (_) {
      // ช่างที่สมัครแล้วไม่ต้องสมัครซ้ำเมื่อเน็ตหลุด แต่ pending token ยังเข้าหน้าสมัคร
      _hasProfile = _profileFromToken(token);
    }
  }

  @override
  void dispose() {
    jobsRevision.dispose();
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
