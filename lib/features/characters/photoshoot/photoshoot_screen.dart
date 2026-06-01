import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../gallery/ui/image_detail_view.dart';
import '../../generation/providers/generation_notifier.dart';
import '../models/closet_outfit.dart';
import '../models/saved_character.dart';
import '../outfit/outfit_renderer.dart';
import '../outfit/widgets/outfit_state_panel.dart';
import '../providers/character_library_notifier.dart';

/// A single-screen photoshoot mode: pick a saved character + outfit, dress them
/// in-place ephemerally, pick style/pose/environment, preview the assembled
/// prompt, and kick the existing image-gen pipeline.
///
/// Layout mirrors the main editor: a large image preview fills the top, and the
/// controls live in a pull-up drawer at the bottom (Dress / Scene / Prompt
/// tabs) with a persistent GENERATE/SEND action bar so the call-to-action never
/// scrolls away.
///
/// Working outfit state is session-only — the saved closet is untouched unless
/// the user taps "Save state to outfit".
class PhotoshootScreen extends StatefulWidget {
  final String characterId;
  final String initialOutfitId;

  const PhotoshootScreen({
    super.key,
    required this.characterId,
    required this.initialOutfitId,
  });

  @override
  State<PhotoshootScreen> createState() => _PhotoshootScreenState();
}

