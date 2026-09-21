import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState(
    api: FixGoApiClient(baseUrl: AppConfig.apiBaseUrl),
  );
  await appState.restoreSession();
  runApp(FixGoCustomerApp(appState: appState));
}

class FixGoCustomerApp extends StatefulWidget {
  const FixGoCustomerApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<FixGoCustomerApp> createState() => _FixGoCustomerAppState();
}

class _FixGoCustomerAppState extends State<FixGoCustomerApp> {
  AppState get _appState => widget.appState;

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _appState,
      child: MaterialApp(
        title: 'MechNow',
        debugShowCheckedModeBanner: false,
        theme: buildFixGoTheme(),
        home: AnimatedBuilder(
          animation: _appState,
          builder: (context, _) {
            return _appState.isSignedIn
                ? const ShellScreen()
                : const LoginScreen();
          },
        ),
      ),
    );
  }
}
