import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityPreferences {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  SecurityPreferences(this._prefs, this._secure);

  // — Key constants —
  static const String _kApiKey = 'nai_api_key';
  static const String _kSecureApiKey = 'nai_api_key_secure';
  static const String _kApiKeyBackup = 'nai_api_key_backup';
  static const String _kPinEnabled = 'pin_lock_enabled';
  static const String _kPinHash = 'pin_lock_hash';
  static const String _kPinSalt = 'pin_lock_salt';
  static const String _kPinOnResume = 'pin_lock_on_resume';
  static const String _kPinBiometric = 'pin_biometric_enabled';
  static const String _kPinVersion = 'pin_hash_version';

  // — API Key Migration —

  Future<void> migrateApiKey() async {
    final plaintext = _prefs.getString(_kApiKey) ?? '';
    if (plaintext.isNotEmpty) {
      await _secure.write(key: _kSecureApiKey, value: plaintext);
      _setBackup(plaintext);
      await _prefs.remove(_kApiKey);
    }
  }

  // — API Key (with backup fallback) —

  Future<String> getApiKey() async {
    // Try primary secure storage
    try {
      final key = await _secure.read(key: _kSecureApiKey);
      if (key != null && key.isNotEmpty) {
        _setBackup(key);
        return key;
      }
    } catch (e) {
      debugPrint('Secure storage read failed: $e');
    }

    // Fallback to backup in SharedPreferences
    final backup = _getBackup();
    if (backup.isNotEmpty) {
      // Restore to primary storage
      try {
        await _secure.write(key: _kSecureApiKey, value: backup);
      } catch (_) {}
      return backup;
    }

    return '';
  }

  Future<void> setApiKey(String value) async {
    await _secure.write(key: _kSecureApiKey, value: value);
    _setBackup(value);
  }

  // Simple obfuscation for the SharedPreferences backup (not cryptographic
  // security — just prevents casual reading of the value).
  void _setBackup(String value) {
    if (value.isEmpty) return;
    final encoded = base64Encode(utf8.encode(value));
    _prefs.setString(_kApiKeyBackup, encoded);
  }

  String _getBackup() {
    final encoded = _prefs.getString(_kApiKeyBackup) ?? '';
    if (encoded.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return '';
    }
  }

  // — PIN Enabled —

  bool get pinEnabled => _prefs.getBool(_kPinEnabled) ?? false;

  Future<void> setPinEnabled(bool value) async {
    await _prefs.setBool(_kPinEnabled, value);
  }

  // — PIN Hash —

  String get pinHash => _prefs.getString(_kPinHash) ?? '';

  Future<void> setPinHash(String value) async {
    await _prefs.setString(_kPinHash, value);
  }

  // — PIN Salt —

  String get pinSalt => _prefs.getString(_kPinSalt) ?? '';

  Future<void> setPinSalt(String value) async {
    await _prefs.setString(_kPinSalt, value);
  }

  // — PIN Lock on Resume —

  bool get pinLockOnResume => _prefs.getBool(_kPinOnResume) ?? false;

  Future<void> setPinLockOnResume(bool value) async {
    await _prefs.setBool(_kPinOnResume, value);
  }

  // — PIN Biometric —

  bool get pinBiometricEnabled => _prefs.getBool(_kPinBiometric) ?? false;

  Future<void> setPinBiometricEnabled(bool value) async {
    await _prefs.setBool(_kPinBiometric, value);
  }

  // — PIN Hash Version —

  int get pinHashVersion => _prefs.getInt(_kPinVersion) ?? 1;

  Future<void> setPinHashVersion(int value) async {
    await _prefs.setInt(_kPinVersion, value);
  }
}
