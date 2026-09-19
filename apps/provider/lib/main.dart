import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/shell_screen.dart';

void main() {
  runApp(const FixGoProviderApp());
}

class FixGoProviderApp extends StatefulWidget {
  const FixGoProviderApp({super.key});

  @override
  State<FixGoProviderApp> createState() => _FixGoProviderAppState();
}

class _FixGoProviderAppState extends State<FixGoProviderApp> {
  late final ProviderAppState _appState = ProviderAppState(
    api: FixGoApiClient(baseUrl: AppConfig.apiBaseUrl),
  );

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderAppScope(
      state: _appState,
      child: MaterialApp(
        title: 'FixGo Fixer',
        debugShowCheckedModeBanner: false,
        theme: buildFixGoTheme(),
        home: AnimatedBuilder(
          animation: _appState,
          builder: (context, _) {
            if (!_appState.isSignedIn) return const ProviderLoginScreen();
            if (!_appState.hasProfile) return const RegisterScreen();
            return const ProviderShellScreen();
          },
        ),
      ),
    );
  }
}
