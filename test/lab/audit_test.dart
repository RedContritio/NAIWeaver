import 'package:flutter_test/flutter_test.dart';

import '../../lab/audit.dart';

void main() {
  group('auditOutfits', () {
    test('clean modern outfit is clean', () {
      final r = auditOutfits([
        {
          'name': 'Cozy',
          'tags': 'white cotton bra, white cotton panties, cream knit sweater, navy pleated skirt, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      expect(r.isClean, isTrue, reason: r.formatted());
    });

    test('chest coverage: outer with no base top flags', () {
      final r = auditOutfits([
        {
          'name': 'Bad',
          // jacket + bra-only — missing a shirt/blouse/etc
          'tags': 'red lace bra, blue denim jacket, black pleated skirt, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isTrue,
          reason: r.formatted());
    });

    test('chest coverage: outer + base top OK', () {
      final r = auditOutfits([
        {
          'name': 'OK',
          'tags': 'white cotton bra, ivory cotton blouse, blue denim jacket, black pleated skirt, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: r.formatted());
    });

    test('chest coverage: loungewear over bra is OK when slot is sleep', () {
      final r = auditOutfits([
        {
          'name': 'Sleep',
          'tags': 'pink cotton bra, lavender cotton panties, cream silk robe',
          // silk WILL flag as forbiddenMaterial — that's a separate finding.
          // We care only that chestCoverage does NOT fire here.
          'slots': const ['sleep'],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: r.formatted());
    });

    test('forbidden material: linen / silk / corduroy / chiffon / velvet / tweed', () {
      final r = auditOutfits([
        {
          'name': 'Bri',
          // 4 of the 6 forbidden materials, taken from bri's actual reference
          // output that you pasted ("silk blouse", "linen shirt", "corduroy
          // skirt"). Should all flag.
          'tags': 'cream silk blouse, sage linen shorts, chocolate corduroy skirt, black tweed coat, ivory cotton tank top',
          'slots': const <String>[],
        }
      ]);
      final mat = r.findings.where((f) => f.category == 'forbiddenMaterial').toList();
      expect(mat.length, greaterThanOrEqualTo(4),
          reason: 'expected 4 material flags, got ${mat.length}\n${r.formatted()}');
    });

    test('forbidden material: "satin slip" passes (satin IS indexed)', () {
      final r = auditOutfits([
        {
          'name': 'Slip',
          'tags': 'cream satin slip, white lace bra, white cotton panties, brown leather sandals',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'forbiddenMaterial'), isFalse,
          reason: r.formatted());
    });

    test('tag count: <4 flags low, >7 flags high', () {
      final low = auditOutfits([
        {
          'name': 'Too short',
          'tags': 'white shirt, blue jeans, brown boots',
          'slots': const <String>[],
        }
      ]);
      expect(low.findings.any((f) => f.category == 'tagCountLow'), isTrue);

      final high = auditOutfits([
        {
          'name': 'Too long',
          'tags': 'a red shirt, b blue jeans, c brown boots, d gold ring, e silver necklace, f black hat, g grey scarf, h white socks, i ivory belt',
          'slots': const <String>[],
        }
      ]);
      expect(high.findings.any((f) => f.category == 'tagCountHigh'), isTrue);
    });

    test('missing color: untinted garment flags', () {
      final r = auditOutfits([
        {
          'name': 'Drab',
          'tags': 'sweater, blue jeans, brown boots, white socks',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'missingColor'), isTrue,
          reason: r.formatted());
    });

    test('smuggle: body part in tags flags', () {
      final r = auditOutfits([
        {
          'name': 'Smuggle',
          'tags': 'white shirt, blue jeans, brown boots, dark brown hair',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'smuggle'), isTrue,
          reason: r.formatted());
    });
  });

  group('auditCharacter', () {
    test('flags missing critical fields', () {
      final r = auditCharacter({
        'name': 'Alice',
        // missing soul_md, character_description, tags, etc.
      });
      expect(r.findings.any((f) => f.field == 'soul_md'), isTrue);
      expect(r.findings.any((f) => f.field == 'character_description'), isTrue);
      expect(r.findings.any((f) => f.field == 'tags'), isTrue);
    });

    test('audits outfit_tags inline through the wardrobe audit', () {
      final r = auditCharacter({
        'name': 'Alice',
        'gender': 'female',
        'soul_md': List.generate(500, (_) => 'word').join(' '), // 500 words
        'character_description': List.generate(50, (_) => 'word').join(' '),
        'personality_summary': 'A vivid one-line summary.',
        'outfit_tags': 'red lace bra, blue denim jacket, black skirt, brown boots',
        'tags': {'base': '1girl', 'face': 'a', 'hair': 'b', 'body': 'c'},
        'reaction_patterns': {
          'nervous': 'x',
          'angry': 'x',
          'attracted': 'x',
          'sad': 'x',
          'scared': 'x',
          'embarrassed': 'x',
          'happy': 'x',
        },
        'theme': {'accent': '#ff0000', 'accent_secondary': '#00ff00', 'bg': '#000000'},
      });
      // outfit_tags has a jacket without a base top → chestCoverage
      expect(r.findings.any((f) => f.field == 'outfit_tags' && f.detail.contains('chestCoverage')),
          isTrue,
          reason: r.formatted());
    });
  });
}
