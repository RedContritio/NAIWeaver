import 'dart:math';

/// Hands out `<prefix><n>` ids for references and vibes that never collide
/// with the ids already in a list, including lists restored from presets or
/// session snapshots (which may hold gaps such as `ref_1, ref_2`).
class ReferenceIdAllocator {
  ReferenceIdAllocator(this.prefix);

  final String prefix;
  int _next = 0;

  String next() => '$prefix${_next++}';

  /// Moves the counter past every `<prefix><n>` id in [items] and gives a
  /// fresh id to each item whose id already appeared earlier in the list.
  List<T> adopt<T>(
    List<T> items, {
    required String Function(T item) idOf,
    required T Function(T item, String id) withId,
  }) {
    final pattern = RegExp('^${RegExp.escape(prefix)}(\\d+)\$');
    for (final item in items) {
      final n = int.tryParse(pattern.firstMatch(idOf(item))?.group(1) ?? '');
      if (n != null) _next = max(_next, n + 1);
    }
    final seen = <String>{};
    return [
      for (final item in items)
        seen.add(idOf(item)) ? item : withId(item, next()),
    ];
  }
}
