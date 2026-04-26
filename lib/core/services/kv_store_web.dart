// Web stub: filesystem operations are no-ops because KvStore.readString/etc
// route to SharedPreferences before reaching the backend on web. These exist
// only so the conditional import resolves without pulling in dart:io.

Future<String?> readFileString(String path) async => null;
Future<void> writeFileString(String path, String value) async {}
Future<void> deleteFile(String path) async {}
Future<bool> fileExists(String path) async => false;
