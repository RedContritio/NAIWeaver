import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

class LocaleNotifier extends ChangeNotifier {
  final PreferencesService _prefs;
  late Locale _locale;

  static const _buildDefault = String.fromEnvironment(
    'DEFAULT_LOCALE',
    defaultValue: 'zh',
  );

  LocaleNotifier(this._prefs) {
    _locale = resolve(_prefs);
  }

  /// The language in effect: the saved choice, else the default.
  static Locale resolve(PreferencesService prefs) {
    final saved = prefs.locale;
    return saved.isNotEmpty ? Locale(saved) : _resolveDefault();
  }

  /// The default without saved preferences: the Web `?lang=` parameter, else
  /// the build's DEFAULT_LOCALE.
  static Locale resolveDefault() => _resolveDefault();

  static Locale _resolveDefault() {
    // On web, URL param overrides build default
    if (kIsWeb) {
      final lang = Uri.base.queryParameters['lang'];
      if (lang == 'ja') return const Locale('ja');
      if (lang == 'en') return const Locale('en');
      if (lang == 'zh') return const Locale('zh');
    }
    // Fall back to build-time default
    return Locale(_buildDefault);
  }

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    await _prefs.setLocale(locale.languageCode);
    notifyListeners();
  }
}
