import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_rules.dart';
import 'package:naiweaver/core/gateway/image_quote.dart';

/// The golden cases the gateway's own tests run (docs/GATEWAY_CONTRACT.md §3).
void main() {
  final fixture =
      jsonDecode(File('test/fixtures/quote_cases.json').readAsStringSync())
          as Map<String, dynamic>;
  final baseRules = fixture['base_rules'] as Map<String, dynamic>;

  ImageRules rulesFor(Map<String, dynamic> testCase) {
    final image = {
      ...baseRules,
      if (testCase.containsKey('green_point_discount'))
        'green_point_discount': testCase['green_point_discount'],
      if (testCase.containsKey('free_allowance_exhausted'))
        'free_allowance_exhausted': testCase['free_allowance_exhausted'],
    };
    return ImageRules.tryParse({'image': image})!;
  }

  Map<String, dynamic> requestFor(Map<String, dynamic> testCase) => {
    if (testCase['action'] != null) 'action': testCase['action'],
    'parameters': testCase['parameters'],
  };

  group('golden quote cases', () {
    for (final raw in fixture['cases'] as List<dynamic>) {
      final testCase = raw as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final quote = quoteImageRequest(
          rulesFor(testCase),
          requestFor(testCase),
          images: testCase['seeds'] as int,
        );
        final expected = testCase['expected'] as Map<String, dynamic>;
        final breakdown = expected['breakdown'] as Map<String, dynamic>;
        expect(quote.mode, expected['mode']);
        expect(quote.points, expected['points']);
        expect(quote.perImage, expected['per_image']);
        expect(quote.images, expected['images']);
        expect(quote.base, breakdown['base']);
        expect(quote.directorRefs, breakdown['director_refs']);
        expect(quote.extraVibes, breakdown['extra_vibes']);
        expect(quote.reasons, expected['reasons']);
      });
    }
  });

  group('requests the gateway rejects', () {
    for (final raw in fixture['invalid_cases'] as List<dynamic>) {
      final testCase = raw as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final field =
            (testCase['expected_error'] as Map<String, dynamic>)['field'];
        expect(
          () => quoteImageRequest(
            rulesFor(testCase),
            requestFor(testCase),
            images: 1,
          ),
          throwsA(
            isA<InvalidQuoteRequest>().having((e) => e.field, 'field', field),
          ),
        );
      });
    }
  });
}
