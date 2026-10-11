import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_exception.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/backend_client.dart';
import '../../../core/theme/theme_extensions.dart';
import '../backend_auth_notifier.dart';

class BackendQueueBadge extends StatefulWidget {
  const BackendQueueBadge({super.key, this.client, this.interval});

  /// The client to poll with; defaults to the shared [BackendClient].
  final BackendClient? client;

  /// Time between polls; defaults to five seconds.
  final Duration? interval;

  @override
  State<BackendQueueBadge> createState() => _BackendQueueBadgeState();
}

typedef _QueueStatus = ({
  int? estimatedWaitSeconds,
  int queued,
  int active,
  bool userQueued,
  bool userActive,
});

class _BackendQueueBadgeState extends State<BackendQueueBadge>
    with WidgetsBindingObserver {
  Timer? _timer;
  _QueueStatus? _status;
  bool _signedIn = false;
  bool _pageVisible = true;
  bool _loading = false;

  BackendClient get _client => widget.client ?? BackendClient.shared;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _pageVisible = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<BackendAuthNotifier>();
    _signedIn = auth.isAuthenticated && !auth.sessionExpired;
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _pageVisible = state == AppLifecycleState.resumed;
    _syncPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Polls only while someone is signed in and looking at the page.
  void _syncPolling() {
    if (_signedIn && _pageVisible) {
      if (_timer != null) return;
      _load();
      _timer = Timer.periodic(
        widget.interval ?? const Duration(seconds: 5),
        (_) => _load(),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final response = await _client.get<dynamic>('/api/queue');
      final data = response.data;
      if (data is! Map<String, dynamic> || !mounted) return;
      final status = (
        estimatedWaitSeconds: (data['estimated_wait_seconds'] as num?)?.toInt(),
        queued: (data['queued'] as num?)?.toInt() ?? 0,
        active: (data['active'] as num?)?.toInt() ?? 0,
        userQueued: data['user_queued'] as bool? ?? false,
        userActive: data['user_active'] as bool? ?? false,
      );
      if (status != _status) setState(() => _status = status);
    } on BackendException {
      // Queue status is informational; generation errors are surfaced elsewhere.
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final status = _status;
    final seconds = status?.estimatedWaitSeconds;
    final detail = (status?.userActive ?? false) || seconds == 0
        ? context.l.gatewayQueueActive
        : seconds != null
        ? '≈ ${_formatDuration(seconds)}'
        : (status?.userQueued ?? false)
        ? context.l.gatewayQueueQueued
        : (status?.active ?? 0) > 0
        ? context.l.gatewayQueueActive
        : (status?.queued ?? 0) > 0
        ? context.l.gatewayQueueQueued
        : context.l.gatewayQueueIdle;
    return Tooltip(
      message: '${context.l.gatewayQueueStatus}: $detail',
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: t.borderSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.borderMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 12, color: t.headerText),
            const SizedBox(width: 4),
            Text(
              detail,
              style: TextStyle(
                color: t.headerText,
                fontSize: t.fontSize(8),
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes < 60) {
      return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
    }
    final hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }
}
