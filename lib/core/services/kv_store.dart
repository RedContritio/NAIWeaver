import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kv_store_web.dart' if (dart.library.io) 'kv_store_io.dart' as backend;

/// Platform-agnostic small-JSON key/value store.
///
/// On native: backed by a file at the given path (preserves existing on-disk
/// JSON files like presets.json so users keep their data).
/// On web: backed by SharedPreferences keyed by `prefsKey`.
///
/// Typical use: one logical record per filesystem path. Callers pass the same
/// `path` they used to use with `File(...)`, plus a stable `prefsKey` for web.
class KvStore {
  static Future<String?> readString({
    required String path,
    required String prefsKey,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(prefsKey);
      return (v == null || v.isEmpty) ? null : v;
    }
    return backend.readFileString(path);
  }

  static Future<void> writeString({
    required String path,
    required String prefsKey,
    required String value,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, value);
      return;
    }
    await backend.writeFileString(path, value);
  }

  static Future<void> remove({
    required String path,
    required String prefsKey,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
      return;
    }
    await backend.deleteFile(path);
  }

  static Future<bool> exists({
    required String path,
    required String prefsKey,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(prefsKey);
    }
    return backend.fileExists(path);
  }
}
