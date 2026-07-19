import 'package:flutter/services.dart';

/// Free-space queries backed by a tiny MethodChannel (Android `StatFs` in
/// `MainActivity.kt`). Used to sanity-check the destination volume before
/// moving the output library to an SD card (issue #21).
class DeviceStorage {
  DeviceStorage._();

  static const _channel = MethodChannel('dev.naiweaver.app/storage');

  /// Available bytes on the volume containing [path], or null when unknown
  /// (non-Android platform, missing path, or StatFs failure). Callers should
  /// treat null as "cannot verify" rather than "no space".
  static Future<int?> freeBytesAt(String path) async {
    try {
      return await _channel.invokeMethod<int>('getFreeBytes', {'path': path});
    } catch (_) {
      return null;
    }
  }
}
