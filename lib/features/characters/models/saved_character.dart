import '../../generation/models/nai_character.dart';

/// A reusable saved persona — a library entity distinct from the per-generation
/// [NaiCharacter] (which is a scene slot). A [SavedCharacter] can be converted
/// into a [NaiCharacter] via [toNaiCharacter].
///
/// One JSON file per character at `<appSupport>/characters/{id}.json`. Its
/// closet (list of outfits) lives separately at
/// `<appSupport>/characters/{id}/closet.json`.
///
/// Tag buckets contain NO CLOTHING — clothing is the closet's job.
class SavedCharacter {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// "female" | "male" | "nonbinary" | "" — informational only.
  final String gender;

  // Tag buckets (comma-separated Danbooru tags). NO clothing.
  final String baseTags; // 1girl/1boy/1other, ethnicity, age, permanent marks
  final String faceTags; // eye colour/shape, eyebrows, nose, lips, structure
  final String hairTags; // colour, length, style, texture
  final String bodyTags_; // build, proportions, chest size

  // NSFW sub-buckets — empty by default; used by NSFW prompt assembly + the
  // outfit-state "exposure" logic later.
  final String nsfwTop;
  final String nsfwBottom;
  final String nsfwAlways;

  /// Natural-language permanent physical description (future photoreal path;
  /// not used by NAI's tag-based image gen).
  final String characterDescription;

  /// Optional long-form personality / "soul" document (second-person "You
  /// are…"). Populated by the character generator; not used by image gen but
  /// kept around so the persona is portable/editable. Empty for hand-built
  /// characters.
  final String soulMd;

  /// One-sentence personality summary, if generated. Empty otherwise.
  final String personalitySummary;

  final String artistTag;
  final String stylePrefix;

  /// Optional UI tint {accent, accentSecondary, bg} as hex strings.
  final String? themeAccent;
  final String? themeAccentSecondary;
  final String? themeBg;

  /// Which closet outfit is the "default" (used when the autocomplete entry is
  /// just `[name]` with no outfit qualifier). Null ⇒ first outfit / none.
  final String? primaryOutfitId;

  final String notes;

  SavedCharacter({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.gender = '',
    this.baseTags = '',
    this.faceTags = '',
    this.hairTags = '',
    String bodyTags = '',
    this.nsfwTop = '',
    this.nsfwBottom = '',
    this.nsfwAlways = '',
    this.characterDescription = '',
    this.soulMd = '',
    this.personalitySummary = '',
    this.artistTag = '',
    this.stylePrefix = '',
    this.themeAccent,
    this.themeAccentSecondary,
    this.themeBg,
    this.primaryOutfitId,
    this.notes = '',
  })  : bodyTags_ = bodyTags,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// The body-shape tags (NO clothing, NO face/hair split exposed) — used for
  /// the autocomplete expansion prefix. = [base, face, hair, body] non-empty
  /// joined by ", ".
  String get derivedBodyTags => [baseTags, faceTags, hairTags, bodyTags_]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(', ');

  /// The clothing-free NSFW additions, joined.
  String get derivedNsfwAlways => nsfwAlways.trim();

  static String _genId() {
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    // 12 hex chars, low bits of microsecond clock — collision-safe enough for
    // a hand-managed local library.
    return ms.length >= 12 ? ms.substring(ms.length - 12) : ms.padLeft(12, '0');
  }

  factory SavedCharacter.create({required String name}) =>
      SavedCharacter(id: _genId(), name: name);

