// Platform-agnostic entrypoint for triggering a browser download.
//
// On web this routes to an `<a download>`-based blob download (web_download_web.dart).
// On native it routes to a no-op stub (web_download_io.dart) so that callers can
// invoke it unconditionally without pulling `dart:html` into native builds.
import 'web_download_io.dart' if (dart.library.html) 'web_download_web.dart' as backend;

/// Triggers a browser download of [bytes] as [fileName] with the given [mimeType].
///
/// No-op on non-web platforms (callers should guard with `kIsWeb` and use the
/// native save path instead). Returns true if a download was triggered.
bool downloadBytes(List<int> bytes, String fileName, {String mimeType = 'image/png'}) {
  return backend.downloadBytes(bytes, fileName, mimeType: mimeType);
}
