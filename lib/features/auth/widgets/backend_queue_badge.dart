import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/gateway/backend_gateway.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';

class BackendQueueBadge extends StatefulWidget {
  const BackendQueueBadge({super.key});

  @override
  State<BackendQueueBadge> createState() => _BackendQueueBadgeState();
}

class _BackendQueueBadgeState extends State<BackendQueueBadge> {
  final Dio _dio = Dio();
  Timer? _timer;
  int _queued = 0;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await _dio.get<dynamic>(backendUrl('/api/queue'));
      final data = response.data;
      if (data is! Map<String, dynamic> || !mounted) return;
      setState(() {
        _queued = (data['queued'] as num?)?.toInt() ?? 0;
        _active = (data['active'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // Queue status is informational; generation errors are surfaced elsewhere.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final total = _queued + _active;
    final detail = total == 0
        ? context.l.gatewayQueueIdle
        : '${context.l.gatewayQueueQueued} $_queued · ${context.l.gatewayQueueActive} $_active';
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
            Icon(Icons.queue, size: 12, color: t.headerText),
            const SizedBox(width: 4),
            Text(
              '$total',
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
}
