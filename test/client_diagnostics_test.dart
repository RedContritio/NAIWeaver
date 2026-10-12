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
