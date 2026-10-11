import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_error_messages.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../backend_auth_notifier.dart';

class BackendAuthGate extends StatefulWidget {
  final Widget child;
  const BackendAuthGate({super.key, required this.child});

  @override
  State<BackendAuthGate> createState() => _BackendAuthGateState();
}

class _BackendAuthGateState extends State<BackendAuthGate> {
  BackendAuthNotifier? _auth;
  bool _expiredDialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (!useBackendGateway) return;
    _auth = context.read<BackendAuthNotifier>()..addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth!;
    if (auth.sessionExpired && !_expiredDialogOpen) {
      _expiredDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askToSignIn(auth));
    }
    if (auth.logoutFailed) {
      auth.acknowledgeLogoutFailure();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showErrorSnackBar(context, context.l.gatewayLogoutFailed);
      });
    }
  }

  /// The redirect leaves the page, so it waits for the user's confirmation:
  /// anything unsaved on this page would be lost.
  Future<void> _askToSignIn(BackendAuthNotifier auth) async {
    if (!mounted) return;
    final t = context.tRead;
    final l = context.l;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.gatewaySessionExpiredTitle.toUpperCase(),
          style: TextStyle(
            fontSize: t.titleSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Text(
          l.gatewaySessionExpiredBody,
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(10)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l.gatewaySessionExpiredConfirm.toUpperCase(),
              style: TextStyle(color: t.accent, fontSize: t.buttonSize(9)),
            ),
          ),
        ],
      ),
    );
    _expiredDialogOpen = false;
    await auth.login();
  }

  @override
  Widget build(BuildContext context) {
    if (!useBackendGateway) return widget.child;
    final auth = context.watch<BackendAuthNotifier>();
    if (auth.isAuthenticated) return widget.child;
    final l = context.l;
    final error = auth.error;
    // A failed load is retried; only a missing session needs the sign-in.
    final canRetry = error != null && !error.isNotAuthenticated;
    final failure = error != null
        ? backendErrorMessage(l, error)
        : auth.loginLaunchFailed
        ? l.gatewayLoginOpenFailed
        : null;
    final Widget body;
    if (auth.isLoading) {
      body = const LoadingState();
    } else {
      final signIn = TextButton(
        onPressed: auth.login,
        child: Text(l.gatewayAuthContinue),
      );
      body = failure == null
          ? Center(child: signIn)
          : Column(
              children: [
                Expanded(
                  child: ErrorState(
                    message: failure,
                    onRetry: canRetry ? auth.initialize : null,
                    retryLabel: l.gatewayAuthRetry,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: VisionMetrics.space24),
                  child: signIn,
                ),
              ],
            );
    }
    return Scaffold(backgroundColor: context.t.background, body: body);
  }
}
