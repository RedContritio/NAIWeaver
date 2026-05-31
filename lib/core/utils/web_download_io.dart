// Native stub: there is no browser to download into. Exists only so the
// conditional import in web_download.dart resolves without pulling dart:html
// into native builds.
bool downloadBytes(List<int> bytes, String fileName, {String mimeType = 'image/png'}) => false;
