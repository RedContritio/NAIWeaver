// Web implementation: triggers a browser download via a temporary blob URL
// and a synthetic `<a download>` click. Only reached via the conditional import
// in web_download.dart on web builds.
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

bool downloadBytes(List<int> bytes, String fileName, {String mimeType = 'image/png'}) {
  final data = Uint8List.fromList(bytes);
  final blobParts = [data.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    web.URL.revokeObjectURL(url);
  }
  return true;
}
