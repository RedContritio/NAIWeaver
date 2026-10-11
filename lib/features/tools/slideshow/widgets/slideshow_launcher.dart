import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/manager_list_tile.dart';
import '../../../../core/widgets/manager_shell.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/ui/app_states.dart';
import '../../../../core/widgets/ui/app_tabs.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../../../gallery/providers/gallery_notifier.dart';
import '../models/slideshow_config.dart';
import '../providers/slideshow_notifier.dart';
import '../../../../core/jukebox/jukebox_registry.dart';
import '../../../../core/jukebox/models/jukebox_song.dart';
import '../../jukebox/widgets/jukebox_panel.dart';
import '../../widgets/shelf_toggle.dart';
import 'image_source_selector.dart';
import 'slideshow_player.dart';
import '../../../../core/theme/vision_metrics.dart';

class SlideshowLauncher extends StatefulWidget {
  const SlideshowLauncher({super.key});

  @override
  State<SlideshowLauncher> createState() => _SlideshowLauncherState();
}

class _SlideshowLauncherState extends State<SlideshowLauncher> {
  bool _showingEditor = false;

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SlideshowNotifier>();
    final t = context.t;

    // Every edit is saved immediately, so no unsaved-changes guard is needed.
    return ManagerMasterDetailShell(
      showDetail: _showingEditor && notifier.activeConfig != null,
      masterHeader: _buildHeader(context, notifier, t),
      detailTitle: notifier.activeConfig?.name.toUpperCase() ?? '',
      onCloseDetail: () => setState(() => _showingEditor = false),
      master: _buildConfigList(context, notifier, t),
      detail: _buildEditor(context, notifier, t),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    return Container(
      padding: const EdgeInsets.all(VisionMetrics.space16),
      width: double.infinity,
      color: t.surfaceHigh,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l.slideshowTitle,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(12),
              letterSpacing: 4,
              fontWeight: FontWeight.w900,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.music_note,
                  size: VisionMetrics.iconMedium,
                  color: t.accent,
                ),
                tooltip: l.jukeboxTitle,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => Dialog.fullscreen(
                      backgroundColor: t.background,
                      child: const JukeboxPanel(),
                    ),
                  );
                },
              ),
              TextButton.icon(
                onPressed: () => _playAll(context, notifier),
                icon: Icon(
                  Icons.play_arrow,
                  size: VisionMetrics.iconMedium,
                  color: t.accent,
                ),
                label: Text(
                  l.slideshowPlayAll,
                  style: TextStyle(
                    color: t.accent,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: t.accent.withValues(
                    alpha: VisionMetrics.opacityHover,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: VisionMetrics.space16,
                    vertical: VisionMetrics.space8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigList(
    BuildContext context,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    return Container(
      color: t.surfaceMid,
      child: Column(
        children: [
          ManagerListHeader(
            title: l.slideshowConfigs,
            actions: [
              ManagerIconButton(
                icon: Icons.add,
                tooltip: l.slideshowNewConfig,
                onPressed: () {
                  notifier.createNew();
                  _save(context, notifier);
                  setState(() => _showingEditor = true);
                },
              ),
            ],
          ),
          Divider(height: 1, color: t.textMinimal),
          Expanded(
            child: notifier.configs.isEmpty
                ? EmptyState(message: l.slideshowNoConfigs)
                : ListView.builder(
                    itemCount: notifier.configs.length,
                    itemBuilder: (context, index) {
                      final config = notifier.configs[index];
                      final isSelected = notifier.activeConfig?.id == config.id;
                      return ManagerListTile(
                        title: config.name.toUpperCase(),
                        subtitle: _sourceLabel(context, config),
                        selected: isSelected,
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.slideshow,
                              size: VisionMetrics.iconSmall,
                              color: isSelected
                                  ? t.textPrimary
                                  : t.secondaryText,
                            ),
                            if (notifier.defaultConfigId == config.id)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: VisionMetrics.space4,
                                ),
                                child: Icon(
                                  Icons.star,
                                  size: VisionMetrics.iconSmall,
                                  color: t.accent,
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          notifier.selectConfig(config);
                          setState(() => _showingEditor = true);
                        },
                        inlineActions: [
                          ManagerIconButton(
                            icon: Icons.play_arrow,
                            tooltip: l.slideshowPlay,
                            color: t.accent,
                            onPressed: () => _play(context, notifier, config),
                          ),
                        ],
                        menuActions: [
                          ManagerListAction(
                            label: l.commonDelete,
                            icon: Icons.delete_outline,
                            destructive: true,
                            onSelected: () => _showDeleteConfirm(
                              context,
                              notifier,
                              config,
                              t,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    final config = notifier.activeConfig;
    if (config == null) {
      return EmptyState(message: l.slideshowSelectOrCreate);
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(VisionMetrics.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                _sectionTitle(l.slideshowNameLabel, t),
                _textField(
                  value: config.name,
                  onChanged: (val) {
                    notifier.updateConfig(config.copyWith(name: val));
                    _save(context, notifier);
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Image source
                _sectionTitle(l.slideshowSourceLabel, t),
                ImageSourceSelector(
                  config: config,
                  onChanged: (updated) {
                    notifier.updateConfig(updated);
                    _save(context, notifier);
                  },
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Transition
                _sectionTitle(l.slideshowTransition, t),
                _buildTransitionGrid(context, config, notifier, t),
                const SizedBox(height: VisionMetrics.space16),
                _buildSlider(
                  label: l.slideshowTransitionDuration,
                  value: config.transitionDuration,
                  min: 0.3,
                  max: 2.0,
                  suffix: 's',
                  onChanged: (v) {
                    notifier.updateConfig(
                      config.copyWith(transitionDuration: v),
                    );
                    _save(context, notifier);
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Timing
                _sectionTitle(l.slideshowTiming, t),
                _buildSlider(
                  label: l.slideshowSlideDuration,
                  value: config.slideDuration,
                  min: 3.0,
                  max: 30.0,
                  suffix: 's',
                  onChanged: (v) {
                    notifier.updateConfig(config.copyWith(slideDuration: v));
                    _save(context, notifier);
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Ken Burns
                _sectionTitle(l.slideshowKenBurns, t),
                _buildToggle(
                  label: l.slideshowEnabled,
                  value: config.kenBurnsEnabled && !config.manualZoomEnabled,
                  onChanged: (v) {
                    notifier.updateConfig(
                      config.copyWith(
                        kenBurnsEnabled: v,
                        manualZoomEnabled: v ? false : config.manualZoomEnabled,
                      ),
                    );
                    _save(context, notifier);
                  },
                  t: t,
                ),
                if (config.kenBurnsEnabled && !config.manualZoomEnabled)
                  _buildSlider(
                    label: l.slideshowIntensity,
                    value: config.kenBurnsIntensity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      notifier.updateConfig(
                        config.copyWith(kenBurnsIntensity: v),
                      );
                      _save(context, notifier);
                    },
                    t: t,
                  ),
                const SizedBox(height: VisionMetrics.space16),

                // Manual zoom
                _buildToggle(
                  label: l.slideshowManualZoom,
                  value: config.manualZoomEnabled,
                  onChanged: (v) {
                    notifier.updateConfig(
                      config.copyWith(
                        manualZoomEnabled: v,
                        kenBurnsEnabled: v ? false : config.kenBurnsEnabled,
                      ),
                    );
                    _save(context, notifier);
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Playback
                _sectionTitle(l.slideshowPlayback, t),
                _buildToggle(
                  label: l.slideshowShuffle,
                  value: config.shuffleEnabled,
                  onChanged: (v) {
                    notifier.updateConfig(config.copyWith(shuffleEnabled: v));
                    _save(context, notifier);
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space8),
                _buildToggle(
                  label: l.slideshowLoop,
                  value: config.loopEnabled,
                  onChanged: (v) {
                    notifier.updateConfig(config.copyWith(loopEnabled: v));
                    _save(context, notifier);
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Music
                _sectionTitle(l.slideshowMusic, t),
                _buildToggle(
                  label: l.slideshowEnableMusic,
                  value: config.musicEnabled,
                  onChanged: (v) {
                    notifier.updateConfig(config.copyWith(musicEnabled: v));
                    _save(context, notifier);
                  },
                  t: t,
                ),
                if (config.musicEnabled) ...[
                  const SizedBox(height: VisionMetrics.space12),
                  // Song picker
                  _buildMusicSongPicker(config, notifier, t),
                  const SizedBox(height: VisionMetrics.space12),
                  // Category filter
                  _buildMusicCategoryPicker(config, notifier, t),
                  const SizedBox(height: VisionMetrics.space12),
                  // Volume
                  _buildSlider(
                    label: l.slideshowMusicVolume,
                    value: config.musicVolume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      notifier.updateConfig(config.copyWith(musicVolume: v));
                      _save(context, notifier);
                    },
                    t: t,
                  ),
                  const SizedBox(height: VisionMetrics.space12),
                  // SoundFont picker
                  _buildMusicSoundFontPicker(config, notifier, t),
                  const SizedBox(height: VisionMetrics.space12),
                  // Karaoke toggle
                  _buildToggle(
                    label: l.slideshowKaraoke,
                    value: config.karaokeEnabled,
                    onChanged: (v) {
                      notifier.updateConfig(config.copyWith(karaokeEnabled: v));
                      _save(context, notifier);
                    },
                    t: t,
                  ),
                ],
                const SizedBox(height: VisionMetrics.space24),

                // Default slideshow
                _sectionTitle(l.slideshowDefault, t),
                _buildToggle(
                  label: l.slideshowUseAsDefault,
                  value: notifier.defaultConfigId == config.id,
                  onChanged: (v) {
                    final newId = v ? config.id : null;
                    notifier.setDefaultConfigId(newId);
                    context.read<PreferencesService>().setDefaultSlideshowId(
                      newId,
                    );
                  },
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space24),
              ],
            ),
          ),
        ),
        // Play button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(VisionMetrics.space16),
          color: t.surfaceMid,
          child: ElevatedButton.icon(
            onPressed: () => _play(context, notifier, config),
            icon: const Icon(Icons.play_arrow, size: VisionMetrics.iconMedium),
            label: Text(
              l.slideshowPlay,
              style: TextStyle(
                fontSize: t.fontSize(11),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.background,
              padding: const EdgeInsets.symmetric(
                vertical: VisionMetrics.space12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransitionGrid(
    BuildContext context,
    SlideshowConfig config,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    final types = TransitionType.values;
    final labels = [
      l.slideshowTransFade,
      l.slideshowTransSlideL,
      l.slideshowTransSlideR,
      l.slideshowTransSlideUp,
      l.slideshowTransZoom,
      l.slideshowTransXZoom,
    ];
    return AppSegmented<TransitionType>(
      options: [
        for (var i = 0; i < types.length; i++)
          AppOption(value: types[i], label: labels[i]),
      ],
      selected: config.transition,
      onChanged: (type) {
        notifier.updateConfig(config.copyWith(transition: type));
        _save(context, notifier);
      },
    );
  }

  Widget _sectionTitle(String title, VisionTokens t) =>
      SectionTitle(title, t: t);

  Widget _textField({
    required String value,
    required ValueChanged<String> onChanged,
    required VisionTokens t,
  }) {
    return _NameField(
      // A different config gets a fresh field; edits of the same one keep it.
      key: ValueKey(context.read<SlideshowNotifier>().activeConfig?.id),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    String? suffix,
    required ValueChanged<double> onChanged,
    required VisionTokens t,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(8),
                letterSpacing: 1,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)}${suffix ?? ''}',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(9),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        VisionSlider(
          value: value,
          onChanged: onChanged,
          min: min,
          max: max,
          activeColor: t.textPrimary.withValues(
            alpha: VisionMetrics.opacityPressed,
          ),
          inactiveColor: t.borderSubtle,
          thumbColor: t.textPrimary,
          thumbRadius: 6,
          overlayRadius: 12,
        ),
      ],
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VisionTokens t,
  }) {
    return ShelfToggle(label: label, value: value, onChanged: onChanged);
  }

  String _sourceLabel(BuildContext context, SlideshowConfig config) {
    final l = context.l;
    switch (config.sourceType) {
      case ImageSourceType.allImages:
        return l.slideshowSourceAllImages;
      case ImageSourceType.album:
        return l.slideshowSourceAlbum;
      case ImageSourceType.favorites:
        return l.slideshowSourceFavorites;
      case ImageSourceType.custom:
        return l.slideshowSourceCustom(config.customImageBasenames.length);
    }
  }

  void _play(
    BuildContext context,
    SlideshowNotifier notifier,
    SlideshowConfig config,
  ) {
    final gallery = context.read<GalleryNotifier>();
    final playlist = notifier.buildPlaylist(config, gallery);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowPlayer(config: config, playlist: playlist),
      ),
    );
  }

  void _playAll(BuildContext context, SlideshowNotifier notifier) {
    final config =
        notifier.defaultConfig ??
        const SlideshowConfig(id: '_quick_play', name: 'Quick Play');
    _play(context, notifier, config);
  }

  void _save(BuildContext context, SlideshowNotifier notifier) {
    final prefs = context.read<PreferencesService>();
    prefs.setSlideshowConfigs(notifier.toJsonString());
  }

  Widget _buildMusicSongPicker(
    SlideshowConfig config,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    final songs = JukeboxRegistry.allSongs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l.slideshowSongsHint,
          style: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(7),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: VisionMetrics.space8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: songs.map((song) {
            final selected = config.musicSongIds.contains(song.id);
            return InkWell(
              onTap: () {
                final ids = List<String>.from(config.musicSongIds);
                if (selected) {
                  ids.remove(song.id);
                } else {
                  ids.add(song.id);
                }
                notifier.updateConfig(config.copyWith(musicSongIds: ids));
                _save(context, notifier);
              },
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              child: Container(
                constraints: BoxConstraints(minHeight: context.hitSize),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? t.accent.withValues(alpha: VisionMetrics.opacityPressed)
                      : t.borderSubtle,
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  border: Border.all(
                    color: selected ? t.accent : Colors.transparent,
                  ),
                ),
                child: Text(
                  song.title.toUpperCase(),
                  style: TextStyle(
                    color: selected ? t.accent : t.textSecondary,
                    fontSize: t.fontSize(7),
                    letterSpacing: 0.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMusicCategoryPicker(
    SlideshowConfig config,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    final categories = [null, ...SongCategory.values];
    final labels = [
      context.l.slideshowCategoryAll,
      ...SongCategory.values.map((c) => JukeboxRegistry.categoryDisplayName(c)),
    ];
    return AppSegmented<int?>(
      options: [
        for (var i = 0; i < categories.length; i++)
          AppOption(value: categories[i]?.index, label: labels[i]),
      ],
      selected: config.musicCategoryIndex,
      onChanged: (catIndex) {
        if (catIndex == null) {
          notifier.updateConfig(config.copyWith(clearMusicCategory: true));
        } else {
          notifier.updateConfig(config.copyWith(musicCategoryIndex: catIndex));
        }
        _save(context, notifier);
      },
    );
  }

  Widget _buildMusicSoundFontPicker(
    SlideshowConfig config,
    SlideshowNotifier notifier,
    VisionTokens t,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l.slideshowSoundFont,
          style: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(8),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: VisionMetrics.space8),
        AppSegmented<String?>(
          options: [
            AppOption(value: null, label: context.l.slideshowSoundFontDefault),
            for (final sf in JukeboxRegistry.allSoundFonts)
              AppOption(value: sf.id, label: sf.name),
          ],
          selected: config.musicSoundFontId,
          onChanged: (sfId) {
            if (sfId == null) {
              notifier.updateConfig(
                config.copyWith(clearMusicSoundFontId: true),
              );
            } else {
              notifier.updateConfig(config.copyWith(musicSoundFontId: sfId));
            }
            _save(context, notifier);
          },
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirm(
    BuildContext context,
    SlideshowNotifier notifier,
    SlideshowConfig config,
    VisionTokens t,
  ) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.slideshowDeleteConfig,
      message: l.slideshowDeleteConfirm(config.name.toUpperCase()),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true && context.mounted) {
      notifier.deleteConfig(config.id);
      _save(context, notifier);
    }
  }
}

/// Name input that owns its controller, so typing is never reset by rebuilds.
class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_NameField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      style: TextStyle(
        color: t.textSecondary,
        fontSize: t.fontSize(13),
        height: 1.5,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: t.borderSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(VisionMetrics.space12),
      ),
    );
  }
}
