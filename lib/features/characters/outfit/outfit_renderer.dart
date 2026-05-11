/// Renders per-slot items + states to a Danbooru tag string for image
/// generation, with underwear concealment and nudity consolidation.
///
/// Ported from bri.'s `render_items_to_tags` / `apply_concealment` /
/// `render_items_for_pov` in `app/outfit_slots.py`.
library;

import 'outfit_classifier.dart';
import 'outfit_slots.dart';
import 'outfit_slots_data.dart';

/// Result of rendering: the comma-joined tag string and whether the look is
/// "dishevelled" (any NSFW-triggering slot non-intact AND visible — caller
/// should append `nsfw`).
class RenderedOutfit {
  final String tags;
  final bool isDishevelled;
  const RenderedOutfit(this.tags, this.isDishevelled);
}

// -- Concealing-slot state tables ------------------------------------------
const Set<String> _braConcealingTopStates = {'intact', 'unbuttoned'};
const Set<String> _braConcealingDressTopStates = {'intact', 'unbuttoned'};
const Set<String> _pantiesConcealingBottomStates = {'intact', 'unbuttoned'};
const Set<String> _pantiesConcealingDressBottomStates = {'intact'};
const Set<String> _braConcealingArmorStates = {'intact'};
const Set<String> _pantiesConcealingArmorStates = {'intact'};
const Set<String> _topConcealingArmorStates = {'intact'};
const Set<String> _closedFrontConcealingStates = {'intact'};

String _g(Map<String, dynamic>? m) => ((m?['garment'] as String?) ?? '').toLowerCase();
String _state(Map<String, dynamic>? m) => (m?['state'] as String?) ?? 'intact';

bool _isOuterwearClosedFront(String garment) {
  final g = garment.toLowerCase();
  return closedFrontOuterwearKeywords.any((kw) => g.contains(kw));
}

bool _outerwearConcealsChest(Map<String, dynamic> items) {
  final outer = items['outerwear'];
  if (outer is! Map<String, dynamic>) return false;
  if (!_closedFrontConcealingStates.contains(_state(outer))) return false;
  return _isOuterwearClosedFront(_g(outer));
}

bool _isBraConcealed(Map<String, dynamic> items) {
  final dress = items['dress'];
  if (dress is Map<String, dynamic> &&
      _braConcealingDressTopStates
          .contains((dress['top_state'] as String?) ?? 'intact')) {
    return true;
  }
  final top = items['top'];
  if (top is Map<String, dynamic> &&
      _braConcealingTopStates.contains(_state(top))) {
    return true;
  }
  final armor = items['armor'];
  if (armor is Map<String, dynamic> &&
      _braConcealingArmorStates.contains(_state(armor))) {
    return true;
  }
  if (_outerwearConcealsChest(items)) return true;
  return false;
}

bool _isPantiesConcealed(Map<String, dynamic> items) {
  final dress = items['dress'];
  if (dress is Map<String, dynamic> &&
      _pantiesConcealingDressBottomStates
          .contains((dress['bottom_state'] as String?) ?? 'intact')) {
    return true;
  }
  final bottom = items['bottom'];
  if (bottom is Map<String, dynamic> &&
      _pantiesConcealingBottomStates.contains(_state(bottom))) {
    return true;
  }
  final armor = items['armor'];
  if (armor is Map<String, dynamic> &&
      _pantiesConcealingArmorStates.contains(_state(armor))) {
    return true;
  }
  final outer = items['outerwear'];
  if (outer is Map<String, dynamic> &&
      _closedFrontConcealingStates.contains(_state(outer))) {
    final g = _g(outer);
    if (longClosedFrontOuterwearKeywords.any((kw) => g.contains(kw))) {
      return true;
    }
  }
  return false;
}

bool _isTopConcealedByArmor(Map<String, dynamic> items) {
  final armor = items['armor'];
  if (armor is! Map<String, dynamic>) return false;
  return _topConcealingArmorStates.contains(_state(armor));
}

bool _braProvidesCoverage(Map<String, dynamic> items) {
  final bra = items['bra'];
  if (bra is! Map<String, dynamic>) return false;
  if (_state(bra) != 'intact') return false;
  return !_isBraConcealed(items);
}

bool _pantiesProvideCoverage(Map<String, dynamic> items) {
  final panties = items['panties'];
  if (panties is! Map<String, dynamic>) return false;
  if (_state(panties) != 'intact') return false;
  return !_isPantiesConcealed(items);
}

