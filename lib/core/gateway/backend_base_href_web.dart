import 'package:web/web.dart' as web;

/// The path of the document's `<base href>` (for sub-path deployments),
/// without a trailing slash. Empty when the app is served from the root.
String platformBaseHrefPath() {
  final href = web.document.querySelector('base')?.getAttribute('href');
  if (href == null || href.isEmpty) return '';
  final path = Uri.tryParse(href)?.path ?? '';
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
