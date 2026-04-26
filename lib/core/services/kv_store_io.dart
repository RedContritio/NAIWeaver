import 'dart:io';

Future<String?> readFileString(String path) async {
  final f = File(path);
  if (!await f.exists()) return null;
  final content = await f.readAsString();
  return content.isEmpty ? null : content;
}

Future<void> writeFileString(String path, String value) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(value);
}

Future<void> deleteFile(String path) async {
  final f = File(path);
  if (await f.exists()) {
    await f.delete();
  }
}

Future<bool> fileExists(String path) => File(path).exists();
