import 'dart:convert';
import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixgo_provider/app_state.dart';

class OfflineApi extends FixGoApiClient {
  OfflineApi(this.status) : super(baseUrl: 'https://api.example.com');
  final int status;
  @override
  Future<Map<String, dynamic>> getProviderProfile() async {
    throw ApiException(status, 'offline');
  }
}

/// pending token ค้างอยู่ /providers/me ได้ 404 แต่ /auth/line/refresh อาจได้บัญชีที่สมัครไว้แล้ว
class PendingApi extends FixGoApiClient {
  PendingApi({this.refreshed}) : super(baseUrl: 'https://api.example.com');

  /// null = บัญชี LINE นี้ยังไม่ได้สมัคร (refresh ได้ 404)
  final String? refreshed;
  int refreshCalls = 0;

  @override
  Future<Map<String, dynamic>> getProviderProfile() async {
    if (accessToken == refreshed) return {'id': 'provider-1', 'isOnline': true};
    throw ApiException(404, 'ไม่พบข้อมูลช่าง');
  }

  @override
  Future<({String accessToken, bool hasProfile})>
      refreshPendingLineSession() async {
    refreshCalls++;
    final token = refreshed;
    if (token == null) {
      throw ApiException(404, 'บัญชี LINE นี้ยังไม่ได้ส่งใบสมัครช่าง');
    }
    accessToken = token;
    return (accessToken: token, hasProfile: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  String sessionToken = '';
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
      if (call.method == 'read') return sessionToken;
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });
  String token(String sub) =>
      'header.${base64Url.encode(utf8.encode(jsonEncode({
            'sub': sub
          })))}.signature';

  for (final status in [408, 503]) {
    test('existing mechanic stays in the main flow after $status', () async {
      sessionToken = token('provider-1');
      final state = ProviderAppState(api: OfflineApi(status));
      addTearDown(state.dispose);
      await state.restoreSession();
      expect(state.isSignedIn, true);
      expect(state.hasProfile, true);
      expect(state.isOnline, false);
    });
    test('pending mechanic remains in registration after $status', () async {
      sessionToken = token('pending:0800000000');
      final state = ProviderAppState(api: OfflineApi(status));
      addTearDown(state.dispose);
      await state.restoreSession();
      expect(state.hasProfile, false);
    });
  }
  test('stale pending LINE token switches to the registered account', () async {
    sessionToken = token('pending:line:U1');
    final real = token('provider-1');
    final api = PendingApi(refreshed: real);
    final state = ProviderAppState(api: api);
    addTearDown(state.dispose);
    await state.restoreSession();
    expect(api.refreshCalls, 1);
    expect(state.hasProfile, true);
    expect(state.isOnline, true);
    expect(api.accessToken, real);
  });
  test('pending LINE token without an application stays in registration',
      () async {
    sessionToken = token('pending:line:U1');
    final api = PendingApi();
    final state = ProviderAppState(api: api);
    addTearDown(state.dispose);
    await state.restoreSession();
    expect(api.refreshCalls, 1);
    expect(state.hasProfile, false);
    expect(api.accessToken, sessionToken);
  });
  test('OTP pending token does not ask for a LINE refresh', () async {
    sessionToken = token('pending:0800000000');
    final api = PendingApi(refreshed: token('provider-1'));
    final state = ProviderAppState(api: api);
    addTearDown(state.dispose);
    await state.restoreSession();
    expect(api.refreshCalls, 0);
    expect(state.hasProfile, false);
  });
  test('unauthorized session is cleared', () async {
    sessionToken = token('provider-1');
    final state = ProviderAppState(api: OfflineApi(401));
    addTearDown(state.dispose);
    await state.restoreSession();
    expect(state.isSignedIn, false);
  });
}
