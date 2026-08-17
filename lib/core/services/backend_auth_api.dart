import 'package:dio/dio.dart';

import '../gateway/backend_gateway.dart';
import 'webauthn_browser.dart';

class BackendAuthException implements Exception {
  final int statusCode;
  final String message;

  const BackendAuthException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class BackendAuthApi {
  BackendAuthApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  final Dio _dio;

  Future<AuthPayload> loginWithWebAuthn() async {
    final options = await loginWebAuthnOptions();
    return loginWithWebAuthnOptions(options);
  }

  Future<AuthPayload> loginWithWebAuthnOptions(
    BackendWebAuthnOptions options,
  ) async {
    final credential = await getWebAuthnCredential(options.publicKey);
    final data = await verifyWebAuthnLogin(options.challengeId, credential);
    return AuthPayload.fromJson(data);
  }

  Future<AuthPayload> bindWithWebAuthn(String token) async {
    final options = await registerWebAuthnOptions(token);
    return bindWithWebAuthnOptions(token, options);
  }

  Future<AuthPayload> bindWithWebAuthnOptions(
    String token,
    BackendWebAuthnOptions options,
  ) async {
    final credential = await createWebAuthnCredential(options.publicKey);
    final data = await verifyWebAuthnRegistration(
      token,
      options.challengeId,
      credential,
    );
    return AuthPayload.fromJson(data);
  }

  Future<BackendWebAuthnOptions> loginWebAuthnOptions() async {
    final data = await _json('POST', '/api/webauthn/login/options');
    return BackendWebAuthnOptions.fromJson(data);
  }

  Future<BackendWebAuthnOptions> registerWebAuthnOptions(String token) async {
    final data = await _json(
      'POST',
      '/api/webauthn/register/options',
      body: {'token': token},
    );
    return BackendWebAuthnOptions.fromJson(data);
  }

  Future<Map<String, dynamic>> verifyWebAuthnLogin(
    String challengeId,
    Map<String, dynamic> credential,
  ) {
    return _json(
      'POST',
      '/api/webauthn/login/verify',
      body: {'challenge_id': challengeId, 'credential': credential},
    );
  }

  Future<Map<String, dynamic>> verifyWebAuthnRegistration(
    String token,
    String challengeId,
    Map<String, dynamic> credential,
  ) {
    return _json(
      'POST',
      '/api/webauthn/register/verify',
      body: {
        'token': token,
        'challenge_id': challengeId,
        'credential': credential,
      },
    );
  }

  Future<void> logout() async {
    await _json('POST', '/api/logout', body: <String, dynamic>{});
  }

  Future<AuthPayload> me() async {
    final data = await _json('GET', '/api/me');
    return AuthPayload.fromJson(data);
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        backendUrl(path),
        data: body,
        options: Options(method: method, responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      throw const BackendAuthException(502, 'Invalid server response');
    } on DioException catch (e) {
      final data = e.response?.data;
      var message = e.message ?? 'Request failed';
      if (data is Map && data['detail'] != null) {
        message = data['detail'].toString();
      }
      throw BackendAuthException(e.response?.statusCode ?? 0, message);
    }
  }
}

class BackendWebAuthnOptions {
  final String challengeId;
  final Map<String, dynamic> publicKey;

  const BackendWebAuthnOptions({
    required this.challengeId,
    required this.publicKey,
  });

  factory BackendWebAuthnOptions.fromJson(Map<String, dynamic> json) {
    return BackendWebAuthnOptions(
      challengeId: json['challenge_id'] as String? ?? '',
      publicKey: json['publicKey'] as Map<String, dynamic>? ?? const {},
    );
  }
}

class AuthPayload {
  final AuthUser user;
  final BackendQuota? quota;

  const AuthPayload({required this.user, this.quota});

  factory AuthPayload.fromJson(Map<String, dynamic> json) {
    return AuthPayload(
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      quota: json['quota'] is Map<String, dynamic>
          ? BackendQuota.fromJson(json['quota'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AuthUser {
  final int id;
  final String username;
  final bool isAdmin;
  final List<String> permissions;

  const AuthUser({
    required this.id,
    required this.username,
    required this.isAdmin,
    required this.permissions,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'] as List<dynamic>? ?? const [];
    return AuthUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      isAdmin: json['is_admin'] as bool? ?? false,
      permissions: permissions.map((item) => item.toString()).toList(),
    );
  }
}

class BackendQuota {
  final BackendQuotaBucket free;
  final BackendQuotaBucket paid;

  const BackendQuota({required this.free, required this.paid});

  factory BackendQuota.fromJson(Map<String, dynamic> json) {
    return BackendQuota(
      free: BackendQuotaBucket.fromJson(
        json['free'] as Map<String, dynamic>? ?? const {},
      ),
      paid: BackendQuotaBucket.fromJson(
        json['paid'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class BackendQuotaBucket {
  final String kind;
  final int? dailyLimit;
  final int? pointLimit;
  final int used;
  final int? remaining;
  final bool unlimited;

  const BackendQuotaBucket({
    required this.kind,
    required this.dailyLimit,
    required this.pointLimit,
    required this.used,
    required this.remaining,
    required this.unlimited,
  });

  factory BackendQuotaBucket.fromJson(Map<String, dynamic> json) {
    return BackendQuotaBucket(
      kind: json['kind'] as String? ?? 'daily',
      dailyLimit: (json['daily_limit'] as num?)?.toInt(),
      pointLimit: (json['point_limit'] as num?)?.toInt(),
      used: (json['used'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt(),
      unlimited: json['unlimited'] as bool? ?? false,
    );
  }

  bool get hasRemaining => unlimited || (remaining != null && remaining! > 0);
}
