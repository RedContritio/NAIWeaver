import 'package:flutter/material.dart';
import '../../../../core/jukebox/models/jukebox_song.dart';
import '../../../../core/jukebox/providers/jukebox_notifier.dart';
import '../../../../core/jukebox/widgets/fullscreen_visualizer.dart';
import '../../../../core/jukebox/widgets/karaoke_overlay.dart';
import '../../../../core/jukebox/widgets/karaoke_visualizer.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/widgets/ui/app_pill.dart';
import '../../../../core/widgets/ui/app_tone.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../../../../core/theme/vision_metrics.dart';

// ─────────────────────────────────────────
// Desktop Now Playing section
// ─────────────────────────────────────────

/// Desktop "Now Playing" section: song info, transport controls, and optional
/// inline karaoke visualizer preview.
class JukeboxNowPlaying extends StatelessWidget {
  final JukeboxNotifier jukebox;
  final VisionTokens t;

  const JukeboxNowPlaying({super.key, required this.jukebox, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        _buildBody(context),
        if (jukebox.showKaraokeInPanel && jukebox.currentSong != null) ...[
          const SizedBox(height: VisionMetrics.space16),
          buildVisualizerPreview(context, jukebox, t, height: 160),
        ],
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final song = jukebox.currentSong;
    return Row(
      children: [
        Expanded(child: SectionTitle(context.l.jukeboxNowPlaying, t: t)),
        if (song != null)
          IconButton(
            icon: Icon(
              jukebox.showKaraokeInPanel
                  ? Icons.visibility
                  : Icons.visibility_off,
              size: 16,
              color: jukebox.showKaraokeInPanel ? t.accent : t.textDisabled,
            ),
            onPressed: jukebox.toggleKaraokeInPanel,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(VisionMetrics.space4),
            tooltip: context.l.jukeboxToggleVisualizer,
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final song = jukebox.currentSong;
    if (song == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(VisionMetrics.space24),
          child: Text(
            context.l.jukeboxNoSongPlaying,
            style: TextStyle(
              color: t.textMinimal,
              fontSize: t.fontSize(9),
              letterSpacing: 2,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSongTitle(song, t),
        if (song.artist != null) buildSongArtist(song, t),
        buildSongBadges(context, song, t),
        const SizedBox(height: VisionMetrics.space16),
        buildTransportControls(context, jukebox, t),
      ],
    );
  }

  // ─────────────────────────────────────────
  // Shared static builders used by both desktop and mobile
  // ─────────────────────────────────────────

  /// Song title display.
  static Widget buildSongTitle(JukeboxSong song, VisionTokens t) {
    return Text(
      song.title.toUpperCase(),
      style: TextStyle(
        color: t.textPrimary,
        fontSize: t.fontSize(14),
        letterSpacing: 2,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  /// Song artist display.
  static Widget buildSongArtist(JukeboxSong song, VisionTokens t) {
    return Padding(
      padding: const EdgeInsets.only(top: VisionMetrics.space4),
      child: Text(
        song.artist!.toUpperCase(),
        style: TextStyle(
          color: t.textTertiary,
          fontSize: t.fontSize(10),
          letterSpacing: 1,
        ),
      ),
    );
  }

  /// Category & karaoke badges.
  static Widget buildSongBadges(
    BuildContext context,
    JukeboxSong song,
    VisionTokens t,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: VisionMetrics.space4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VisionMetrics.space8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: t.borderSubtle,
              borderRadius: BorderRadius.circular(VisionMetrics.radius2),
            ),
            child: Text(
              song.categoryLabel,
              style: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(7),
                letterSpacing: 1,
              ),
            ),
          ),
          if (song.isKaraoke) ...[
            const SizedBox(width: VisionMetrics.space8),
            AppPill(
              text: context.l.jukeboxKaraokeLabel,
              tone: AppTone.info,
              dense: true,
            ),
          ],
        ],
      ),
    );
  }

  /// Seek bar + play/pause/skip + volume slider.
  static Widget buildTransportControls(
    BuildContext context,
    JukeboxNotifier jukebox,
    VisionTokens t,
  ) {
    return Column(
      children: [
        // Seek bar
        Row(
          children: [
            Text(
              formatDuration(jukebox.position),
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(7)),
            ),
            Expanded(
              child: VisionSlider.accent(
                value: jukebox.duration.inMilliseconds > 0
                    ? (jukebox.position.inMilliseconds /
                              jukebox.duration.inMilliseconds)
                          .clamp(0.0, 1.0)
                    : 0.0,
                onChanged: (v) {
                  final target = Duration(
                    milliseconds: (v * jukebox.duration.inMilliseconds).round(),
                  );
                  jukebox.seek(target);
                },
                t: t,
              ),
            ),
            Text(
              formatDuration(jukebox.duration),
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(7)),
            ),
          ],
        ),
        // Transport buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.skip_previous, color: t.textSecondary, size: 28),
              tooltip: context.l.jukeboxPrevious,
              onPressed: jukebox.previous,
            ),
            const SizedBox(width: VisionMetrics.space16),
            IconButton(
              icon: Icon(
                jukebox.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: t.accent,
                size: 44,
              ),
              tooltip: jukebox.isPlaying
                  ? context.l.jukeboxPause
                  : context.l.jukeboxPlay,
              onPressed: jukebox.isPlaying ? jukebox.pause : jukebox.resume,
            ),
            const SizedBox(width: VisionMetrics.space16),
            IconButton(
              icon: Icon(Icons.skip_next, color: t.textSecondary, size: 28),
              tooltip: context.l.jukeboxNext,
              onPressed: jukebox.next,
            ),
          ],
        ),
        const SizedBox(height: VisionMetrics.space8),
        // Volume
        Row(
          children: [
            IconButton(
              icon: Icon(
                jukebox.isMuted ? Icons.volume_off : Icons.volume_up,
                size: 16,
                color: t.textDisabled,
              ),
              tooltip: jukebox.isMuted
                  ? context.l.jukeboxUnmute
                  : context.l.jukeboxMute,
              onPressed: jukebox.toggleMute,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(VisionMetrics.space4),
            ),
            Expanded(
              child: VisionSlider(
                value: jukebox.isMuted ? 0.0 : jukebox.volume,
                onChanged: (v) => jukebox.setVolume(v),
                activeColor: t.textPrimary.withValues(
                  alpha: VisionMetrics.opacityDisabled,
                ),
                inactiveColor: t.borderSubtle,
                thumbColor: t.textPrimary,
                thumbRadius: 4,
                overlayRadius: 8,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Visualizer preview box with fullscreen button.
  static Widget buildVisualizerPreview(
    BuildContext context,
    JukeboxNotifier jukebox,
    VisionTokens t, {
    double height = 160,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const KaraokeVisualizer(),
            if (jukebox.currentSong!.isKaraoke)
              const KaraokeOverlay(preview: true),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(
                  Icons.fullscreen,
                  size: 20,
                  color: Colors.white.withValues(
                    alpha: VisionMetrics.opacityScrim,
                  ),
                ),
                tooltip: context.l.jukeboxFullscreen,
                onPressed: () => openFullscreenVisualizer(context),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(VisionMetrics.space4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format a [Duration] as MM:SS.
  static String formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Open the fullscreen karaoke visualizer dialog.
  static void openFullscreenVisualizer(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: const FullscreenVisualizer(),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Mobile Now Playing bar (compact + expandable)
// ─────────────────────────────────────────

/// Mobile "Now Playing" bar: compact transport strip that expands into a full
/// scrollable panel. The expanded body is supplied by the parent so that the
/// composition shell controls section ordering.
class JukeboxMobileNowPlaying extends StatelessWidget {
  final JukeboxNotifier jukebox;
  final VisionTokens t;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Full widget tree to show when the panel is expanded. Built by the
  /// composition shell using the other extracted sub-widgets.
  final Widget expandedBody;

  /// Optional callback to enter game mode from the compact bar.
  final VoidCallback? onGamePressed;

  const JukeboxMobileNowPlaying({
    super.key,
    required this.jukebox,
    required this.t,
    required this.expanded,
    required this.onExpandedChanged,
    required this.expandedBody,
    this.onGamePressed,
  });

  @override
  Widget build(BuildContext context) {
    if (jukebox.currentSong == null) return const SizedBox.shrink();

    final song = jukebox.currentSong!;
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: expanded ? screenHeight * 0.5 : double.infinity,
        ),
        child: Container(
          color: t.surfaceMid,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDragHandle(),
              if (!expanded) ...[
                _buildCompactBar(context, song),
                const SizedBox(height: VisionMetrics.space4),
              ],
              if (expanded) Flexible(child: expandedBody),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.primaryDelta != null) {
          if (d.primaryDelta! < -5) onExpandedChanged(true);
          if (d.primaryDelta! > 5) onExpandedChanged(false);
        }
      },
      onTap: () => onExpandedChanged(!expanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space12),
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: t.textMinimal,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.expand_less,
                  size: 12,
                  color: t.textDisabled,
                ),
                const SizedBox(width: 2),
                Text(
                  expanded ? 'LESS' : 'MORE',
                  style: TextStyle(
                    color: t.textDisabled,
                    fontSize: t.fontSize(8),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactBar(BuildContext context, JukeboxSong song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              song.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: t.fontSize(9),
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.skip_previous, size: 20, color: t.textSecondary),
            tooltip: context.l.jukeboxPrevious,
            onPressed: jukebox.previous,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(VisionMetrics.space4),
          ),
          IconButton(
            icon: Icon(
              jukebox.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 24,
              color: t.accent,
            ),
            tooltip: jukebox.isPlaying
                ? context.l.jukeboxPause
                : context.l.jukeboxPlay,
            onPressed: jukebox.isPlaying ? jukebox.pause : jukebox.resume,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(VisionMetrics.space4),
          ),
          IconButton(
            icon: Icon(Icons.skip_next, size: 20, color: t.textSecondary),
            tooltip: context.l.jukeboxNext,
            onPressed: jukebox.next,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(VisionMetrics.space4),
          ),
          if (onGamePressed != null && jukebox.currentSong != null)
            IconButton(
              icon: Icon(Icons.sports_esports, size: 20, color: t.accent),
              tooltip: context.l.jukeboxGameModeTooltip,
              onPressed: onGamePressed,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(VisionMetrics.space4),
            ),
          if (jukebox.isPlaying)
            IconButton(
              icon: Icon(Icons.fullscreen, size: 20, color: t.accent),
              tooltip: context.l.jukeboxFullscreen,
              onPressed: () =>
                  JukeboxNowPlaying.openFullscreenVisualizer(context),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(VisionMetrics.space4),
            ),
          Icon(Icons.expand_less, size: 16, color: t.textMinimal),
        ],
      ),
    );
  }
}