class _PhotoshootScreenState extends State<PhotoshootScreen>
    with SingleTickerProviderStateMixin {
  /// Working copy of the outfit — mutations here do NOT auto-persist. They are
  /// written back to the library only via `_saveStateToOutfit`.
  ClosetOutfit? _workingOutfit;

  String? _selectedOutfitId;

  String? _selectedStyle; // artist-tag bundle id, or null
  final Set<String> _selectedPoseIds = {};
  final Set<String> _selectedEnvIds = {};
  final TextEditingController _customPoseCtrl = TextEditingController();
  final TextEditingController _customEnvCtrl = TextEditingController();

  List<_PresetEntry> _poses = const [];
  List<_PresetEntry> _environments = const [];
  bool _presetsLoaded = false;

  /// Pull-up drawer state.
  bool _drawerExpanded = true;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _selectedOutfitId = widget.initialOutfitId;
    _tabController = TabController(length: 3, vsync: this);
    _loadPresets();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workingOutfit == null) {
      final closet = context.read<CharacterLibraryNotifier>().closetFor(widget.characterId);
      // Resolve the requested outfit; if its id is stale/missing, fall back to
      // the first outfit so the Dress tab, the DRESS badge, and SAVE all agree
      // on the same outfit (otherwise the panel shows closet.first while save
      // silently no-ops and the badge reads 0).
      final resolved = closet.where((o) => o.id == _selectedOutfitId).firstOrNull ??
          (closet.isNotEmpty ? closet.first : null);
      if (resolved != null) {
        _workingOutfit = resolved;
        _selectedOutfitId = resolved.id;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customPoseCtrl.dispose();
    _customEnvCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    try {
      final posesJson = await rootBundle.loadString('assets/photoshoot/poses.json');
      final envsJson = await rootBundle.loadString('assets/photoshoot/environments.json');
      final poses = (jsonDecode(posesJson) as List)
          .cast<Map<String, dynamic>>()
          .map(_PresetEntry.fromJson)
          .toList();
      final envs = (jsonDecode(envsJson) as List)
          .cast<Map<String, dynamic>>()
          .map(_PresetEntry.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _poses = poses;
        _environments = envs;
        _presetsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _presetsLoaded = true);
    }
  }

  void _selectOutfit(ClosetOutfit outfit) {
    setState(() {
      _selectedOutfitId = outfit.id;
      _workingOutfit = outfit;
    });
  }

  Future<void> _saveStateToOutfit() async {
    final outfit = _workingOutfit;
    if (outfit == null) return;
    final lib = context.read<CharacterLibraryNotifier>();
    await lib.updateOutfit(widget.characterId, outfit);
    if (!mounted) return;
    showAppSnackBar(context, 'OUTFIT STATE SAVED');
  }

  String _assembledPrompt(SavedCharacter character, ClosetOutfit? outfit) {
    final parts = <String>[];

    final styleTags = _styleTagsFor(_selectedStyle, character);
    if (styleTags.isNotEmpty) parts.add(styleTags);

    final body = character.derivedBodyTags;
    if (body.isNotEmpty) parts.add(body);

    bool dishevelled = false;
    if (outfit != null) {
      final items = outfit.items;
      if (items != null && items.isNotEmpty) {
        final r = renderItemsToTags(items.cast<String, dynamic>());
        if (r.tags.isNotEmpty) parts.add(r.tags);
        dishevelled = r.isDishevelled;
      } else if (outfit.tags.trim().isNotEmpty) {
        final r = applyConcealment(outfit.tags);
        if (r.tags.isNotEmpty) parts.add(r.tags);
        dishevelled = r.isDishevelled;
      }
    }

    final poseTags = _collectPresetTags(_poses, _selectedPoseIds, _customPoseCtrl.text);
    if (poseTags.isNotEmpty) parts.add(poseTags);

    final envTags = _collectPresetTags(_environments, _selectedEnvIds, _customEnvCtrl.text);
    if (envTags.isNotEmpty) parts.add(envTags);

    if (dishevelled) parts.add('nsfw');
    return parts.join(', ');
  }

  /// Resolves the character + working outfit currently in play, mirroring the
  /// resolution order in [build]. Returns null character if it was deleted.
  (SavedCharacter?, ClosetOutfit?) _currentCharacterAndOutfit() {
    final lib = context.read<CharacterLibraryNotifier>();
    final character = lib.characterById(widget.characterId);
    final closet = lib.closetFor(widget.characterId);
    final outfit = _workingOutfit ??
        closet.where((o) => o.id == _selectedOutfitId).firstOrNull ??
        (closet.isNotEmpty ? closet.first : null);
    return (character, outfit);
  }

  /// Combined character + outfit negative tags for the current selection, so a
  /// photoshoot honors the per-character/per-outfit negatives the rest of the
  /// app respects. Empty when neither has any (or the character is gone).
  String _assembledNegativePrompt() {
    final (character, outfit) = _currentCharacterAndOutfit();
    if (character == null) return '';
    return context
        .read<CharacterLibraryNotifier>()
        .negativeExpansionFor(character, outfit);
  }

  String _styleTagsFor(String? id, SavedCharacter character) {
    if (id == null) return '';
    if (id == 'character') return character.artistTag.trim();
    final found = _kStyleBundles.firstWhere(
      (b) => b.id == id,
      orElse: () => const _StyleBundle(id: '', label: '', tags: ''),
    );
    return found.tags;
  }

  String _collectPresetTags(
      List<_PresetEntry> presets, Set<String> selected, String custom) {
    final picks = <String>[];
    for (final p in presets) {
      if (selected.contains(p.id)) picks.add(p.tags);
    }
    final c = custom.trim();
    if (c.isNotEmpty) picks.add(c);
    return picks.join(', ');
  }

  /// Count of active selections in each tab, for the badge in the tab label.
  int get _sceneCount =>
      _selectedPoseIds.length +
      _selectedEnvIds.length +
      (_selectedStyle != null ? 1 : 0) +
      (_customPoseCtrl.text.trim().isNotEmpty ? 1 : 0) +
      (_customEnvCtrl.text.trim().isNotEmpty ? 1 : 0);

  Future<void> _generate(String prompt) async {
    if (prompt.isEmpty) return;
    final gen = context.read<GenerationNotifier>();
    // generate() reads the prompt + negative prompt from the shared
    // controllers, so we must write both. Snapshot the user's main-screen
    // values and restore them afterwards so a photoshoot GENERATE (which stays
    // on this screen) doesn't silently wipe what they had typed on the main
    // editor. SEND intentionally keeps them.
    final savedMainPrompt = gen.promptController.text;
    final savedMainNegative = gen.negativePromptController.text;
    final negatives = _assembledNegativePrompt();
    gen.promptController.text = prompt;
    if (negatives.isNotEmpty) gen.negativePromptController.text = negatives;
    // Drop focus + collapse the drawer so the freshly-generated image is visible.
    FocusScope.of(context).unfocus();
    setState(() => _drawerExpanded = false);
    try {
      await gen.generate();
      if (!mounted) return;
      // generate() never throws — it swallows errors and records them on its
      // state. So check the state, not the (impossible) exception, to decide
      // whether it actually succeeded.
      final st = gen.state;
      if (st.hasAuthError) {
        showErrorSnackBar(context, 'AUTH ERROR — CHECK API KEY');
      } else if (st.errorMessage != null && st.errorMessage!.isNotEmpty) {
        showErrorSnackBar(context, 'GENERATION FAILED: ${st.errorMessage}');
      } else {
        showAppSnackBar(context, 'GENERATED');
      }
    } catch (e) {
      // Belt-and-braces: if generate() ever does throw, still surface it.
      if (!mounted) return;
      showErrorSnackBar(context, 'GENERATION FAILED: $e');
    } finally {
      gen.promptController.text = savedMainPrompt;
      gen.negativePromptController.text = savedMainNegative;
    }
  }

  void _sendToMainPrompt(String prompt) {
    if (prompt.isEmpty) return;
    final gen = context.read<GenerationNotifier>();
    // Capture the root messenger BEFORE popping — after pop, `context` belongs
    // to the dead route and ScaffoldMessenger.of(context) would attach the
    // snackbar to a disappearing messenger (it'd never show).
    final messenger = ScaffoldMessenger.of(context);
    final t = context.tRead;
    gen.promptController.text = prompt;
    // Carry the character/outfit negatives over too, appended (de-duplicated)
    // to whatever the main editor already has — matches the autocomplete
    // insert path so SEND doesn't drop the per-character negatives.
    TagSuggestionHelper.appendNegatives(
        gen.negativePromptController, _assembledNegativePrompt());
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text('SENT TO MAIN PROMPT',
          style: TextStyle(color: t.accentSuccess, fontSize: t.fontSize(11))),
      backgroundColor: const Color(0xFF0A1A0A),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: t.accentSuccess.withValues(alpha: 0.3)),
      ),
    ));
  }

  void _openFullViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImageDetailView(initialIndex: index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lib = context.watch<CharacterLibraryNotifier>();
    final character = lib.characterById(widget.characterId);
    if (character == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photoshoot')),
        body: const Center(child: Text('Character not found')),
      );
    }
    final closet = lib.closetFor(widget.characterId);
    final outfit = _workingOutfit ??
        closet.where((o) => o.id == _selectedOutfitId).firstOrNull ??
        (closet.isNotEmpty ? closet.first : null);
    final assembled = _assembledPrompt(character, outfit);

    final mediaH = MediaQuery.of(context).size.height;
    // SafeArea(top:false) below owns the bottom inset, so our in-Stack math is
    // measured from the top of the system nav bar — we must NOT add bottomInset
    // again (that was a double-count that left a nav-bar-sized gap).
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    // The soft keyboard height (measured from the true screen bottom, so it
    // already includes the nav-bar inset that SafeArea consumed). When it's up
    // we lift the drawer to sit on top of it and force the drawer expanded.
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardInset > 0;
    // Anchor offset for the drawer's bottom, inside SafeArea coordinates.
    final drawerBottom = keyboardOpen ? (keyboardInset - bottomInset).clamp(0.0, mediaH) : 0.0;
    const handleH = 30.0;
    const actionBarH = 60.0;
    final collapsedH = handleH + actionBarH;
    // Leave the fixed chrome (handle + tab bar + action bar) enough room that the
    // TabBarView never collapses to a sliver on short screens.
    final expandedH = (mediaH * 0.62).clamp(collapsedH + 140, mediaH);
    final drawerExpanded = _drawerExpanded || keyboardOpen;

    return Scaffold(
      backgroundColor: t.background,
      // We size and position the drawer above the keyboard ourselves (see
      // keyboardInset below), so don't let the Scaffold also shrink the body —
      // that would double-count the inset.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: t.surfaceHigh,
        iconTheme: IconThemeData(color: t.textSecondary),
        // Scale the toolbar with the user's font scale so the 2-line title can't
        // overflow the default 56dp bar at large scales.
        toolbarHeight: (56 * t.fontScale).clamp(56, 96),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PHOTOSHOOT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(13),
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            Text(character.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.textTertiary, fontSize: t.fontSize(10))),
          ],
        ),
        actions: [
          // Outfit switcher lives in the bar so it never costs a scroll.
          TextButton.icon(
            onPressed: closet.isEmpty ? null : () => _pickOutfit(closet, outfit),
            icon: Icon(Icons.checkroom, size: 15, color: t.accent),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                outfit?.name ?? '(no outfit)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: outfit == null ? t.textMinimal : t.textPrimary,
                    fontSize: t.fontSize(11)),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // -- Image preview fills everything above the collapsed drawer. ----
            // collapsedH no longer includes bottomInset (SafeArea owns it), so
            // the preview's bottom edge sits flush with the collapsed drawer top.
            Positioned.fill(
              bottom: collapsedH,
              child: _previewPane(t),
            ),

            // -- Pull-up controls drawer. -------------------------------------
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              left: 0,
              right: 0,
              // Lift the drawer to sit on top of the keyboard when it's open;
              // otherwise anchor flush to the SafeArea bottom.
              bottom: drawerBottom,
              height: drawerExpanded ? expandedH : collapsedH,
              child: _drawer(t, character, closet, outfit, assembled,
                  expanded: drawerExpanded,
                  handleH: handleH,
                  actionBarH: actionBarH),
            ),
          ],
        ),
      ),
    );
  }

  // -- Preview pane ----------------------------------------------------------

  Widget _previewPane(VisionTokens t) {
    final gen = context.watch<GenerationNotifier>();
    final gallery = context.watch<GalleryNotifier>();
    final bytes = gen.state.generatedImage;
    final loading = gen.state.isLoading;
    final recent = gallery.activeItems.take(12).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              // Tapping the big preview opens the full-screen gallery viewer at
              // the newest image (index 0 with the default dateDesc sort).
              onTap: recent.isEmpty ? null : () => _openFullViewer(0),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: t.surfaceMid.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: loading ? t.accent : t.borderSubtle,
                      width: loading ? 2 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bytes != null)
                      Image.memory(bytes,
                          fit: BoxFit.contain,
                          // Hold the prior frame during a new decode so the
                          // preview doesn't flash to blank between generations.
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium)
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_outlined,
                                size: 44,
                                color: t.textPrimary.withValues(alpha: 0.12)),
                            const SizedBox(height: 8),
                            Text('YOUR SHOT APPEARS HERE',
                                style: TextStyle(
                                    color: t.textMinimal,
                                    fontSize: t.fontSize(9),
                                    letterSpacing: 1.5)),
                          ],
                        ),
                      ),
                    if (loading)
                      Container(
                        color: t.background.withValues(alpha: 0.35),
                        child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: t.accent),
                        ),
                      ),
                    if (bytes != null && !loading)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: t.background.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen,
                                  size: 12, color: t.textSecondary),
                              const SizedBox(width: 3),
                              Text('TAP TO VIEW',
                                  style: TextStyle(
                                      color: t.textSecondary,
                                      fontSize: t.fontSize(8),
                                      letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final f = recent[i].file;
                  return GestureDetector(
                    onTap: () => _openFullViewer(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        f,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        cacheWidth: 112,
                        errorBuilder: (_, _, _) => Container(
                          width: 56,
                          height: 56,
                          color: t.surfaceMid,
                          child: Icon(Icons.broken_image,
                              size: 16, color: t.textMinimal),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -- Drawer ----------------------------------------------------------------

  Widget _drawer(VisionTokens t, SavedCharacter character,
      List<ClosetOutfit> closet, ClosetOutfit? outfit, String assembled,
      {required bool expanded,
      required double handleH,
      required double actionBarH}) {
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border.all(color: t.borderStrong),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          // The drag-to-expand/collapse gesture lives ONLY on the handle so it
          // never competes with the tabs' own vertical ListView scrolling.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _drawerExpanded = !_drawerExpanded),
            onVerticalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -300 && !_drawerExpanded) {
                setState(() => _drawerExpanded = true);
              }
              if (v > 300 && _drawerExpanded) {
                // Drop focus so the keyboard closes too.
                FocusScope.of(context).unfocus();
                setState(() => _drawerExpanded = false);
              }
            },
            child: SizedBox(
              height: handleH,
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          if (expanded)
            Expanded(
              child: Column(
                children: [
                  _tabBar(t),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _dressTab(t, outfit),
                        _sceneTab(t, character),
                        _promptTab(t, assembled),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _actionBar(t, assembled, height: actionBarH),
        ],
      ),
    );
  }

  Widget _tabBar(VisionTokens t) {
    Widget label(String text, int count) => Tab(
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  style: TextStyle(
                      fontSize: t.fontSize(10),
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold)),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          fontSize: t.fontSize(8),
                          color: t.accent,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        );

    final dressCount = (_workingOutfit != null) ? 1 : 0;
    return TabBar(
      controller: _tabController,
      labelColor: t.accent,
      unselectedLabelColor: t.textTertiary,
      indicatorColor: t.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: t.borderSubtle,
      tabs: [
        label('DRESS', dressCount),
        label('SCENE', _sceneCount),
        label('PROMPT', 0),
      ],
    );
  }

  // -- Tab: Dress ------------------------------------------------------------

  Widget _dressTab(VisionTokens t, ClosetOutfit? outfit) {
    if (outfit == null) {
      return _emptyHint(
          t, 'No outfit to dress — add one from the character editor.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      children: [
        OutfitStatePanel(
          key: ValueKey('photoshoot_state_${outfit.id}'),
          outfit: outfit,
          persistent: false,
          onChanged: (updated) => setState(() => _workingOutfit = updated),
          // Apply-to-prompt routes through the assembled prompt path instead of
          // writing into the controller directly — keeps the photoshoot prompt
          // self-contained.
          onApplyToPrompt: (_, _) {},
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _saveStateToOutfit,
            icon: Icon(Icons.save_outlined, size: 14, color: t.accent),
            label: Text('SAVE STATE TO OUTFIT',
                style: TextStyle(
                    color: t.accent,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1)),
          ),
        ),
      ],
    );
  }

  // -- Tab: Scene (style + pose + environment) -------------------------------

  Widget _sceneTab(VisionTokens t, SavedCharacter character) {
    return ListView(
      // Extra bottom room so the focused custom-tag field can scroll clear of
      // the action bar when the keyboard is up.
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _stylePicker(t, character),
        const SizedBox(height: 16),
        _presetSection(
          t,
          title: 'POSE',
          presets: _poses,
          selected: _selectedPoseIds,
          customCtrl: _customPoseCtrl,
          hint: 'custom pose tags…',
        ),
        const SizedBox(height: 16),
        _presetSection(
          t,
          title: 'ENVIRONMENT',
          presets: _environments,
          selected: _selectedEnvIds,
          customCtrl: _customEnvCtrl,
          hint: 'custom environment tags…',
        ),
      ],
    );
  }

  // -- Tab: Prompt -----------------------------------------------------------

  Widget _promptTab(VisionTokens t, String assembled) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      children: [
        Row(
          children: [
            Text('ASSEMBLED PROMPT',
                style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${assembled.isEmpty ? 0 : assembled.split(',').length} tags',
                style: TextStyle(
                    color: t.textMinimal, fontSize: t.fontSize(9))),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surfaceMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.borderSubtle),
          ),
          child: SelectableText(
            assembled.isEmpty ? '(empty)' : assembled,
            style: TextStyle(
                color: t.textPrimary, fontSize: t.fontSize(12), height: 1.4),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Built from: style → body → outfit → pose → environment. Adjust in the Dress and Scene tabs.',
          style: TextStyle(
              color: t.textMinimal, fontSize: t.fontSize(9), height: 1.4),
        ),
      ],
    );
  }

  // -- Action bar (always visible) -------------------------------------------

  Widget _actionBar(VisionTokens t, String assembled, {required double height}) {
    final canGen = assembled.isNotEmpty;
    final gen = context.watch<GenerationNotifier>();
    final loading = gen.state.isLoading;
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: (canGen && !loading) ? () => _generate(assembled) : null,
              icon: loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.accent),
                    )
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(loading ? 'GENERATING…' : 'GENERATE',
                  style:
                      TextStyle(fontSize: t.fontSize(11), letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: t.surfaceHigh,
                elevation: 0,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canGen ? () => _sendToMainPrompt(assembled) : null,
              icon: Icon(Icons.exit_to_app, size: 14, color: t.accent),
              label: Text('SEND',
                  style: TextStyle(
                      color: t.accent,
                      fontSize: t.fontSize(10),
                      letterSpacing: 1)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.accent),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Pieces ----------------------------------------------------------------

  Future<void> _pickOutfit(List<ClosetOutfit> closet, ClosetOutfit? current) async {
    final t = context.tRead;
    final chosen = await showModalBottomSheet<ClosetOutfit>(
      context: context,
      backgroundColor: t.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text('OUTFIT',
                    style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(9),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold)),
              ),
              for (final o in closet)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(o),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.borderSubtle)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(o.name,
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: t.fontSize(13),
                                  fontWeight: o.id == current?.id
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                        if (o.id == current?.id)
                          Icon(Icons.check, size: 18, color: t.accent),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (chosen != null && chosen.id != current?.id) _selectOutfit(chosen);
  }

  Widget _stylePicker(VisionTokens t, SavedCharacter character) {
    final hasCharacterArtist = character.artistTag.trim().isNotEmpty;
    final bundles = <_StyleBundle>[
      if (hasCharacterArtist)
        _StyleBundle(
            id: 'character',
            label: 'Character default',
            tags: character.artistTag.trim()),
      ..._kStyleBundles,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STYLE',
            style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(8),
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(t, 'none', selected: _selectedStyle == null,
                onTap: () => setState(() => _selectedStyle = null)),
            for (final b in bundles)
              _chip(t, b.label,
                  selected: _selectedStyle == b.id,
                  onTap: () => setState(() => _selectedStyle = b.id)),
          ],
        ),
      ],
    );
  }

  Widget _presetSection(
    VisionTokens t, {
    required String title,
    required List<_PresetEntry> presets,
    required Set<String> selected,
    required TextEditingController customCtrl,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(8),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (selected.isNotEmpty)
              Text('${selected.length} selected',
                  style: TextStyle(
                      color: t.accent, fontSize: t.fontSize(8))),
            const Spacer(),
            if (!_presetsLoaded)
              SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: t.accent))
            else if (selected.isNotEmpty)
              InkWell(
                onTap: () => setState(selected.clear),
                child: Text('CLEAR',
                    style: TextStyle(
                        color: t.textMinimal,
                        fontSize: t.fontSize(8),
                        letterSpacing: 1)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (presets.isEmpty && _presetsLoaded)
          Text('No presets available',
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in presets)
                _chip(t, p.label,
                    selected: selected.contains(p.id),
                    onTap: () => setState(() {
                          if (selected.contains(p.id)) {
                            selected.remove(p.id);
                          } else {
                            selected.add(p.id);
                          }
                        })),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: customCtrl,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(11)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.borderSubtle),
                borderRadius: BorderRadius.circular(4)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.accent),
                borderRadius: BorderRadius.circular(4)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _chip(VisionTokens t, String label,
      {required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.accent.withValues(alpha: 0.25) : t.surfaceMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? t.accent : t.borderSubtle,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? t.accent : t.textSecondary,
                fontSize: t.fontSize(10),
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _emptyHint(VisionTokens t, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(11))),
      ),
    );
  }
}

