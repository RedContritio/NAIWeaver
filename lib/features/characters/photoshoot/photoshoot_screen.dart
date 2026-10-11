import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/widgets/browser_native_selectable_text.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../../core/widgets/ui/app_sheet.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/ui/app_tabs.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../gallery/ui/image_detail_view.dart';
import '../../auth/backend_auth_notifier.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../generation/widgets/quote_confirm_dialog.dart';
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
      final closet = context.read<CharacterLibraryNotifier>().closetFor(
        widget.characterId,
      );
      // Resolve the requested outfit; if its id is stale/missing, fall back to
      // the first outfit so the Dress tab, the DRESS badge, and SAVE all agree
      // on the same outfit (otherwise the panel shows closet.first while save
      // silently no-ops and the badge reads 0).
      final resolved =
          closet.where((o) => o.id == _selectedOutfitId).firstOrNull ??
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
      final posesJson = await rootBundle.loadString(
        'assets/photoshoot/poses.json',
      );
      final envsJson = await rootBundle.loadString(
        'assets/photoshoot/environments.json',
      );
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
    showAppSnackBar(context, context.l.photoshootOutfitStateSaved);
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

    final poseTags = _collectPresetTags(
      _poses,
      _selectedPoseIds,
      _customPoseCtrl.text,
    );
    if (poseTags.isNotEmpty) parts.add(poseTags);

    final envTags = _collectPresetTags(
      _environments,
      _selectedEnvIds,
      _customEnvCtrl.text,
    );
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
    final outfit =
        _workingOutfit ??
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
    return context.read<CharacterLibraryNotifier>().negativeExpansionFor(
      character,
      outfit,
    );
  }

  String _styleTagsFor(String? id, SavedCharacter character) {
    if (id == null) return '';
    if (id == 'character') return character.artistTag.trim();
    final found = _kStyleBundles.firstWhere(
      (b) => b.id == id,
      orElse: () => const _StyleBundle(id: '', tags: ''),
    );
    return found.tags;
  }

  String _collectPresetTags(
    List<_PresetEntry> presets,
    Set<String> selected,
    String custom,
  ) {
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
    if (!canGenerateImage(context)) {
      showErrorSnackBar(context, context.l.gatewayErrPermissionDenied);
      return;
    }
    final gen = context.read<GenerationNotifier>();
    final auth = useBackendGateway ? context.read<BackendAuthNotifier>() : null;
    // The photoshoot's own prompts go straight to the generation: the main
    // editor's boxes (and what the user types there meanwhile) are not
    // borrowed, so there is nothing to restore afterwards. Without character
    // or outfit negatives the main negative prompt applies, as before. SEND
    // intentionally copies the prompts to the main editor.
    final negatives = _assembledNegativePrompt();
    // Drop focus + collapse the drawer so the freshly-generated image is visible.
    FocusScope.of(context).unfocus();
    setState(() => _drawerExpanded = false);
    final outcome = await gen.generate(
      prompt: prompt,
      negativePrompt: negatives.isEmpty ? null : negatives,
      confirmQuote: (confirmation) => confirmQuoteChange(context, confirmation),
    );
    unawaited(auth?.refreshSession());
    if (!mounted || outcome.declined) return;
    // Judge by what happened to the images, not by the call returning.
    if (outcome.authFailed) {
      showErrorSnackBar(context, context.l.mainAuthError);
    } else if (outcome.succeeded) {
      showAppSnackBar(context, context.l.photoshootGenerated);
    } else {
      showErrorSnackBar(
        context,
        context.l.photoshootGenerationFailed(
          outcome.errorMessage ?? context.l.generationFailedFallback,
        ),
      );
    }
  }

  void _sendToMainPrompt(String prompt) {
    if (prompt.isEmpty) return;
    final gen = context.read<GenerationNotifier>();
    // SEND is an explicit "to the main prompt": it replaces the main prompt
    // with the photoshoot's and carries the character/outfit negatives over,
    // appended (de-duplicated) to the main negative prompt. It goes through
    // the shared character insertion so the negatives follow the same rules
    // as every other insert path.
    gen.insertCharacterTags(
      prompt,
      _assembledNegativePrompt(),
      target: 'main',
      replaceMainPrompt: true,
    );
    // The messenger sits above the route, so the toast outlives the pop.
    showAppSnackBar(context, context.l.photoshootSentToMain);
    Navigator.of(context).pop();
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
        appBar: AppBar(title: Text(context.l.photoshootTitle)),
        body: EmptyState(message: context.l.photoshootCharacterNotFound),
      );
    }
    final closet = lib.closetFor(widget.characterId);
    final outfit =
        _workingOutfit ??
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
    final drawerBottom = keyboardOpen
        ? (keyboardInset - bottomInset).clamp(0.0, mediaH)
        : 0.0;
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
            Text(
              context.l.photoshootTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(13),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              character.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(10)),
            ),
          ],
        ),
        actions: [
          // Outfit switcher lives in the bar so it never costs a scroll.
          TextButton.icon(
            onPressed: closet.isEmpty
                ? null
                : () => _pickOutfit(closet, outfit),
            icon: Icon(
              Icons.checkroom,
              size: VisionMetrics.iconMedium,
              color: t.accent,
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                outfit?.name ?? context.l.photoshootNoOutfit,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: outfit == null ? t.textMinimal : t.textPrimary,
                  fontSize: t.fontSize(11),
                ),
              ),
            ),
          ),
          const SizedBox(width: VisionMetrics.space4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // -- Image preview fills everything above the collapsed drawer. ----
            // collapsedH no longer includes bottomInset (SafeArea owns it), so
            // the preview's bottom edge sits flush with the collapsed drawer top.
            Positioned.fill(bottom: collapsedH, child: _previewPane(t)),

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
              child: _drawer(
                t,
                character,
                closet,
                outfit,
                assembled,
                expanded: drawerExpanded,
                handleH: handleH,
                actionBarH: actionBarH,
              ),
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
      padding: const EdgeInsets.fromLTRB(
        VisionMetrics.space12,
        VisionMetrics.space8,
        VisionMetrics.space12,
        VisionMetrics.space8,
      ),
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
                  color: t.surfaceMid,
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  border: Border.all(
                    color: loading ? t.accent : t.borderSubtle,
                    width: loading ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bytes != null)
                      Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        // Hold the prior frame during a new decode so the
                        // preview doesn't flash to blank between generations.
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      )
                    else
                      EmptyState(
                        icon: Icons.camera_outlined,
                        message: context.l.photoshootPreviewPlaceholder,
                      ),
                    if (loading)
                      ColoredBox(
                        color: t.background.withValues(
                          alpha: VisionMetrics.opacityScrim,
                        ),
                        child: const LoadingState(),
                      ),
                    if (bytes != null && !loading)
                      Positioned(
                        right: VisionMetrics.space8,
                        bottom: VisionMetrics.space8,
                        child: AppPill(
                          icon: Icons.fullscreen,
                          text: context.l.photoshootTapToView,
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: VisionMetrics.space8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: VisionMetrics.space8),
                itemBuilder: (_, i) {
                  final f = recent[i].file;
                  return GestureDetector(
                    onTap: () => _openFullViewer(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        VisionMetrics.radius4,
                      ),
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
                          child: Icon(
                            Icons.broken_image,
                            size: VisionMetrics.iconMedium,
                            color: t.textMinimal,
                          ),
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

  Widget _drawer(
    VisionTokens t,
    SavedCharacter character,
    List<ClosetOutfit> closet,
    ClosetOutfit? outfit,
    String assembled, {
    required bool expanded,
    required double handleH,
    required double actionBarH,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(VisionMetrics.radius12),
        ),
        border: Border.all(color: t.borderStrong),
        boxShadow: [
          BoxShadow(
            color: t.background.withValues(alpha: VisionMetrics.opacityScrim),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
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
                    borderRadius: BorderRadius.circular(VisionMetrics.radius2),
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
    final l = context.l;
    String label(String text, int count) => count > 0 ? '$text ($count)' : text;
    final dressCount = (_workingOutfit != null) ? 1 : 0;
    // The controller drives the pages; the tab bar only mirrors its index.
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) => AppTabBar<int>(
        options: [
          AppOption(value: 0, label: label(l.photoshootTabDress, dressCount)),
          AppOption(value: 1, label: label(l.photoshootTabScene, _sceneCount)),
          AppOption(value: 2, label: l.photoshootTabPrompt),
        ],
        selected: _tabController.index,
        onChanged: _tabController.animateTo,
      ),
    );
  }

  // -- Tab: Dress ------------------------------------------------------------

  Widget _dressTab(VisionTokens t, ClosetOutfit? outfit) {
    if (outfit == null) {
      return EmptyState(message: context.l.photoshootNoOutfitHint);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VisionMetrics.space16,
        VisionMetrics.space12,
        VisionMetrics.space16,
        VisionMetrics.space16,
      ),
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
        const SizedBox(height: VisionMetrics.space8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _saveStateToOutfit,
            icon: Icon(
              Icons.save_outlined,
              size: VisionMetrics.iconSmall,
              color: t.accent,
            ),
            label: Text(
              context.l.photoshootSaveState,
              style: TextStyle(
                color: t.accent,
                fontSize: t.fontSize(9),
                letterSpacing: 1,
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(
        VisionMetrics.space16,
        VisionMetrics.space12,
        VisionMetrics.space16,
        VisionMetrics.space24,
      ),
      children: [
        _stylePicker(t, character),
        const SizedBox(height: VisionMetrics.space16),
        _presetSection(
          t,
          title: context.l.photoshootSectionPose,
          presets: _poses,
          selected: _selectedPoseIds,
          customCtrl: _customPoseCtrl,
          hint: context.l.photoshootCustomPoseHint,
        ),
        const SizedBox(height: VisionMetrics.space16),
        _presetSection(
          t,
          title: context.l.photoshootSectionEnvironment,
          presets: _environments,
          selected: _selectedEnvIds,
          customCtrl: _customEnvCtrl,
          hint: context.l.photoshootCustomEnvHint,
        ),
      ],
    );
  }

  // -- Tab: Prompt -----------------------------------------------------------

  Widget _promptTab(VisionTokens t, String assembled) {
    final l = context.l;
    final tagCount = assembled.isEmpty ? 0 : assembled.split(',').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VisionMetrics.space16,
        VisionMetrics.space12,
        VisionMetrics.space16,
        VisionMetrics.space16,
      ),
      children: [
        SectionTitle(
          l.photoshootAssembledPrompt,
          t: t,
          variant: SectionTitleVariant.compact,
          trailing: Text(
            l.photoshootTagCount(tagCount),
            style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: AppPanel(
            variant: AppPanelVariant.raised,
            child: BrowserNativeSelectableText(
              text: assembled.isEmpty ? l.photoshootEmptyPrompt : assembled,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: t.fontSize(12),
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: VisionMetrics.space12),
        Text(
          l.photoshootPromptBuiltFrom,
          style: TextStyle(
            color: t.textMinimal,
            fontSize: t.fontSize(9),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // -- Action bar (always visible) -------------------------------------------

  Widget _actionBar(
    VisionTokens t,
    String assembled, {
    required double height,
  }) {
    final canGen = assembled.isNotEmpty;
    final gen = context.watch<GenerationNotifier>();
    final loading = gen.state.isLoading;
    return Container(
      height: height,
      padding: const EdgeInsets.all(VisionMetrics.space12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: (canGen && !loading)
                  ? () => _generate(assembled)
                  : null,
              icon: loading
                  ? SizedBox(
                      width: VisionMetrics.iconSmall,
                      height: VisionMetrics.iconSmall,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.accent,
                      ),
                    )
                  : const Icon(
                      Icons.auto_awesome,
                      size: VisionMetrics.iconMedium,
                    ),
              label: Text(
                loading
                    ? context.l.photoshootGenerating
                    : context.l.photoshootGenerate,
                style: TextStyle(fontSize: t.fontSize(11), letterSpacing: 1),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: t.surfaceHigh,
                elevation: 0,
                minimumSize: Size.fromHeight(context.hitSize),
              ),
            ),
          ),
          const SizedBox(width: VisionMetrics.space8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canGen ? () => _sendToMainPrompt(assembled) : null,
              icon: Icon(
                Icons.exit_to_app,
                size: VisionMetrics.iconSmall,
                color: t.accent,
              ),
              label: Text(
                context.l.photoshootSend,
                style: TextStyle(
                  color: t.accent,
                  fontSize: t.fontSize(10),
                  letterSpacing: 1,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.accent),
                minimumSize: Size.fromHeight(context.hitSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Pieces ----------------------------------------------------------------

  Future<void> _pickOutfit(
    List<ClosetOutfit> closet,
    ClosetOutfit? current,
  ) async {
    final chosen = await showAppSheet<ClosetOutfit>(
      context: context,
      builder: (ctx) {
        final t = ctx.t;
        return AppPickerSheet(
          title: ctx.l.photoshootSelectOutfit,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in closet)
                ListTile(
                  title: Text(
                    o.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(13),
                      fontWeight: o.id == current?.id
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: o.id == current?.id
                      ? Icon(
                          Icons.check,
                          size: VisionMetrics.iconMedium,
                          color: t.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (chosen != null && chosen.id != current?.id) _selectOutfit(chosen);
  }

  Widget _stylePicker(VisionTokens t, SavedCharacter character) {
    final l = context.l;
    final hasCharacterArtist = character.artistTag.trim().isNotEmpty;
    final options = <AppOption<String?>>[
      AppOption(value: null, label: l.commonNone),
      if (hasCharacterArtist)
        AppOption(value: 'character', label: l.photoshootStyleCharacterDefault),
      for (final b in _kStyleBundles)
        AppOption(value: b.id, label: _styleLabel(l, b.id)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          l.photoshootSectionStyle,
          t: t,
          variant: SectionTitleVariant.compact,
        ),
        AppSegmented<String?>(
          options: options,
          selected: _selectedStyle,
          onChanged: (id) => setState(() => _selectedStyle = id),
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
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title,
          t: t,
          variant: SectionTitleVariant.compact,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.isNotEmpty)
                Text(
                  l.photoshootSelectedCount(selected.length),
                  style: TextStyle(color: t.accent, fontSize: t.fontSize(8)),
                ),
              if (!_presetsLoaded)
                SizedBox(
                  width: VisionMetrics.iconSmall,
                  height: VisionMetrics.iconSmall,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                )
              else if (selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(selected.clear),
                  child: Text(
                    l.photoshootClear,
                    style: TextStyle(
                      color: t.textMinimal,
                      fontSize: t.fontSize(8),
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (presets.isEmpty && _presetsLoaded)
          Text(
            l.photoshootNoPresets,
            style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
          )
        else
          Wrap(
            spacing: VisionMetrics.space8,
            runSpacing: VisionMetrics.space8,
            children: [
              for (final p in presets)
                FilterChip(
                  label: Text(p.label),
                  selected: selected.contains(p.id),
                  showCheckmark: false,
                  onSelected: (on) => setState(() {
                    if (on) {
                      selected.add(p.id);
                    } else {
                      selected.remove(p.id);
                    }
                  }),
                ),
            ],
          ),
        const SizedBox(height: VisionMetrics.space8),
        TextField(
          controller: customCtrl,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: t.textMinimal,
              fontSize: t.fontSize(11),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: VisionMetrics.space12,
              vertical: VisionMetrics.space12,
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.borderSubtle),
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent),
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  String _styleLabel(AppLocalizations l, String id) => switch (id) {
    'anime' => l.photoshootStyleAnime,
    'painterly' => l.photoshootStylePainterly,
    'photoreal' => l.photoshootStylePhotoreal,
    'sketch' => l.photoshootStyleSketch,
    'watercolor' => l.photoshootStyleWatercolor,
    'ink' => l.photoshootStyleInk,
    _ => id,
  };
}

class _PresetEntry {
  final String id;
  final String label;
  final String tags;

  const _PresetEntry({
    required this.id,
    required this.label,
    required this.tags,
  });

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
  final String tags;
  const _StyleBundle({required this.id, required this.tags});
}

/// A small set of curated artist-tag bundles. Intentionally short; users pick
/// or override per-character via the artistTag field.
const List<_StyleBundle> _kStyleBundles = [
  _StyleBundle(id: 'anime', tags: 'anime coloring'),
  _StyleBundle(id: 'painterly', tags: 'painterly, soft brush'),
  _StyleBundle(id: 'photoreal', tags: 'realistic, photorealistic'),
  _StyleBundle(id: 'sketch', tags: 'sketch, pencil drawing'),
  _StyleBundle(
    id: 'watercolor',
    tags: 'watercolor (medium), traditional media',
  ),
  _StyleBundle(id: 'ink', tags: 'ink (medium), monochrome'),
];
