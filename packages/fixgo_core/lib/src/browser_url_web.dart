import 'package:web/web.dart' as web;

Map<String, String> browserQueryParameters() =>
    Uri.parse(web.window.location.href).queryParameters;

void clearBrowserQuery() {
  final location = web.window.location;
  web.window.history.replaceState(null, '', location.pathname);
}
