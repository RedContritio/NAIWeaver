import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_gateway.dart';
import '../../../core/theme/theme_extensions.dart';
import '../backend_auth_notifier.dart';

class BackendAuthGate extends StatelessWidget {
  final Widget child;
  const BackendAuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!useBackendGateway) return child;
    final auth = context.watch<BackendAuthNotifier>();
    if (auth.isAuthenticated) return child;
    return Scaffold(
      backgroundColor: context.t.background,
      body: Center(
        child: auth.isLoading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (auth.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(auth.errorMessage!),
                    ),
                  TextButton(
                    onPressed: auth.login,
                    child: const Text('通过 only WebAuth 继续'),
                  ),
                ],
              ),
      ),
    );
  }
}
