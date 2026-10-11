import 'package:dio/dio.dart';

import '../gateway/backend_exception.dart';
import '../gateway/backend_rules.dart';
import 'backend_client.dart';

class BackendAuthApi {
  BackendAuthApi({BackendClient? client})
    : _client = client ?? BackendClient.shared;

  final BackendClient _client;

  /// Ends the gateway session. A 401 means there was none left to end.
  Future<void> logout() async {
    try {
      await _client.post<dynamic>(
        '/api/logout',
        data: const <String, dynamic>{},
        options: _ownsAuthFailure,
      );
    } on BackendException catch (error) {
      if (!error.isNotAuthenticated) rethrow;
    }
  }

  /// The signed-in user. A 401 `not_authenticated` is thrown to the caller
  /// without raising the session-expired flow: the caller decides.
  Future<AuthPayload> me() async {
    final response = await _client.get<dynamic>(
      '/api/me',
      options: _ownsAuthFailure,
    );
    final data = response.data;
    if (data is! Map<String, dynamic> ||
        data['user'] is! Map<String, dynamic>) {
      throw const BackendException(
        statusCode: null,
        code: BackendErrorCode.invalidResponse,
      );
    }
    return AuthPayload.fromJson(data);
  }

  static final _ownsAuthFailure = Options(
    extra: {backendSkipAuthCallbackKey: true},
  );
}

class AuthPayload {
  final AuthUser user;
  final BackendQuota? quota;
  final ImageRules? rules;

  const AuthPayload({required this.user, this.quota, this.rules});

  factory AuthPayload.fromJson(Map<String, dynamic> json) {
    return AuthPayload(
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      quota: json['quota'] is Map<String, dynamic>
          ? BackendQuota.fromJson(json['quota'] as Map<String, dynamic>)
          : null,
      rules: ImageRules.tryParse(json['rules']),
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
  final int? greenPointLimit;
  final int? greenPointDiscount;
  final int? redPoints;
  final int? pointLimit;
  final int used;
  final int? remaining;
  final bool unlimited;
  final bool enabled;

  const BackendQuotaBucket({
    required this.kind,
    required this.greenPointLimit,
    required this.greenPointDiscount,
    required this.redPoints,
    required this.pointLimit,
    required this.used,
    required this.remaining,
    required this.unlimited,
    required this.enabled,
  });

  factory BackendQuotaBucket.fromJson(Map<String, dynamic> json) {
    return BackendQuotaBucket(
      kind: json['kind'] as String? ?? 'points',
      greenPointLimit: (json['green_point_limit'] as num?)?.toInt(),
      greenPointDiscount: (json['green_point_discount'] as num?)?.toInt(),
      redPoints: (json['red_points'] as num?)?.toInt(),
      pointLimit: (json['point_limit'] as num?)?.toInt(),
      used: (json['used'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt(),
      unlimited: json['unlimited'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  bool get hasRemaining => unlimited || (remaining != null && remaining! > 0);
}
