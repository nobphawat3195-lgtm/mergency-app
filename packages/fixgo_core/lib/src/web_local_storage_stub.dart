/// แอปมือถือไม่ใช้ localStorage (ดู token_store.dart)
const isWebStorage = false;

String? webStorageRead(String key) => throw UnsupportedError('web only');

void webStorageWrite(String key, String value) =>
    throw UnsupportedError('web only');

void webStorageDelete(String key) => throw UnsupportedError('web only');
