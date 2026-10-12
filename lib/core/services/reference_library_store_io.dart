import 'kv_store.dart';

// Native builds keep the library in its JSON file, as before.

Future<String?> readLibrary(String path, String legacyPrefsKey) =>
    KvStore.readString(path: path, prefsKey: legacyPrefsKey);

Future<void> writeLibrary(String path, String legacyPrefsKey, String value) =>
    KvStore.writeString(path: path, prefsKey: legacyPrefsKey, value: value);