  factory SavedCharacter.fromJson(Map<String, dynamic> json) {
    final tags = (json['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final theme = (json['theme'] as Map?)?.cast<String, dynamic>();
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    String s(dynamic v) => v is String ? v : '';
    return SavedCharacter(
      id: s(json['id']).isNotEmpty ? s(json['id']) : _genId(),
      name: s(json['name']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      gender: s(json['gender']),
      baseTags: s(tags['base']),
      faceTags: s(tags['face']),
      hairTags: s(tags['hair']),
      bodyTags: s(tags['body']),
      nsfwTop: s(tags['nsfwTop']),
      nsfwBottom: s(tags['nsfwBottom']),
      nsfwAlways: s(tags['nsfwAlways']),
      characterDescription: s(json['characterDescription']),
      soulMd: s(json['soulMd']),
      personalitySummary: s(json['personalitySummary']),
      artistTag: s(json['artistTag']),
      stylePrefix: s(json['stylePrefix']),
      themeAccent: theme != null && theme['accent'] is String
          ? theme['accent'] as String
          : null,
      themeAccentSecondary: theme != null && theme['accentSecondary'] is String
          ? theme['accentSecondary'] as String
          : null,
      themeBg: theme != null && theme['bg'] is String
          ? theme['bg'] as String
          : null,
      primaryOutfitId:
          json['primaryOutfitId'] is String ? json['primaryOutfitId'] as String : null,
      notes: s(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'gender': gender,
        'tags': {
          'base': baseTags,
          'face': faceTags,
          'hair': hairTags,
          'body': bodyTags_,
          'nsfwTop': nsfwTop,
          'nsfwBottom': nsfwBottom,
          'nsfwAlways': nsfwAlways,
        },
        'characterDescription': characterDescription,
        if (soulMd.isNotEmpty) 'soulMd': soulMd,
        if (personalitySummary.isNotEmpty) 'personalitySummary': personalitySummary,
        'artistTag': artistTag,
        'stylePrefix': stylePrefix,
        if (themeAccent != null || themeAccentSecondary != null || themeBg != null)
          'theme': {
            if (themeAccent != null) 'accent': themeAccent,
            if (themeAccentSecondary != null) 'accentSecondary': themeAccentSecondary,
            if (themeBg != null) 'bg': themeBg,
          },
        'primaryOutfitId': primaryOutfitId,
        'notes': notes,
      };

  SavedCharacter copyWith({
    String? name,
    DateTime? updatedAt,
    String? gender,
    String? baseTags,
    String? faceTags,
    String? hairTags,
    String? bodyTags,
    String? nsfwTop,
    String? nsfwBottom,
    String? nsfwAlways,
    String? characterDescription,
    String? soulMd,
    String? personalitySummary,
    String? artistTag,
    String? stylePrefix,
    Object? themeAccent = _sentinel,
    Object? themeAccentSecondary = _sentinel,
    Object? themeBg = _sentinel,
    Object? primaryOutfitId = _sentinel,
    String? notes,
  }) {
    return SavedCharacter(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      gender: gender ?? this.gender,
      baseTags: baseTags ?? this.baseTags,
      faceTags: faceTags ?? this.faceTags,
      hairTags: hairTags ?? this.hairTags,
      bodyTags: bodyTags ?? bodyTags_,
      nsfwTop: nsfwTop ?? this.nsfwTop,
      nsfwBottom: nsfwBottom ?? this.nsfwBottom,
      nsfwAlways: nsfwAlways ?? this.nsfwAlways,
      characterDescription: characterDescription ?? this.characterDescription,
      soulMd: soulMd ?? this.soulMd,
      personalitySummary: personalitySummary ?? this.personalitySummary,
      artistTag: artistTag ?? this.artistTag,
      stylePrefix: stylePrefix ?? this.stylePrefix,
      themeAccent: themeAccent == _sentinel ? this.themeAccent : themeAccent as String?,
      themeAccentSecondary: themeAccentSecondary == _sentinel
          ? this.themeAccentSecondary
          : themeAccentSecondary as String?,
      themeBg: themeBg == _sentinel ? this.themeBg : themeBg as String?,
      primaryOutfitId: primaryOutfitId == _sentinel
          ? this.primaryOutfitId
          : primaryOutfitId as String?,
      notes: notes ?? this.notes,
    );
  }

  /// Build a generation-slot [NaiCharacter] from this persona + an optional
  /// pre-rendered outfit tag string (already run through concealment).
  NaiCharacter toNaiCharacter({
    String outfitTags = '',
    bool dishevelled = false,
    String uc = '',
    NaiCoordinate? center,
  }) {
    final parts = <String>[
      if (stylePrefix.trim().isNotEmpty) stylePrefix.trim(),
      if (derivedBodyTags.isNotEmpty) derivedBodyTags,
      if (outfitTags.trim().isNotEmpty) outfitTags.trim(),
      if (dishevelled) 'nsfw',
      if (artistTag.trim().isNotEmpty) artistTag.trim(),
    ];
    return NaiCharacter(
      name: name,
      prompt: parts.join(', '),
      uc: uc,
      center: center ?? NaiCoordinate(x: 0.5, y: 0.5),
    );
  }
}

const Object _sentinel = Object();
