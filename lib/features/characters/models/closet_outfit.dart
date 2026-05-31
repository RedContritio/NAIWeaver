/// One outfit in a character's closet. One JSON file per character holds the
/// whole closet as a JSON array at `<appSupport>/characters/{id}/closet.json`.
///
/// Ported (adapted) from bri.'s closet outfit shape. The `items` field is the
/// lazily-populated, persisted per-slot outfit STATE (see outfit_classifier.dart
/// / outfit_renderer.dart) — i.e. the "current dressing state" of this outfit.
class ClosetOutfit {
  final String id;
  final String name; // evocative, e.g. "Rainy Day Chic"

  /// Comma-separated Danbooru CLOTHING tags only (4–7 garments typically).
  final String tags;

  /// Outfit-level negative tags (comma-separated). Appended to the character's
  /// own negative tags when this specific outfit is inserted via autocomplete.
  final String negativeTags;

  final List<String> seasons; // subset of spring/summer/fall/winter
  final List<String> weather; // subset of clear/cloudy/rain/snow/storm/hot/cold/mild/fog/humid
  final List<String> activities; // subset of casual/indoor/outdoor/formal/studying/exercise/shopping/date

  /// [minC, maxC]. Default [-10, 35].
  final List<num> temperatureRange;

  /// subset of morning/daytime/evening/sleep. [] = any.
  final List<String> slots;

  /// Reserved — the hairstyle-library subsystem isn't ported. Leave null.
  final String? hairStyleId;

  /// Parsed per-slot outfit state (`{slot: itemMap}`), or null if not yet
  /// classified. Persisted so the dressing state survives restart.
  final Map<String, dynamic>? items;

  /// One-shot flag: when true, the next delta applied to this outfit's state is
  /// scrubbed of removal-type transitions (used right after an outfit swap).
  /// Persisted false; mostly relevant to Phase B / future flows.
  final bool fresh;

  ClosetOutfit({
    required this.id,
    required this.name,
    this.tags = '',
    this.negativeTags = '',
    List<String>? seasons,
    List<String>? weather,
    List<String>? activities,
    List<num>? temperatureRange,
    List<String>? slots,
    this.hairStyleId,
    this.items,
    this.fresh = false,
  })  : seasons = seasons ?? const [],
        weather = weather ?? const [],
        activities = activities ?? const [],
        temperatureRange =
            (temperatureRange != null && temperatureRange.length == 2)
                ? temperatureRange
                : const [-10, 35],
        slots = slots ?? const [];

  static const List<String> kSeasons = ['spring', 'summer', 'fall', 'winter'];
  static const List<String> kWeather = [
    'clear',
    'cloudy',
    'rain',
    'snow',
    'storm',
    'hot',
    'cold',
    'mild',
    'fog',
    'humid'
  ];
  static const List<String> kActivities = [
    'casual',
    'indoor',
    'outdoor',
    'formal',
    'studying',
    'exercise',
    'shopping',
    'date'
  ];
  static const List<String> kTimeSlots = ['morning', 'daytime', 'evening', 'sleep'];

  static String _genId() {
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return ms.length >= 12 ? ms.substring(ms.length - 12) : ms.padLeft(12, '0');
  }

  factory ClosetOutfit.create({required String name, String tags = ''}) =>
      ClosetOutfit(id: _genId(), name: name, tags: tags);

  static List<String> _strList(dynamic v, {List<String>? allow}) {
    if (v is! List) return const [];
    final out = v.whereType<String>().map((s) => s.toLowerCase()).toList();
    if (allow == null) return out;
    return out.where(allow.contains).toList();
  }

  factory ClosetOutfit.fromJson(Map<String, dynamic> json) {
    final tr = json['temperatureRange'];
    List<num>? temp;
    if (tr is List && tr.length == 2 && tr[0] is num && tr[1] is num) {
      temp = [tr[0] as num, tr[1] as num];
    }
    return ClosetOutfit(
      id: (json['id'] is String && (json['id'] as String).isNotEmpty)
          ? json['id'] as String
          : _genId(),
      name: json['name'] is String ? json['name'] as String : '',
      tags: json['tags'] is String ? json['tags'] as String : '',
      negativeTags: json['negativeTags'] is String ? json['negativeTags'] as String : '',
      seasons: _strList(json['seasons'], allow: kSeasons),
      weather: _strList(json['weather'], allow: kWeather),
      activities: _strList(json['activities'], allow: kActivities),
      temperatureRange: temp,
      slots: _strList(json['slots'], allow: kTimeSlots),
      hairStyleId:
          json['hairStyleId'] is String ? json['hairStyleId'] as String : null,
      items: json['items'] is Map
          ? (json['items'] as Map).cast<String, dynamic>()
          : null,
      fresh: json['fresh'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags,
        if (negativeTags.isNotEmpty) 'negativeTags': negativeTags,
        'seasons': seasons,
        'weather': weather,
        'activities': activities,
        'temperatureRange': temperatureRange,
        'slots': slots,
        'hairStyleId': hairStyleId,
        if (items != null) 'items': items,
        'fresh': fresh,
      };

  ClosetOutfit copyWith({
    String? name,
    String? tags,
    String? negativeTags,
    List<String>? seasons,
    List<String>? weather,
    List<String>? activities,
    List<num>? temperatureRange,
    List<String>? slots,
    Object? hairStyleId = _sentinel,
    Object? items = _sentinel,
    bool? fresh,
  }) {
    return ClosetOutfit(
      id: id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      negativeTags: negativeTags ?? this.negativeTags,
      seasons: seasons ?? this.seasons,
      weather: weather ?? this.weather,
      activities: activities ?? this.activities,
      temperatureRange: temperatureRange ?? this.temperatureRange,
      slots: slots ?? this.slots,
      hairStyleId:
          hairStyleId == _sentinel ? this.hairStyleId : hairStyleId as String?,
      items: items == _sentinel
          ? this.items
          : items as Map<String, dynamic>?,
      fresh: fresh ?? this.fresh,
    );
  }

  /// Builds the closet outfit from JSON returned by the wardrobe-generation
  /// LLM (snake_case keys like `temperature_range`). Assigns a fresh id.
  factory ClosetOutfit.fromGeneratedJson(Map<String, dynamic> json) {
    final tr = json['temperature_range'] ?? json['temperatureRange'];
    List<num>? temp;
    if (tr is List && tr.length == 2 && tr[0] is num && tr[1] is num) {
      temp = [tr[0] as num, tr[1] as num];
    }
    return ClosetOutfit(
      id: _genId(),
      name: json['name'] is String ? (json['name'] as String).trim() : 'Outfit',
      tags: json['tags'] is String ? (json['tags'] as String).trim() : '',
      negativeTags: json['negativeTags'] is String
          ? (json['negativeTags'] as String).trim()
          : (json['negative_tags'] is String ? (json['negative_tags'] as String).trim() : ''),
      seasons: _strList(json['seasons'], allow: kSeasons),
      weather: _strList(json['weather'], allow: kWeather),
      activities: _strList(json['activities'], allow: kActivities),
      temperatureRange: temp,
      slots: _strList(json['slots'], allow: kTimeSlots),
    );
  }

  bool isGeneratedPrimary(Map<String, dynamic> json) =>
      json['primary'] == true || json['meet_cute'] == true;
}

const Object _sentinel = Object();
