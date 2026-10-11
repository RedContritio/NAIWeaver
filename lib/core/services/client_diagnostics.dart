import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

class ClientDiagnosticEvent {
  const ClientDiagnosticEvent({
    required this.timestamp,
    required this.sequence,
    required this.elapsedMs,
    required this.event,
    required this.details,
  });

  final DateTime timestamp;
  final int sequence;
  final int elapsedMs;
  final String event;
  final Map<String, Object?> details;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'sequence': sequence,
    'elapsed_ms': elapsedMs,
    'event': event,
    'details': details,
  };
}

/// A bounded, in-memory diagnostic trail for user-submitted bug reports.
///
/// It deliberately does not hook [debugPrint] or retain user-entered values.
/// Runtime observers feed it lifecycle and interaction metadata. Nothing
/// leaves the device until the user presses the feedback submit button.
class ClientDiagnostics {
  ClientDiagnostics({this.capacity = 1200}) {
    _beginSession();
  }

  static final ClientDiagnostics instance = ClientDiagnostics();

  final int capacity;
  final ListQueue<ClientDiagnosticEvent> _events = ListQueue();
  late DateTime _startedAt;
  late Stopwatch _stopwatch;
  late String _sessionId;
  int _sequence = 0;
  int _dropped = 0;

  static final RegExp _sensitiveKey = RegExp(
    r'(token|authorization|cookie|password|passcode|api[_-]?key|secret|seed)',
    caseSensitive: false,
  );

  static final RegExp _userValueKey = RegExp(
    r'(^|_)(prompt|content|input|text|value)($|_)',
    caseSensitive: false,
  );

  static final RegExp _safeMetadataSuffix = RegExp(
    r'(_length|_count|_present|_empty|_type|_kind|_width|_height|_size|_offset|_selection|_start|_end)$',
    caseSensitive: false,
  );

  void record(String event, [Map<String, Object?> details = const {}]) {
    if (capacity <= 0) return;
    final safeDetails = <String, Object?>{};
    for (final entry in details.entries.take(48)) {
      final key = _truncate(entry.key, 80);
      safeDetails[key] = _isSensitiveKey(key)
          ? '[redacted]'
          : _safeValue(entry.value);
    }
    _events.add(
      ClientDiagnosticEvent(
        timestamp: DateTime.now(),
        sequence: _sequence++,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        event: _truncate(event, 96),
        details: Map.unmodifiable(safeDetails),
      ),
    );
    while (_events.length > capacity) {
      _events.removeFirst();
      _dropped++;
    }
  }

  List<Map<String, dynamic>> snapshot() => _events
      .map((event) => Map<String, dynamic>.from(event.toJson()))
      .toList(growable: false);

  int get length => _events.length;

  int get droppedCount => _dropped;

  Duration get sessionDuration => _stopwatch.elapsed;

  String get sessionId => _sessionId;

  Map<String, dynamic> get sessionContext => {
    'diagnostic_session_id': _sessionId,
    'diagnostic_session_started_at': _startedAt.toUtc().toIso8601String(),
    'diagnostic_session_duration_ms': _stopwatch.elapsedMilliseconds,
    'diagnostic_event_capacity': capacity,
    'diagnostic_event_count': length,
    'diagnostic_dropped_event_count': _dropped,
  };

  void clear() => _events.clear();

  void reset({String reason = 'manual'}) {
    _events.clear();
    _beginSession();
    record('diagnostic_session_started', {'reason': reason});
  }

  void _beginSession() {
    _startedAt = DateTime.now();
    _stopwatch = Stopwatch()..start();
    _sessionId =
        '${_startedAt.microsecondsSinceEpoch.toRadixString(36)}-'
        '${identityHashCode(this).toRadixString(36)}';
    _sequence = 0;
    _dropped = 0;
  }

  static bool _isSensitiveKey(String key) {
    if (_sensitiveKey.hasMatch(key)) return true;
    if (!_userValueKey.hasMatch(key)) return false;
    return !_safeMetadataSuffix.hasMatch(key);
  }

  static Object? _safeValue(Object? value) {
    if (value == null || value is bool || value is num) return value;
    if (value is Map) return '[map omitted]';
    if (value is Iterable) return '[list omitted]';
    return _truncate(value.toString(), 240);
  }

  static String _truncate(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';
}

/// Coarse key class recorded instead of the key itself, so the trail never
/// contains typed text. Shared by the Flutter (`HardwareKeyboard`) and the
/// browser (`KeyboardEvent`) observers so both report the same categories;
/// a `null` key (an unmapped browser key name) counts as a command.
String clientDiagnosticKeyCategory(LogicalKeyboardKey? key) => switch (key) {
  null => 'command',
  LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'enter',
  LogicalKeyboardKey.escape => 'escape',
  LogicalKeyboardKey.tab => 'tab',
  LogicalKeyboardKey.backspace || LogicalKeyboardKey.delete => 'editing',
  LogicalKeyboardKey.arrowUp ||
  LogicalKeyboardKey.arrowDown ||
  LogicalKeyboardKey.arrowLeft ||
  LogicalKeyboardKey.arrowRight ||
  LogicalKeyboardKey.home ||
  LogicalKeyboardKey.end ||
  LogicalKeyboardKey.pageUp ||
  LogicalKeyboardKey.pageDown => 'navigation',
  LogicalKeyboardKey(:final keyLabel) when keyLabel.runes.length == 1 =>
    'character',
  _ => 'command',
};

/// Leading- and trailing-edge throttle for bursty diagnostic sources.
///
/// The first event of a burst is recorded immediately; events arriving within
/// [interval] are coalesced into a single trailing record that runs with the
/// latest callback and reports how many events it stands for. A soft keyboard
/// animation, which fires dozens of resize events, therefore costs a couple
/// of entries instead of flushing the ring buffer.
class DiagnosticThrottle {
  DiagnosticThrottle(this.interval);

  final Duration interval;
  Timer? _cooldown;
  void Function(int coalescedCount)? _pending;
  int _coalesced = 0;

  /// Records via [record] now, or once the current interval has elapsed.
  /// [record] receives the number of events folded into this record beyond
  /// the one being recorded.
  void call(void Function(int coalescedCount) record) {
    if (_cooldown == null) {
      record(0);
      _startCooldown();
      return;
    }
    _pending = record;
    _coalesced++;
  }

  void _startCooldown() {
    _cooldown = Timer(interval, () {
      _cooldown = null;
      final pending = _pending;
      if (pending == null) return;
      final coalesced = _coalesced - 1;
      _pending = null;
      _coalesced = 0;
      pending(coalesced);
      _startCooldown();
    });
  }
}
