import 'dart:async';
import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

// The web build stores the reference library in IndexedDB. Saved entries
// keep full-size source images as base64, which overflowed localStorage's
// ~5 MB quota after a few saves (SharedPreferences then failed after its
// in-memory cache had already been updated, so the entry looked saved until
// the page was reloaded). IndexedDB quotas are far larger and a failed write
// rejects the transaction, which the caller reports.

const _databaseName = 'naiweaver';
const _storeName = 'kv';
const _recordKey = 'reference_library';

Future<String?> readLibrary(String path, String legacyPrefsKey) async {
  final db = await _open();
  try {
    final store = db.transaction(_storeName.toJS, 'readonly').objectStore(_storeName);
    final value = await _result(store.get(_recordKey.toJS));
    if (value != null) return (value as JSString).toDart;
  } finally {
    db.close();
  }
  // Libraries saved by older builds still live in localStorage.
  final prefs = await SharedPreferences.getInstance();
  final legacy = prefs.getString(legacyPrefsKey);
  return (legacy == null || legacy.isEmpty) ? null : legacy;
}

Future<void> writeLibrary(String path, String legacyPrefsKey, String value) async {
  final db = await _open();
  try {
    final transaction = db.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).put(value.toJS, _recordKey.toJS);
    await _completion(transaction);
  } finally {
    db.close();
  }
  // The copy in IndexedDB is now authoritative; free the localStorage quota.
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(legacyPrefsKey);
}

Future<web.IDBDatabase> _open() {
  final completer = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open(_databaseName, 1);
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(_storeName)) {
      db.createObjectStore(_storeName);
    }
  }).toJS;
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      StateError('IndexedDB open failed: ${request.error?.message}'),
    );
  }).toJS;
  return completer.future;
}

Future<JSAny?> _result(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      StateError('IndexedDB read failed: ${request.error?.message}'),
    );
  }).toJS;
  return completer.future;
}

/// Completes when [transaction] commits; fails if it errors or aborts
/// (e.g. QuotaExceededError).
Future<void> _completion(web.IDBTransaction transaction) {
  final completer = Completer<void>();
  void fail(String reason) {
    if (completer.isCompleted) return;
    completer.completeError(
      StateError('IndexedDB write $reason: ${transaction.error?.message}'),
    );
  }

  transaction.oncomplete = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  transaction.onerror = ((web.Event _) => fail('failed')).toJS;
  transaction.onabort = ((web.Event _) => fail('aborted')).toJS;
  return completer.future;
}
