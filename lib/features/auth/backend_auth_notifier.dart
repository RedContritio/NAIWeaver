import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gateway/backend_exception.dart';
import '../../core/gateway/backend_gateway.dart';
import '../../core/gateway/backend_rules.dart';
import '../../core/services/backend_auth_api.dart';
import '../../core/services/backend_client.dart';
import 'page_navigation_stub.dart'
    if (dart.library.js_interop) 'page_navigation_web.dart';

/// The browser operations the sign-in flow needs; faked in tests.
abstract class BackendAuthNavigation {
  /// The address of the page the user is on.
  Uri get currentPage;

  /// Navigates this tab to [uri]; false when the browser refused.
  Future<bool> open(Uri uri);

  /// Reloads the page, discarding all in-memory state.
  void reload();
}

class BrowserAuthNavigation implements BackendAuthNavigation {
  const BrowserAuthNavigation();

  @override
  Uri get currentPage => Uri.base;

  @override
  Future<bool> open(Uri uri) => launchUrl(uri, webOnlyWindowName: '_self');

  @override
  void reload() => reloadPage();
}

/// `/auth/login` with `return_to` set to the page the user is on (the gateway
/// accepts only same-origin paths starting with `/`).
Uri buildLoginUri(Uri page) {
  final login = page.resolve(backendUrl('/auth/login'));
  final returnTo = page.hasQuery ? '${page.path}?${page.query}' : page.path;
  return login.replace(
    queryParameters: {if (returnTo.startsWith('/')) 'return_to': returnTo},
  );
}

class BackendAuthNotifier extends ChangeNotifier {
  final BackendAuthApi api;
  final BackendClient _client;
  final BackendAuthNavigation _navigation;
  final bool _gateway;

  BackendAuthNotifier({
    BackendAuthApi? api,
    BackendClient? client,
    BackendAuthNavigation navigation = const BrowserAuthNavigation(),
    bool? gateway,
  }) : _client = client ?? BackendClient.shared,
       api = api ?? BackendAuthApi(client: client),
       _navigation = navigation,
       _gateway = gateway ?? useBackendGateway {
    if (_gateway) _client.onNotAuthenticated = markSessionExpired;
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  AuthUser? _user;
  AuthUser? get user => _user;
  bool get isAuthenticated => _user != null;

  BackendQuota? _quota;
  BackendQuota? get quota => _quota;

  ImageRules? _rules;
  ImageRules? get rules => _rules;

  /// Why the user could not be loaded (shown on the sign-in screen).
  BackendException? _error;
  BackendException? get error => _error;

  /// The last failed background refresh; the signed-in user is kept.
  BackendException? _refreshError;
  BackendException? get refreshError => _refreshError;

  bool _loginLaunchFailed = false;
  bool get loginLaunchFailed => _loginLaunchFailed;

  bool _sessionExpired = false;

  /// The gateway no longer knows this session. The page stays usable until
  /// the user confirms the sign-in redirect, so unsaved edits are not lost.
  bool get sessionExpired => _sessionExpired;

  bool _logoutFailed = false;

  /// The last sign-out attempt failed and the session is still valid.
  bool get logoutFailed => _logoutFailed;

  void _apply(AuthPayload payload) {
    _user = payload.user;
    _quota = payload.quota;
    _rules = payload.rules;
    _client.imageRules = payload.rules;
  }

  Future<void> initialize() async {
    if (!_gateway) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _apply(await api.me());
    } on BackendException catch (error) {
      _user = null;
      _quota = null;
      _rules = null;
      if (error.isNotAuthenticated) {
        await login();
      } else {
        _error = error;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSession() async {
    try {
      _apply(await api.me());
      _refreshError = null;
    } on BackendException catch (error) {
      if (error.isNotAuthenticated) {
        markSessionExpired();
      } else {
        // Offline or a server hiccup says nothing about the session.
        _refreshError = error;
      }
    }
    notifyListeners();
  }

  /// Flags the session as gone without leaving the page.
  void markSessionExpired() {
    if (_user == null || _sessionExpired) return;
    _sessionExpired = true;
    notifyListeners();
  }

  Future<void> login() async {
    _loginLaunchFailed = false;
    if (!await _navigation.open(buildLoginUri(_navigation.currentPage))) {
      _loginLaunchFailed = true;
      notifyListeners();
    }
  }

  /// Ends the session and reloads the page. When the gateway cannot confirm
  /// the sign-out the user stays signed in and [logoutFailed] is set.
  Future<void> logout() async {
    _logoutFailed = false;
    try {
      await api.logout();
    } on BackendException {
      _logoutFailed = true;
      notifyListeners();
      return;
    }
    _user = null;
    _quota = null;
    _rules = null;
    _client.imageRules = null;
    notifyListeners();
    _navigation.reload();
  }

  void acknowledgeLogoutFailure() {
    _logoutFailed = false;
  }

  @override
  void dispose() {
    if (_client.onNotAuthenticated == markSessionExpired) {
      _client.onNotAuthenticated = null;
    }
    super.dispose();
  }
}