class _PresetEntry {
  final String id;
  final String label;
  final String tags;

  const _PresetEntry({required this.id, required this.label, required this.tags});

  factory _PresetEntry.fromJson(Map<String, dynamic> json) {
    return _PresetEntry(
      id: json['id'] as String,
      label: json['label'] as String,
      tags: json['tags'] as String,
    );
  }
}

class _StyleBundle {
  final String id;
  final String label;
  final String tags;
  const _StyleBundle({required this.id, required this.label, required this.tags});
}

/// A small set of curated artist-tag bundles. Intentionally short; users pick
/// or override per-character via the artistTag field.
const List<_StyleBundle> _kStyleBundles = [
  _StyleBundle(id: 'anime', label: 'Anime', tags: 'anime coloring'),
  _StyleBundle(id: 'painterly', label: 'Painterly', tags: 'painterly, soft brush'),
  _StyleBundle(id: 'photoreal', label: 'Photoreal', tags: 'realistic, photorealistic'),
  _StyleBundle(id: 'sketch', label: 'Sketch', tags: 'sketch, pencil drawing'),
  _StyleBundle(id: 'watercolor', label: 'Watercolour', tags: 'watercolor (medium), traditional media'),
  _StyleBundle(id: 'ink', label: 'Ink', tags: 'ink (medium), monochrome'),
];