bool _legwearCoversFeet(Map<String, dynamic> items) {
  final lw = items['legwear'];
  if (lw is! Map<String, dynamic>) return false;
  return _state(lw) == 'intact';
}

bool _isCompletelyNudeEligible(Map<String, dynamic> items) {
  for (final slot in ['legwear', 'footwear', 'headwear', 'outerwear']) {
    final it = items[slot];
    if (it is! Map<String, dynamic>) continue;
    if (_state(it) != 'removed') return false;
  }
  final acc = items['accessory'];
  if (acc is Map<String, dynamic>) {
    final subs = acc['items'];
    if (subs is Map && subs.isNotEmpty) {
      if (subs.values.any(
          (s) => (s is Map ? (s['state'] ?? 'intact') : 'intact') != 'removed')) {
        return false;
      }
    } else if (_state(acc) != 'removed') {
      return false;
    }
  }
  return true;
}

// -- Per-(slot, state) tag rendering ---------------------------------------

String _renderTop(String garment, String base, String state) {
  switch (state) {
    case 'intact':
      return base;
    case 'unbuttoned':
      return '$base, unbuttoned shirt, partially unbuttoned';
    case 'open':
      return '$base, open shirt, open clothes';
    case 'lifted':
      return '$base, shirt lift, clothes lift';
  }
  return base;
}

String _renderBottom(String garment, String base, String state) {
  if (state == 'intact') return base;
  final isSkirt = garment.contains('skirt');
  switch (state) {
    case 'unbuttoned':
      return isSkirt ? base : '$base, unbuttoned pants';
    case 'lifted':
      return isSkirt ? '$base, skirt lift, clothes lift' : '$base, clothes lift';
    case 'pulled_down':
      return isSkirt ? '$base, clothes pull' : '$base, pants pull, clothes pull';
    case 'around_ankles':
      return '$base, pants around one leg';
  }
  return base;
}

String _renderBra(String garment, String base, String state) {
  switch (state) {
    case 'intact':
      return base;
    case 'pulled_down':
      return '$base, bra pull';
    case 'aside':
      return '$base, bra aside';
  }
  return base;
}

String _renderPanties(String garment, String base, String state) {
  switch (state) {
    case 'intact':
      return base;
    case 'pulled_down':
      return '$base, panties pull, clothes pull';
    case 'aside':
      return '$base, panties aside, clothing aside';
    case 'around_ankles':
      return '$base, panties around one leg, panties around ankles';
  }
  return base;
}

String _renderOuterwear(String garment, String base, String state) {
  switch (state) {
    case 'intact':
      return base;
    case 'unbuttoned':
      return '$base, unbuttoned jacket';
    case 'open':
      return '$base, open jacket, open clothes';
  }
  return base;
}

String _renderLegwear(String garment, String base, String state) {
  switch (state) {
    case 'intact':
      return base;
    case 'pulled_down':
      return '$base, stocking pull';
    case 'around_ankles':
      return '$base, socks around one leg';
  }
  return base;
}

String _renderDress(Map<String, dynamic> item) {
  final base = (item['base_tags'] as String?)?.isNotEmpty == true
      ? item['base_tags'] as String
      : (item['garment'] as String?) ?? 'dress';
  final topState = (item['top_state'] as String?) ?? 'intact';
  final botState = (item['bottom_state'] as String?) ?? 'intact';

  if (topState == 'removed' && botState == 'removed') return '';

  final parts = <String>[base];
  switch (topState) {
    case 'unbuttoned':
      parts.add('unbuttoned dress');
      break;
    case 'open':
      parts.addAll(['open dress', 'open clothes']);
      break;
    case 'pulled_down':
      parts.addAll(['dress pull', 'clothes pull']);
      break;
    case 'removed':
      parts.add('dress off the shoulder');
      break;
  }
  switch (botState) {
    case 'lifted':
      parts.addAll(['dress lift', 'clothes lift']);
      break;
    case 'aside':
      parts.addAll(['clothing aside', 'dress aside']);
      break;
    case 'removed':
      parts.add('dress hiked up');
      break;
  }
  return parts.where((p) => p.isNotEmpty).join(', ');
}

typedef _SimpleRenderer = String Function(String garment, String base, String state);

const Map<String, _SimpleRenderer> _simpleRenderers = {
  'top': _renderTop,
  'bottom': _renderBottom,
  'bra': _renderBra,
  'panties': _renderPanties,
  'outerwear': _renderOuterwear,
  'legwear': _renderLegwear,
};

