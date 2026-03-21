import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Image extensions accepted by the app.
const _imageExtensions = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};

bool _isAndroid() => !kIsWeb && Platform.isAndroid;

/// Picks image files with an Android SAF workaround.
///
/// On Android, SAF transcoding can strip PNG metadata chunks when using
/// [FileType.image]. This helper uses [FileType.any] on Android to bypass
/// that behaviour, then filters results by extension manually.
Future<FilePickerResult?> pickImageFiles({
  bool allowMultiple = false,
  bool withData = false,
}) async {
  final android = _isAndroid();
  final result = await FilePicker.platform.pickFiles(
    type: android ? FileType.any : FileType.image,
    allowMultiple: allowMultiple,
    withData: withData,
  );
  if (result == null || !android) return result;

  // Filter out non-image files the user may have selected.
  final filtered = result.files.where((f) {
    if (f.path == null) return false;
    final ext = f.path!.toLowerCase();
    return _imageExtensions.any((e) => ext.endsWith(e));
  }).toList();

  return filtered.isEmpty ? null : FilePickerResult(filtered);
}

/// Picks files with custom extensions, using [FileType.any] on Android
/// (where [FileType.custom] can fail) with manual extension filtering.
Future<FilePickerResult?> pickCustomFiles({
  required List<String> allowedExtensions,
  bool allowMultiple = false,
  bool withData = false,
}) async {
  final android = _isAndroid();
  final result = await FilePicker.platform.pickFiles(
    type: android ? FileType.any : FileType.custom,
    allowedExtensions: android ? null : allowedExtensions,
    allowMultiple: allowMultiple,
    withData: withData,
  );
  if (result == null || !android) return result;

  final exts = allowedExtensions.map((e) => '.$e'.toLowerCase()).toSet();
  final filtered = result.files.where((f) {
    if (f.path == null) return false;
    final path = f.path!.toLowerCase();
    return exts.any((e) => path.endsWith(e));
  }).toList();

  return filtered.isEmpty ? null : FilePickerResult(filtered);
}
