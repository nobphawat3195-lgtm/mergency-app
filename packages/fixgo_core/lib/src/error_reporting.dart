import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// รายงาน crash/error ไป Sentry เมื่อ build ด้วย --dart-define=SENTRY_DSN=...
/// ไม่ตั้ง = รันแอปตามปกติ ไม่ส่งอะไรออกไป
abstract final class ErrorReportingConfig {
  static const dsn = String.fromEnvironment('SENTRY_DSN');
  static const environment =
      String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'production');
}

/// เรียกแทน runApp ใน main() ให้ error ที่หลุดทั้งหมดถูกส่งไป Sentry
Future<void> runWithErrorReporting(
  FutureOr<void> Function() appRunner, {
  required String appName,
}) async {
  if (ErrorReportingConfig.dsn.isEmpty) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = ErrorReportingConfig.dsn;
      options.environment = ErrorReportingConfig.environment;
      options.dist = appName;
      // ไม่แนบข้อมูลส่วนตัว (PDPA): IP ข้อมูลผู้ใช้ และ body/header ของคำขอ
      options.sendDefaultPii = false;
      options.tracesSampleRate = 0;
      options.beforeSend = (event, hint) {
        event.request = null;
        event.user = null;
        return event;
      };
    },
    appRunner: appRunner,
  );
}

/// ส่ง error ที่จับได้แล้ว (เช่น push/Firebase เริ่มไม่ได้) ไปด้วย ถ้าเปิด Sentry อยู่
void reportError(Object error, [StackTrace? stackTrace]) {
  if (ErrorReportingConfig.dsn.isEmpty) {
    debugPrint('error: $error');
    return;
  }
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}
