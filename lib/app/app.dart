import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/l10n/locale_notifier.dart';
import '../core/services/client_diagnostics_runtime.dart';
import '../core/theme/theme_notifier.dart';
import '../core/widgets/pin_lock_gate.dart';
import '../features/auth/widgets/backend_auth_gate.dart';
import '../l10n/app_localizations.dart';
import 'bootstrap.dart';
import 'providers.dart';

/// The provider graph and the [MaterialApp] around [home].
class NaiWeaverApp extends StatelessWidget {
  const NaiWeaverApp({super.key, required this.services, required this.home});

  final AppServices services;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: buildAppProviders(services),
      child: Builder(
        builder: (context) {
          final themeNotifier = context.watch<ThemeNotifier>();
          final localeNotifier = context.watch<LocaleNotifier>();
          return ValueListenableBuilder<bool>(
            valueListenable: services.preferences.tooltipVisibilityNotifier,
            builder: (context, visible, child) =>
                TooltipVisibility(visible: visible, child: child!),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.mouse,
                },
              ),
              theme: themeNotifier.themeData,
              locale: localeNotifier.locale,
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              navigatorObservers: [DiagnosticsNavigatorObserver.instance],
              home: PinLockGate(
                prefs: services.preferences,
                child: BackendAuthGate(child: home),
              ),
            ),
          );
        },
      ),
    );
  }
}
