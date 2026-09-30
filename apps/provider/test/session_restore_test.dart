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
  test('unauthorized session is cleared', () async {
    sessionToken = token('provider-1');
    final state = ProviderAppState(api: OfflineApi(401));
    addTearDown(state.dispose);
    await state.restoreSession();
    expect(state.isSignedIn, false);
  });
}
