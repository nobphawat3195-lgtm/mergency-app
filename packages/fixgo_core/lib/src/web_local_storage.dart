import 'package:web/web.dart' as web;

const isWebStorage = true;

String? webStorageRead(String key) => web.window.localStorage.getItem(key);

void webStorageWrite(String key, String value) =>
    web.window.localStorage.setItem(key, value);

void webStorageDelete(String key) => web.window.localStorage.removeItem(key);
