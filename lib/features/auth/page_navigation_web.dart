import 'package:web/web.dart' as web;

/// Reloads the whole page, dropping every in-memory state of the app.
void reloadPage() => web.window.location.reload();
