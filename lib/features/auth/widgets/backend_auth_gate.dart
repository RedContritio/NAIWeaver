import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_gateway.dart';
import '../../../core/services/backend_auth_api.dart';
import '../../../core/theme/theme_extensions.dart';
import '../backend_auth_notifier.dart';

class BackendAuthGate extends StatefulWidget {
  final Widget child;

  const BackendAuthGate({super.key, required this.child});

  @override
  State<BackendAuthGate> createState() => _BackendAuthGateState();
}

class _BackendAuthGateState extends State<BackendAuthGate> {
  @override
  Widget build(BuildContext context) {
    if (!useBackendGateway) return widget.child;
    final auth = context.watch<BackendAuthNotifier>();
    if (auth.isLoading) {
      return Scaffold(
        backgroundColor: context.t.background,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.t.accent,
          ),
        ),
      );
    }
    if (auth.isAuthenticated) return widget.child;
    return const _LoginScreen();
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  Future<BackendWebAuthnOptions>? _optionsFuture;
  String? _optionsKey;
  bool _actionInProgress = false;

  Future<BackendWebAuthnOptions> _optionsFor(
    BuildContext context,
    String? enrollmentToken,
  ) {
    final key = enrollmentToken == null ? 'login' : 'bind:$enrollmentToken';
    if (_optionsKey != key || _optionsFuture == null) {
      _optionsKey = key;
      final auth = context.read<BackendAuthNotifier>();
      _optionsFuture = enrollmentToken == null
          ? auth.prepareWebAuthnLogin()
          : auth.prepareWebAuthnBind(enrollmentToken);
    }
    return _optionsFuture!;
  }

  void _resetOptions() {
    _optionsFuture = null;
    _optionsKey = null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<BackendAuthNotifier>();
    final t = context.t;
    final enrollmentToken = Uri.base.queryParameters['token']?.trim();
    final enrolling = enrollmentToken != null && enrollmentToken.isNotEmpty;
    final optionsFuture = _optionsFor(
      context,
      enrolling ? enrollmentToken : null,
    );
    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<BackendWebAuthnOptions>(
              future: optionsFuture,
              builder: (context, snapshot) {
                final optionsReady = snapshot.hasData;
                final preparing =
                    snapshot.connectionState != ConnectionState.done;
                final errorMessage =
                    auth.errorMessage ??
                    (snapshot.hasError ? snapshot.error.toString() : null);
                final busy = auth.isLoading || _actionInProgress || preparing;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      height: 36,
                      color: t.logoColor,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      enrolling ? '绑定此设备' : '使用通行密钥登录',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: t.fontSize(16),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      enrolling
                          ? '系统会要求你用 Touch ID、Face ID、指纹、Windows Hello 或安全密钥确认。'
                          : '每次登录都需要通过浏览器保存的通行密钥确认。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(11),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        errorMessage.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.accentDanger,
                          fontSize: t.fontSize(10),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: busy || !optionsReady
                          ? null
                          : () => enrolling
                                ? _bind(
                                    context,
                                    enrollmentToken,
                                    snapshot.data!,
                                  )
                                : _login(context, snapshot.data!),
                      icon: busy
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.background,
                              ),
                            )
                          : Icon(
                              enrolling
                                  ? Icons.phonelink_lock_outlined
                                  : Icons.fingerprint,
                              size: 18,
                            ),
                      label: Text(
                        (preparing
                                ? '准备中'
                                : enrolling
                                ? '绑定此设备'
                                : '登录')
                            .toUpperCase(),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.background,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login(
    BuildContext context,
    BackendWebAuthnOptions options,
  ) async {
    final auth = context.read<BackendAuthNotifier>();
    final future = auth.loginWithPreparedWebAuthn(options);
    if (mounted) setState(() => _actionInProgress = true);
    await future;
    if (!mounted) return;
    if (!auth.isAuthenticated) {
      setState(() {
        _actionInProgress = false;
        _resetOptions();
      });
    }
  }

  Future<void> _bind(
    BuildContext context,
    String token,
    BackendWebAuthnOptions options,
  ) async {
    final auth = context.read<BackendAuthNotifier>();
    final future = auth.bindWithPreparedWebAuthn(token, options);
    if (mounted) setState(() => _actionInProgress = true);
    await future;
    if (!mounted) return;
    if (!auth.isAuthenticated) {
      setState(() {
        _actionInProgress = false;
        _resetOptions();
      });
    }
  }
}
