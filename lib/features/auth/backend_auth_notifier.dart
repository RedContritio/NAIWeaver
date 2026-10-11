import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gateway/backend_gateway.dart';

import '../../core/services/backend_auth_api.dart';

class BackendAuthNotifier extends ChangeNotifier {
  final BackendAuthApi api;

  BackendAuthNotifier({BackendAuthApi? api}) : api = api ?? BackendAuthApi();

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  AuthUser? _user;
  AuthUser? get user => _user;
  bool get isAuthenticated => _user != null;

  BackendQuota? _quota;
  BackendQuota? get quota => _quota;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final payload = await api.me();
      _user = payload.user;
      _quota = payload.quota;
    } on BackendAuthException catch (error) {
      _user = null;
      _quota = null;
      if (error.statusCode == 401) {
        await login();
      } else {
        _errorMessage = error.message;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSession() async {
    try {
      final payload = await api.me();
      _user = payload.user;
      _quota = payload.quota;
      notifyListeners();
    } on BackendAuthException catch (error) {
      _user = null;
      _quota = null;
      if (error.statusCode == 401) {
        await login();
      } else {
        _errorMessage = error.message;
      }
      notifyListeners();
    }
  }

  Future<void> login() async {
    final uri = Uri.base.resolve(backendUrl('/auth/login'));
    if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
      _errorMessage = '无法打开认证页面，请刷新重试。';
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } finally {
      _user = null;
      _quota = null;
      notifyListeners();
    }
  }
}
