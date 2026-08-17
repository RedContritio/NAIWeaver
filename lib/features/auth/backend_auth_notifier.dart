import 'package:flutter/foundation.dart';

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
    } on BackendAuthException {
      _user = null;
      _quota = null;
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
    } on BackendAuthException {
      _user = null;
      _quota = null;
      notifyListeners();
    }
  }

  Future<void> loginWithWebAuthn() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final payload = await api.loginWithWebAuthn();
      _user = payload.user;
      _quota = payload.quota;
    } catch (e) {
      _user = null;
      _quota = null;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BackendWebAuthnOptions> prepareWebAuthnLogin() {
    return api.loginWebAuthnOptions();
  }

  Future<void> loginWithPreparedWebAuthn(BackendWebAuthnOptions options) async {
    _errorMessage = null;
    try {
      final payload = await api.loginWithWebAuthnOptions(options);
      _user = payload.user;
      _quota = payload.quota;
    } catch (e) {
      _user = null;
      _quota = null;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> bindWithWebAuthn(String token) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final payload = await api.bindWithWebAuthn(token);
      _user = payload.user;
      _quota = payload.quota;
    } catch (e) {
      _user = null;
      _quota = null;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BackendWebAuthnOptions> prepareWebAuthnBind(String token) {
    return api.registerWebAuthnOptions(token);
  }

  Future<void> bindWithPreparedWebAuthn(
    String token,
    BackendWebAuthnOptions options,
  ) async {
    _errorMessage = null;
    try {
      final payload = await api.bindWithWebAuthnOptions(token, options);
      _user = payload.user;
      _quota = payload.quota;
    } catch (e) {
      _user = null;
      _quota = null;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
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
