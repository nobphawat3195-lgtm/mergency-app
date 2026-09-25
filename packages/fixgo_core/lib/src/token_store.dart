import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'web_local_storage_stub.dart'
    if (dart.library.js_interop) 'web_local_storage.dart';

/// เก็บ access token
/// - แอปมือถือ: พื้นที่เข้ารหัสของระบบปฏิบัติการ (Keychain / EncryptedSharedPreferences)
/// - เว็บ: localStorage ของเบราว์เซอร์ตามปกติของเว็บแอป
///   (ปลั๊กอิน secure storage บนเว็บหาตัว implementation ไม่เจอใน release build ทำให้ล็อกอินหายทุกครั้งที่รีเฟรช
///   และบนเว็บก็เก็บกุญแจเข้ารหัสไว้ใน localStorage เหมือนกัน จึงไม่ได้ปลอดภัยกว่า)
class SecureTokenStore {
  const SecureTokenStore(this.key);

  final String key;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read() async =>
      isWebStorage ? webStorageRead(key) : _storage.read(key: key);

  Future<void> write(String token) async => isWebStorage
      ? webStorageWrite(key, token)
      : _storage.write(key: key, value: token);

  Future<void> clear() async =>
      isWebStorage ? webStorageDelete(key) : _storage.delete(key: key);
}
