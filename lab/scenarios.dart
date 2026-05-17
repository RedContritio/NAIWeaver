// Hand-picked scenarios for the prompt lab. Each scenario covers a different
// axis we want to evaluate: vibe, era, location, gender, count. Edit / add
// freely — these are intentionally cheap to change.

import 'package:naiweaver/features/characters/gen/character_gen_data.dart';
import 'package:naiweaver/features/characters/gen/character_gen_service.dart';

class LabScenario {
  /// Stable id used to name the run file: `<id>_<timestamp>.json`.
  final String id;
  final String description;
  final CharacterGenForm form;
  const LabScenario({
    required this.id,
    required this.description,
    required this.form,
  });
}

/// Lookup helper used by run_lab.dart.
LabScenario? findScenario(String id) {
  for (final s in kLabScenarios) {
    if (s.id == id) return s;
  }
  return null;
}

CharacterVibe _vibe(String id) =>
    kCharacterVibes.firstWhere((v) => v.id == id, orElse: () => kCharacterVibes.first);

final List<LabScenario> kLabScenarios = <LabScenario>[
  // -- Modern ----------------------------------------------------------------
  LabScenario(
    id: 'modern_tokyo_mysterious_f',
    description: 'Modern Tokyo, female, mysterious — bri\'s canonical reference (Sendai-ish).',
    form: CharacterGenForm(
      gender: 'female',
      vibe: _vibe('mysterious'),
      era: kFallbackEras.first, // present-day
      location: 'Sendai, Japan',
      nsfw: false,
      imageStyle: CharacterImageStyle.anime,
      wardrobeCount: 7,
    ),
  ),
  LabScenario(
    id: 'modern_lisbon_friendly_f',
    description: 'Modern Portugal, female, friendly — tests language flavour + casual outfits.',
    form: CharacterGenForm(
      gender: 'female',
      vibe: _vibe('friendly'),
      era: kFallbackEras.first,
      location: 'Lisbon, Portugal',
      wardrobeCount: 5,
    ),
  ),
  LabScenario(
    id: 'modern_nyc_chaotic_m',
    description: 'Modern NYC, male, chaotic — checks male underwear path (should not produce bras).',
    form: CharacterGenForm(
      gender: 'male',
      vibe: _vibe('chaotic'),
      era: kFallbackEras.first,
      location: 'Brooklyn, New York',
      wardrobeCount: 5,
    ),
  ),

  // -- Historical ------------------------------------------------------------
  LabScenario(
    id: 'victorian_zenith_f',
    description: 'Victorian London, female — checks era VOCABULARY + corset/chemise base layer.',
    form: CharacterGenForm(
      gender: 'female',
      vibe: _vibe('mysterious'),
      era: const CharacterEra(
        id: 'victorian-zenith',
        year: 1888,
        label: 'Victorian Zenith',
        quote: 'Steam, fog, and gaslight.',
      ),
      location: 'Whitechapel, London',
      wardrobeCount: 5,
    ),
  ),
  LabScenario(
    id: 'pax_romana_intimidating_m',
    description: 'Ancient Rome, male, intimidating — checks linen-loincloth base + no modern items.',
    form: CharacterGenForm(
      gender: 'male',
      vibe: _vibe('intimidating'),
      era: const CharacterEra(
        id: 'pax-romana',
        year: 117,
        label: 'Pax Romana',
      ),
      location: 'Ostia',
      wardrobeCount: 5,
    ),
  ),
  LabScenario(
    id: 'roaring_twenties_f',
    description: '1920s NYC, female — flapper-era (bra/panties transition zone).',
    form: CharacterGenForm(
      gender: 'female',
      vibe: _vibe('romantic'),
      era: const CharacterEra(
        id: 'roaring-twenties',
        year: 1925,
        label: 'The Roaring Twenties',
        quote: 'Jazz and bootleg gin.',
      ),
      location: 'Harlem, New York',
      wardrobeCount: 5,
    ),
  ),

  // -- Stress tests ---------------------------------------------------------
  LabScenario(
    id: 'wardrobe_only_modern_f',
    description: 'Wardrobe-only path with a pre-baked body tag set (no main-gen call).',
    form: CharacterGenForm(
      gender: 'female',
      vibe: _vibe('surprise_me'),
      era: kFallbackEras.first,
      location: '',
      wardrobeCount: 7,
    ),
  ),
];
