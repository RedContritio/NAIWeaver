import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';
import 'package:naiweaver/features/characters/services/wardrobe_generator_service.dart';

/// A scripted [TextGenService] that returns canned responses in order.
class _FakeTextGen implements TextGenService {
  final List<String> responses;
  int _i = 0;
  _FakeTextGen(this.responses);

  @override
  Future<String> generate(TextGenRequest req) async {
    final r = _i < responses.length ? responses[_i] : '{"outfits": []}';
    _i++;
    return r;
  }

  @override
  Stream<String> generateStream(TextGenRequest req) => Stream.value('');

  @override
  Future<TextGenResult> generateStructured(TextGenRequest req) async =>
      TextGenResult(text: await generate(req));

  @override
  String get providerId => 'fake';
}

void main() {
  test('parses a clean {"outfits":[...]} response', () async {
    final svc = WardrobeGeneratorService(_FakeTextGen([
      '{"outfits":[{"name":"Cozy","tags":"cream knit sweater, navy skirt, brown boots","seasons":["fall"],"weather":["cold"],"activities":["casual"],"temperature_range":[2,12],"slots":[]}]}'
    ]));
    final out = await svc.generate(characterTags: '1girl', count: 1, maxTokens: 2000);
    expect(out.length, 1);
    expect(out.first.outfit.name, 'Cozy');
    expect(out.first.outfit.tags, 'cream knit sweater, navy skirt, brown boots');
    expect(out.first.outfit.temperatureRange, [2, 12]);
  });

  test('strips markdown fences', () async {
    final svc = WardrobeGeneratorService(_FakeTextGen([
      '```json\n{"outfits":[{"name":"A","tags":"red dress, sandals"}]}\n```'
    ]));
    final out = await svc.generate(characterTags: '1girl', count: 1, maxTokens: 2000);
    expect(out.length, 1);
    expect(out.first.outfit.name, 'A');
  });

  test('salvages complete objects from a truncated array', () async {
    // Truncated mid-second-object — the first complete {...} should survive.
    final svc = WardrobeGeneratorService(_FakeTextGen([
      '{"outfits":[{"name":"One","tags":"a, b","seasons":["spring"]},{"name":"Two","tags":"c, d","seas',
      // continuation pass returns nothing useful
      'unparseable garbage',
    ]));
    final out = await svc.generate(characterTags: '1girl', count: 2, maxTokens: 150);
    expect(out.isNotEmpty, isTrue);
    expect(out.first.outfit.name, 'One');
  });

  test('flags primary outfit', () async {
    final svc = WardrobeGeneratorService(_FakeTextGen([
      '{"outfits":[{"name":"P","tags":"x, y","primary":true},{"name":"Q","tags":"z, w"}]}'
    ]));
    final out = await svc.generate(characterTags: '1girl', count: 2, maxTokens: 2000);
    expect(out.length, 2);
    expect(out.firstWhere((o) => o.outfit.name == 'P').isPrimary, isTrue);
    expect(out.firstWhere((o) => o.outfit.name == 'Q').isPrimary, isFalse);
  });

  test('batches small for low token caps and stops when empty', () async {
    // Two batches of 2, then exhausted.
    final svc = WardrobeGeneratorService(_FakeTextGen([
      '{"outfits":[{"name":"a","tags":"1, 2"},{"name":"b","tags":"3, 4"}]}',
      '{"outfits":[{"name":"c","tags":"5, 6"},{"name":"d","tags":"7, 8"}]}',
    ]));
    final out = await svc.generate(characterTags: '1girl', count: 4, maxTokens: 150);
    expect(out.length, 4);
    expect(out.map((o) => o.outfit.name), ['a', 'b', 'c', 'd']);
  });

  group('underwear rule', () {
    test('modern female: hard bra + panties requirement', () {
      final rule = underwearRuleFor(eraHint: '', gender: 'female');
      expect(rule.contains('HARD CONSTRAINT'), isTrue);
      expect(rule.toLowerCase().contains('bra'), isTrue);
      expect(rule.toLowerCase().contains('panties'), isTrue);
      // It must REQUIRE them, not merely permit them.
      expect(rule.toLowerCase().contains('must include'), isTrue);
    });

    test('empty / nonbinary gender defaults to the female bra+panties rule', () {
      for (final g in const ['', 'nonbinary']) {
        final rule = underwearRuleFor(eraHint: '', gender: g);
        expect(rule.toLowerCase().contains('bra and panties'), isTrue,
            reason: 'gender "$g" should default to the bra+panties rule');
      }
    });

    test('modern male: men\'s underwear, no feminine garments', () {
      final rule = underwearRuleFor(eraHint: '', gender: 'male');
      expect(rule.toLowerCase().contains('boxers'), isTrue);
      expect(rule.toLowerCase().contains('briefs'), isTrue);
      // Must steer away from a bra/panties wardrobe for a male character.
      expect(rule.toLowerCase().contains('do not include'), isTrue);
    });

    test('historical female era pulls a period-correct base-layer hint', () {
      final victorian = underwearRuleFor(eraHint: 'Victorian', gender: 'female');
      expect(victorian.toLowerCase().contains('corset'), isTrue);
      expect(victorian.toLowerCase().contains('chemise'), isTrue);
      // Modern bras/panties forbidden in-period.
      expect(victorian.contains('FORBIDDEN'), isTrue);
    });

    test('historical male era uses the generic men\'s base-layer rule', () {
      final rule = underwearRuleFor(eraHint: 'Victorian', gender: 'male');
      expect(rule.toLowerCase().contains('loincloth') ||
          rule.toLowerCase().contains('braies') ||
          rule.toLowerCase().contains('undershirt'), isTrue);
      // The female period hint (corset / chemise / petticoat) is NOT prescribed
      // for a male character — it appears only in the FORBIDDEN list.
      final corsetIdx = rule.toLowerCase().indexOf('corset');
      if (corsetIdx >= 0) {
        expect(rule.contains('FORBIDDEN'), isTrue);
        expect(corsetIdx, greaterThan(rule.indexOf('FORBIDDEN')),
            reason: 'corset must appear only inside the FORBIDDEN list');
      }
    });

    test('unknown historical era falls back to the generic historical rule', () {
      final rule = underwearRuleFor(eraHint: 'Atlantean Bronze Age', gender: 'female');
      expect(rule.contains('HARD CONSTRAINT'), isTrue);
      expect(rule.toLowerCase().contains('era-appropriate'), isTrue);
    });

    test('buildWardrobePrompt embeds the gender-correct underwear rule', () {
      final female = buildWardrobePrompt(count: 3, characterTags: '1girl', gender: 'female');
      expect(female.toLowerCase().contains('bra and panties'), isTrue);

      final male = buildWardrobePrompt(count: 3, characterTags: '1boy', gender: 'male');
      expect(male.toLowerCase().contains('boxers'), isTrue);
    });

    test('substituteWardrobePrompt fills the {underwear_rule} placeholder', () {
      final out = substituteWardrobePrompt(
        template: 'X {underwear_rule} Y',
        count: 1,
        characterTags: '1girl',
        gender: 'female',
      );
      expect(out.startsWith('X '), isTrue);
      expect(out.endsWith(' Y'), isTrue);
      expect(out.toLowerCase().contains('bra and panties'), isTrue);
    });
  });
}
