import 'package:flutter/foundation.dart';

import 'client_diagnostics.dart';

Future<Map<String, dynamic>> collectClientPlatformInfo() async => {
  'platform': defaultTargetPlatform.name,
  'web': false,
};

void startClientDiagnosticsPlatformSession(ClientDiagnostics diagnostics) {}

void captureClientDiagnosticsPlatformSnapshot(ClientDiagnostics diagnostics) {}
