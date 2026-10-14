import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_alerts.dart';

WebAlertPlatform createWebAlertPlatform() => _BrowserPlatform();

class _BrowserPlatform implements WebAlertPlatform {
  @override
  bool get isWeb => true;

  @override
  bool get standalone {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    // Safari บน iPhone บอกผ่าน navigator.standalone
    return web.window.navigator
            .getProperty<JSBoolean?>('standalone'.toJS)
            ?.toDart ??
        false;
  }

  @override
  bool get isIos {
    final agent = web.window.navigator.userAgent;
    if (RegExp('iPhone|iPad|iPod').hasMatch(agent)) return true;
    // iPad รุ่นใหม่บอกตัวเองว่าเป็น Mac
    return agent.contains('Macintosh') &&
        web.window.navigator.maxTouchPoints > 1;
  }

  @override
  bool get pushSupported =>
      web.window.navigator.has('serviceWorker') &&
      web.window.has('PushManager') &&
      web.window.has('Notification');

  @override
  String get permission =>
      web.window.has('Notification') ? web.Notification.permission : 'denied';

  @override
  Future<WebPushKeys?> subscribe(String publicKey, {required bool ask}) async {
    if (!pushSupported) return null;
    if (ask && permission == 'default') {
      // ต้องเรียกตรงจากการแตะ (iPhone ไม่ให้ขอนอก gesture)
      await web.Notification.requestPermission().toDart;
    }
    if (permission != 'granted') return null;

    final registration = await web.window.navigator.serviceWorker.ready.toDart
        .timeout(const Duration(seconds: 10));
    final manager = registration.pushManager;
    final subscription = await manager.getSubscription().toDart ??
        await manager
            .subscribe(
              web.PushSubscriptionOptionsInit(
                userVisibleOnly: true,
                applicationServerKey: _decodeKey(publicKey).toJS,
              ),
            )
            .toDart;
    final json = subscription.toJSON() as JSObject;
    final keys = json.getProperty<JSObject?>('keys'.toJS);
    final endpoint = subscription.endpoint;
    final p256dh = keys?.getProperty<JSString?>('p256dh'.toJS)?.toDart;
    final auth = keys?.getProperty<JSString?>('auth'.toJS)?.toDart;
    if (endpoint.isEmpty || p256dh == null || auth == null) return null;
    return WebPushKeys(endpoint: endpoint, p256dh: p256dh, auth: auth);
  }

  /// VAPID public key เป็น base64url ไม่มี padding
  Uint8List _decodeKey(String key) =>
      base64Url.decode(key.padRight((key.length + 3) & ~3, '='));
}
