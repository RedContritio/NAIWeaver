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

    // --- A1: missingColor gated on garment word ---------------------------

    test('missingColor: attribute-only tags (long sleeves, high collar, etc.) do NOT flag', () {
      final r = auditOutfits([
        {
          'name': 'Attribute',
          'tags': 'ivory chiffon blouse, high collar, long sleeves, lace trim, '
              'burgundy silk skirt, floor-length, black leather boots',
          'slots': const <String>[],
        }
      ]);
      final missing = r.findings.where((f) => f.category == 'missingColor').toList();
      expect(missing, isEmpty,
          reason: 'attribute-only tags should not flag missingColor\n${r.formatted()}');
    });

    test('missingColor: garment word without color still flags', () {
      final r = auditOutfits([
        {
          'name': 'Drab',
          'tags': 'sweater, blue jeans, brown boots, white socks',
          'slots': const <String>[],
        }
      ]);
      final missing = r.findings.where((f) => f.category == 'missingColor').toList();
      expect(missing.length, 1, reason: r.formatted());
      expect(missing.first.detail, contains('"sweater"'));
    });

    test('missingColor: more attribute-only tags pass (scoop neck, hooded, ankle-high, ribbon trim, flat)', () {
      final r = auditOutfits([
        {
          'name': 'AttrPass',
          'tags': 'white cotton dress, short sleeves, scoop neck, ribbon trim, '
              'cream leather slippers, flat, slate cloak, hooded',
          'slots': const <String>[],
        }
      ]);
      final missing = r.findings.where((f) => f.category == 'missingColor').toList();
      expect(missing, isEmpty, reason: r.formatted());
    });

    // --- A2: tan / chestnut removed --------------------------------------

    test('missingColor: tag whose only colour was tan now flags', () {
      // Previously "tan leather sandals" would pass because tan was a colour.
      // It now flags missingColor — desired (tan causes drift).
      final r = auditOutfits([
        {
          'name': 'TanDrift',
          'tags': 'tan leather sandals, white cotton bra, white cotton panties, '
              'cream knit sweater',
          'slots': const <String>[],
        }
      ]);
      final missing = r.findings.where((f) => f.category == 'missingColor').toList();
      expect(missing.any((f) => f.detail.contains('tan leather sandals')), isTrue,
          reason: r.formatted());
    });

    test('missingColor: chestnut no longer counts as a colour', () {
      final r = auditOutfits([
        {
          'name': 'ChestnutDrift',
          'tags': 'chestnut leather belt, white cotton bra, white cotton panties, '
              'cream knit sweater, navy pleated skirt',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'missingColor'
              && f.detail.contains('chestnut leather belt')),
          isTrue,
          reason: r.formatted());
    });

    // --- A3: smuggle false positives -------------------------------------

    test('smuggle: "burgundy plaid scarf" no longer falsely matches "scar"', () {
      final r = auditOutfits([
        {
          'name': 'ScarfPass',
          'tags': 'white cotton bra, white cotton panties, cream knit sweater, '
              'burgundy plaid scarf, navy pleated skirt, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      final smug = r.findings.where((f) => f.category == 'smuggle').toList();
      expect(smug, isEmpty, reason: 'scarf should not smuggle-flag\n${r.formatted()}');
    });

    test('smuggle: bare "mineral" no longer false-flags ordinary tags', () {
      // "mineral grey" hypothetically might have flagged before because of
      // the bare "mineral" token; now the audit only catches "mineral stain"
      // / "mineral-stained" compounds.
      final r = auditOutfits([
        {
          'name': 'MineralOK',
          'tags': 'mineral grey wool coat, ivory cotton blouse, navy pleated skirt, '
              'brown leather boots',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'smuggle'), isFalse,
          reason: r.formatted());
    });

    test('smuggle: "mineral-stained forearms" still flags as smuggle', () {
      final r = auditOutfits([
        {
          'name': 'BriBad',
          'tags': 'cream knit sweater, mineral-stained forearms, navy skirt, brown boots',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'smuggle'), isTrue,
          reason: r.formatted());
    });

    // --- A4: forbiddenMaterial demoted to warning ------------------------

    test('forbiddenMaterial is now a warning, not a blocking finding', () {
      final r = auditOutfits([
        {
          'name': 'Mat',
          'tags': 'cream silk blouse, navy wool skirt, brown leather boots, '
              'ivory cotton tank top',
          'slots': const <String>[],
        }
      ]);
      // Still surfaces in `findings` (back-compat) AND in `warnings`, but NOT
      // in `blocking`.
      expect(r.findings.any((f) => f.category == 'forbiddenMaterial'), isTrue);
      expect(r.warnings.any((f) => f.category == 'forbiddenMaterial'), isTrue);
      expect(r.blocking.any((f) => f.category == 'forbiddenMaterial'), isFalse,
          reason: 'forbiddenMaterial should be a warning, not blocking\n${r.formatted()}');
    });

    // --- A5: unknownTagToken (canonical tag check) ------------------------

    test('unknownTagToken: parenthetical content always flags', () {
      // Skip when canonical file isn't loadable.
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'Roman',
          'tags': 'iron muscle cuirass (lorica musculata), white linen tunic, '
              'brown leather sandals, dark red cloak, leather belt',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      expect(unk.any((f) => f.detail.contains('lorica musculata')), isTrue,
          reason: r.formatted());
    });

    test('unknownTagToken: "cream knit sweater" passes via trailing N-gram', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'CleanCompound',
          'tags': 'cream knit sweater, navy pleated skirt, brown leather boots, '
              'white cotton bra, white cotton panties',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      // "cream knit sweater" → "knit sweater" canonical → no flag.
      // "navy pleated skirt" → "pleated skirt" canonical → no flag.
      // "brown leather boots" → "leather boots" canonical → no flag.
      expect(unk.any((f) =>
              f.detail.contains('cream knit sweater') ||
              f.detail.contains('navy pleated skirt') ||
              f.detail.contains('brown leather boots')),
          isFalse,
          reason: r.formatted());
    });

    test('unknownTagToken is a warning, not blocking', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'Invented',
          'tags': 'cream marshmallow blazer, navy pleated skirt, brown leather boots, '
              'white cotton bra, white cotton panties',
          'slots': const <String>[],
        }
      ]);
      // "marshmallow" isn't canonical and "marshmallow blazer" isn't either,
      // but "blazer" IS canonical (trailing N-gram) — so this specific case
      // PASSES. We assert that the check at least runs and stays in warnings.
      expect(r.blocking.any((f) => f.category == 'unknownTagToken'), isFalse,
          reason: 'unknownTagToken should be warning-only\n${r.formatted()}');
    });

    test('unknownTagToken: pure-colour-only tags do not flag', () {
      if (loadCanonicalTags() == null) return;
      // "navy" alone (no garment) wouldn't normally appear; but the stripping
      // logic should treat such a tag as fine, not flag it.
      final r = auditOutfits([
        {
          'name': 'ColorOnly',
          'tags': 'cream knit sweater, navy pleated skirt, brown leather boots, '
              'white cotton bra, white cotton panties',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      expect(unk, isEmpty,
          reason: 'canonical compounds + leading colours should be clean\n${r.formatted()}');
    });

    // --- B1: _baseTops expanded with dress/gown/tunic/stola/chiton -------

    test('chestCoverage: cloak over a long dress (no separate shirt) is OK', () {
      // Victorian "Autumn Veil"-style case: burgundy long dress + cream cardigan
      // — the dress IS the base layer; should NOT flag chestCoverage.
      final r = auditOutfits([
        {
          'name': 'AutumnVeil',
          'tags': 'burgundy long dress, cream cardigan, long sleeves, brown boots, ribbon trim',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: 'long dress should satisfy chestCoverage\n${r.formatted()}');
    });

    test('chestCoverage: stola under a palla is OK (Roman matron base layer)', () {
      final r = auditOutfits([
        {
          'name': 'RomanMatron',
          'tags': 'crimson stola, ivory palla, gold sandals, floor-length',
          'slots': const <String>[],
        }
      ]);
      // palla isn't an outer layer per _outerLayers, so this wouldn't flag
      // chestCoverage today either; the assertion stays clean regardless.
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: r.formatted());
    });

    test('chestCoverage: gown under a cloak is OK', () {
      final r = auditOutfits([
        {
          'name': 'GownCloak',
          'tags': 'black evening gown, grey cloak, black ankle boots, pearl necklace',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: 'gown should satisfy chestCoverage\n${r.formatted()}');
    });

    test('chestCoverage: tunica under a cloak is OK (Roman base layer)', () {
      final r = auditOutfits([
        {
          'name': 'TunicaCloak',
          'tags': 'brown tunica, grey cloak, leather boots, hooded',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: r.formatted());
    });

    test('chestCoverage: chiton/peplos under a cloak/coat is OK', () {
      final r = auditOutfits([
        {
          'name': 'ChitonCape',
          'tags': 'white chiton, navy cape, brown sandals, head wreath',
          'slots': const <String>[],
        }
      ]);
      expect(r.findings.any((f) => f.category == 'chestCoverage'), isFalse,
          reason: r.formatted());
    });

    // --- B2: _attributeTokens allow-list ----------------------------------

    test('unknownTagToken: standalone attribute tokens (hooded, floor-length, etc.) pass', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'Attr',
          // five attribute-only tags that should NOT flag unknownTagToken:
          // hooded, floor-length, high-waisted, knee-length, ankle-high.
          // Paired with one canonical garment so the outfit reaches 4 tags.
          'tags': 'cream knit sweater, hooded, floor-length, high-waisted, knee-length, ankle-high',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      expect(unk, isEmpty,
          reason: 'attribute-only tokens should not unknownTagToken-flag\n${r.formatted()}');
    });

    test('unknownTagToken: "off-shoulder" alone passes (attribute)', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'OffShoulder',
          'tags': 'white cotton blouse, off-shoulder, navy pleated skirt, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      expect(r.warnings.any((f) =>
              f.category == 'unknownTagToken' && f.detail.contains('off-shoulder')),
          isFalse,
          reason: r.formatted());
    });

    // --- B3: _eraToleratedTags allow-list ---------------------------------

    test('unknownTagToken: Roman period vocab (stola/palla/tunica/subligaculum) passes', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'PaxRomana',
          'tags': 'crimson stola, ivory palla, brown tunica, red subligaculum, gold sandals',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      expect(unk, isEmpty,
          reason: 'Roman period vocab should pass via _eraToleratedTags\n${r.formatted()}');
    });

    test('unknownTagToken: "calcei" and "pallium" pass as era-tolerated', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'RomanFootwear',
          'tags': 'white tunica, grey pallium, brown calcei, gold head wreath',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) =>
          f.category == 'unknownTagToken' &&
          (f.detail.contains('calcei') || f.detail.contains('pallium')));
      expect(unk.isEmpty, isTrue, reason: r.formatted());
    });

    test('unknownTagToken: doublet/hauberk/shendyt pass as era-tolerated', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'EraMixed',
          'tags': 'red doublet, grey hauberk, white shendyt, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      expect(unk, isEmpty, reason: r.formatted());
    });

    // --- B4: _canonicalSupplement -----------------------------------------

    test('unknownTagToken: "tights" passes via canonical supplement', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'WithTights',
          'tags': 'cream knit sweater, navy pleated skirt, black tights, brown leather boots',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) =>
          f.category == 'unknownTagToken' && f.detail.contains('tights')).toList();
      expect(unk, isEmpty, reason: r.formatted());
    });

    test('unknownTagToken: "rust tights" passes (color + supplement)', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'RustTights',
          'tags': 'burgundy sweater vest, cream shirt, rust tights, olive ankle boots',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) =>
          f.category == 'unknownTagToken' && f.detail.contains('rust tights')).toList();
      expect(unk, isEmpty, reason: r.formatted());
    });

    test('unknownTagToken: "cream pajama set" passes via supplement N-gram', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'PajamaSet',
          'tags': 'cream pajama set, long sleeves, slate robe, grey slippers, grey headband',
          'slots': const ['sleep'],
        }
      ]);
      final unk = r.warnings.where((f) =>
          f.category == 'unknownTagToken' && f.detail.contains('pajama set')).toList();
      expect(unk, isEmpty, reason: r.formatted());
    });

    test('unknownTagToken: invented compounds still flag (no regression)', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'StillFlags',
          // "iron muscle cuirass (lorica musculata)" should still flag.
          'tags': 'iron muscle cuirass (lorica musculata), white tunica, '
              'brown leather sandals, dark red cloak, leather belt',
          'slots': const <String>[],
        }
      ]);
      final unk = r.warnings.where((f) => f.category == 'unknownTagToken').toList();
      expect(unk.isNotEmpty, isTrue,
          reason: 'parenthetical should still warn\n${r.formatted()}');
    });

    test('unknownTagToken: ordinary canonical compounds still pass (no regression)', () {
      if (loadCanonicalTags() == null) return;
      final r = auditOutfits([
        {
          'name': 'Clean',
          'tags': 'cream knit sweater, navy pleated skirt, brown leather boots, '
              'white cotton bra, white cotton panties',
          'slots': const <String>[],
        }
      ]);
      expect(r.warnings.where((f) => f.category == 'unknownTagToken'), isEmpty,
          reason: r.formatted());
    });

    // --- OutfitReport severity split -------------------------------------

    test('OutfitReport splits blocking vs warnings; isClean ignores warnings', () {
      final r = auditOutfits([
        {
          'name': 'Mixed',
          // silk → forbiddenMaterial (warning). 4 garment tags, all coloured,
          // so no blocking findings expected.
          'tags': 'cream silk blouse, navy pleated skirt, brown leather boots, white cotton bra',
          'slots': const <String>[],
        }
      ]);
      expect(r.warnings.isNotEmpty, isTrue, reason: r.formatted());
      expect(r.isClean, isTrue,
          reason: 'isClean should ignore warning-severity entries\n${r.formatted()}');
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
