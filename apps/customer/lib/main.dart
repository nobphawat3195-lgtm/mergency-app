import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';

void main() {
  runApp(const FixGoCustomerApp());
}

class FixGoCustomerApp extends StatefulWidget {
  const FixGoCustomerApp({super.key});

  @override
  State<FixGoCustomerApp> createState() => _FixGoCustomerAppState();
}

class _FixGoCustomerAppState extends State<FixGoCustomerApp> {
  late final AppState _appState = AppState(
    api: FixGoApiClient(baseUrl: AppConfig.apiBaseUrl),
  );

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
        title: 'FixGo',
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