/// Render `{slot: itemMap}` → ([RenderedOutfit]).
RenderedOutfit renderItemsToTags(Map<String, dynamic> items) {
  final parts = <String>[];
  var dishevelled = false;
  var torsoBare = false;
  var pelvisBare = false;

  for (final slot in kRenderOrder) {
    final it = items[slot];
    if (it is! Map<String, dynamic>) continue;

    if (slot == 'bra' && _isBraConcealed(items)) continue;
    if (slot == 'panties' && _isPantiesConcealed(items)) continue;
    if (slot == 'top' && _isTopConcealedByArmor(items)) continue;

    final nonIntact = itemIsNonIntact(slot, it);
    if (nonIntact && kNsfwTriggeringSlots.contains(slot)) dishevelled = true;

    if (slot == 'dress') {
      final rendered = _renderDress(it);
      if (rendered.isNotEmpty) parts.add(rendered);
      final topState = (it['top_state'] as String?) ?? 'intact';
      final botState = (it['bottom_state'] as String?) ?? 'intact';
      if (topState == 'removed' && botState == 'removed') {
        if (!_braProvidesCoverage(items)) torsoBare = true;
        if (!_pantiesProvideCoverage(items)) pelvisBare = true;
      } else if (topState == 'pulled_down' && !_braProvidesCoverage(items)) {
        parts.add('breasts out');
      }
      continue;
    }

    final state = _state(it);
    if (slot == 'accessory') {
      final subs = it['items'];
      if (subs is Map && subs.isNotEmpty) {
        final kept = <String>[];
        subs.forEach((subKey, sub) {
          final s = (sub is Map ? (sub['state'] as String?) : null) ?? 'intact';
          if (s != 'removed') kept.add(subKey as String);
        });
        if (kept.isNotEmpty) parts.add(kept.join(', '));
      } else {
        if (state != 'removed') parts.add((it['base_tags'] as String?) ?? '');
      }
      continue;
    }

    if (state == 'removed') {
      if (slot == 'top') {
        if (_braProvidesCoverage(items)) continue;
        torsoBare = true;
        continue;
      }
      if (slot == 'bottom') {
        if (_pantiesProvideCoverage(items)) continue;
        pelvisBare = true;
        continue;
      }
      if (slot == 'footwear' && _legwearCoversFeet(items)) continue;
      final nudity = kRemovedNudityTag[slot] ?? '';
      if (nudity.isNotEmpty) parts.add(nudity);
      continue;
    }

    final renderer = _simpleRenderers[slot];
    if (renderer == null) {
      // headwear / footwear
      parts.add((it['base_tags'] as String?) ?? '');
      continue;
    }
    parts.add(renderer(_g(it), (it['base_tags'] as String?) ?? '', state));
  }

  if (torsoBare && pelvisBare) {
    if (_isCompletelyNudeEligible(items)) {
      parts.removeWhere(
          (p) => p == 'no bra' || p == 'no panties' || p == 'barefoot');
      parts.add('completely nude');
    } else {
      parts.removeWhere((p) => p == 'no bra' || p == 'no panties');
      parts.add('nude');
    }
  } else if (torsoBare) {
    parts.removeWhere((p) => p == 'no bra');
    parts.add('topless');
  } else if (pelvisBare) {
    parts.removeWhere((p) => p == 'no panties');
    parts.add('bottomless');
  }

  return RenderedOutfit(parts.where((p) => p.isNotEmpty).join(', '), dishevelled);
}

/// Run a flat outfit tag string through classify + render. All items treated as
/// intact; the only effective change vs the raw string is hiding underwear
/// covered by an intact outer layer. Returns `('', false)` for empty input.
RenderedOutfit applyConcealment(String? rawTags) {
  if (rawTags == null || rawTags.trim().isEmpty) {
    return const RenderedOutfit('', false);
  }
  final items = classifyOutfitTags(rawTags);
  if (items.isEmpty) return RenderedOutfit(rawTags, false);
  final rendered = renderItemsToTags(items);
  return RenderedOutfit(
    rendered.tags.isNotEmpty ? rendered.tags : rawTags,
    rendered.isDishevelled,
  );
}

/// POV variant: drop headwear+accessory always, footwear unless [feetInFrame],
/// then render. (Harmless if NAIWeaver never does POV crops.)
String renderItemsForPov(Map<String, dynamic>? items, {required bool feetInFrame}) {
  if (items == null || items.isEmpty) return '';
  final filtered = Map<String, dynamic>.from(items);
  filtered.remove('headwear');
  filtered.remove('accessory');
  if (!feetInFrame) filtered.remove('footwear');
  return renderItemsToTags(filtered).tags;
}
