import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/client_diagnostics.dart';

void main() {
  test('diagnostic trail is bounded and redacts sensitive detail keys', () {
    final diagnostics = ClientDiagnostics(capacity: 2);
    diagnostics.record('first', {'prompt': 'secret prompt'});
    diagnostics.record('second', {
      'viewport_height': 640,
      'text_length': 42,
      'textarea_client_height': 120,
    });
    diagnostics.record('third', {
      'negative_prompt': 'secret negative',
      'seed': 123,
    });

    final snapshot = diagnostics.snapshot();
    expect(snapshot, hasLength(2));
    expect(snapshot.first['event'], 'second');
    expect(snapshot.first['sequence'], 1);
    expect(diagnostics.droppedCount, 1);
    final secondDetails = snapshot.first['details'] as Map<String, dynamic>;
    expect(secondDetails['text_length'], 42);
    expect(secondDetails['textarea_client_height'], 120);
    expect(
      (snapshot.last['details'] as Map<String, dynamic>)['negative_prompt'],
      '[redacted]',
    );
    expect(
      (snapshot.last['details'] as Map<String, dynamic>)['seed'],
      '[redacted]',
    );
  });

  test('clear removes previously captured lifecycle events', () {
    final diagnostics = ClientDiagnostics()..record('focus');
    expect(diagnostics.length, 1);
    diagnostics.clear();
    expect(diagnostics.snapshot(), isEmpty);
  });

  test('reset starts a fresh report session with summary metadata', () {
    final diagnostics = ClientDiagnostics(capacity: 4)..record('focus');
    final previousSession = diagnostics.sessionId;

    diagnostics.reset(reason: 'submitted');

    expect(diagnostics.sessionId, isNot(previousSession));
    expect(diagnostics.droppedCount, 0);
    expect(diagnostics.snapshot(), hasLength(1));
    expect(
      diagnostics.snapshot().single['event'],
      'diagnostic_session_started',
    );
    expect(diagnostics.sessionContext['diagnostic_event_capacity'], 4);
    expect(diagnostics.sessionContext['diagnostic_event_count'], 1);
  });

  test('maps and lists are never serialized into diagnostic details', () {
    final diagnostics = ClientDiagnostics()
      ..record('unsafe_shape', {
        'metadata': {'authorization': 'secret'},
        'items': ['private'],
      });
    final details = diagnostics.snapshot().single['details'] as Map;
    expect(details['metadata'], '[map omitted]');
    expect(details['items'], '[list omitted]');
  });
}
