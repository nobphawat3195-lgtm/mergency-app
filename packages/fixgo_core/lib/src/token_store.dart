import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// เก็บ access token ในพื้นที่เข้ารหัสของระบบปฏิบัติการ
/// ไม่ใช้ SharedPreferences/localStorage เพื่อไม่ให้ token หลุดจาก storage ทั่วไป
class SecureTokenStore {
  const SecureTokenStore(this.key);

  final String key;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read() => _storage.read(key: key);

  Future<void> write(String token) => _storage.write(key: key, value: token);

  Future<void> clear() => _storage.delete(key: key);
}
