import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/jukebox_notifier.dart';
import '../midi_sequencer.dart';
import '../../theme/theme_extensions.dart';

/// Translucent overlay for displaying karaoke lyrics.
/// Shows current lyric line with syllable highlighting.
class KaraokeOverlay extends StatelessWidget {
  final bool singleLine;
  final bool preview;

  const KaraokeOverlay({super.key, this.singleLine = false, this.preview = false});

  @override
  Widget build(BuildContext context) {
    final jukebox = context.watch<JukeboxNotifier>();

    if (jukebox.currentSong == null || !jukebox.currentSong!.isKaraoke) {
      return const SizedBox.shrink();
    }

    final lyrics = jukebox.lyrics;
    if (lyrics.isEmpty) return const SizedBox.shrink();

    // Find current lyric line based on position
    final position = jukebox.position;
    LyricLine? currentLine;
    LyricLine? nextLine;
    Duration nextLineTs = jukebox.duration;

    for (int i = 0; i < lyrics.length; i++) {
      final line = lyrics[i];
      final nextTs = i + 1 < lyrics.length ? lyrics[i + 1].timestamp : jukebox.duration;

      if (position >= line.timestamp && position < nextTs) {
        currentLine = line;
        nextLineTs = nextTs;
        if (i + 1 < lyrics.length) nextLine = lyrics[i + 1];
        break;
      }
    }

    if (currentLine == null) return const SizedBox.shrink();

    final t = context.t;
    final highlightColor = jukebox.karaokeHighlightColor ?? t.accent;
    final upcomingColor = jukebox.karaokeUpcomingColor ?? t.textPrimary;
    final nextLineColor = jukebox.karaokeNextLineColor ?? t.textMinimal;
    final fontFamily = jukebox.karaokeFontFamily;
    final fontScale = jukebox.karaokeFontScale;

    if (singleLine) {
      return _KaraokeLine(
        line: currentLine,
        lineEndTimestamp: nextLineTs,
        isCurrent: true,
        highlightColor: highlightColor,
        upcomingColor: upcomingColor,
        nextLineColor: nextLineColor,
        fontFamily: fontFamily,
        fontSize: t.fontSize(9) * fontScale,
        compact: true,
      );
    }

    // Compute line progress for the countdown bar
    final lineStart = currentLine.timestamp;
    final lineEnd = nextLineTs;
    final totalUs = (lineEnd - lineStart).inMicroseconds;
    final lineProgress = totalUs > 0
        ? ((position - lineStart).inMicroseconds / totalUs).clamp(0.0, 1.0)
        : 0.0;

    // Next-line brightness fade: brighten in last 30%
    final effectiveNextLineColor = lineProgress > 0.7
        ? Color.lerp(nextLineColor, upcomingColor, ((lineProgress - 0.7) / 0.3).clamp(0.0, 1.0))!
        : nextLineColor;

    final bottomSafe = preview ? 0.0 : MediaQuery.of(context).padding.bottom;

    return Container(
      padding: preview
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : EdgeInsets.fromLTRB(32, 16, 32, 16 + bottomSafe),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _KaraokeLine(
            line: currentLine,
            lineEndTimestamp: nextLineTs,
            isCurrent: true,
            highlightColor: highlightColor,
            upcomingColor: upcomingColor,
            nextLineColor: nextLineColor,
            fontFamily: fontFamily,
            fontSize: t.fontSize(preview ? 13 : 22) * fontScale,
            maxLines: preview ? 4 : 2,
          ),
          if (nextLine != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: preview ? 2 : 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1.5),
                child: LinearProgressIndicator(
                  value: lineProgress,
                  backgroundColor: nextLineColor.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(highlightColor.withValues(alpha: 0.7)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _KaraokeLine(
              line: nextLine,
              lineEndTimestamp: jukebox.duration,
              isCurrent: false,
              highlightColor: highlightColor,
              upcomingColor: upcomingColor,
              nextLineColor: effectiveNextLineColor,
              fontFamily: fontFamily,
              fontSize: t.fontSize(preview ? 10 : 14) * fontScale,
            ),
          ],
        ],
      ),
    );
  }
}

class _KaraokeLine extends StatefulWidget {
  final LyricLine line;
  final Duration lineEndTimestamp;
  final bool isCurrent;
  final Color highlightColor;
  final Color upcomingColor;
  final Color nextLineColor;
  final String? fontFamily;
  final double fontSize;
  final bool compact;
  final int? maxLines;

  const _KaraokeLine({
    required this.line,
    required this.lineEndTimestamp,
    required this.isCurrent,
    required this.highlightColor,
    required this.upcomingColor,
    required this.nextLineColor,
    this.fontFamily,
    required this.fontSize,
    this.compact = false,
    this.maxLines,
  });

  @override
  State<_KaraokeLine> createState() => _KaraokeLineState();
}

class _KaraokeLineState extends State<_KaraokeLine> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTicker();
  }

  @override
  void didUpdateWidget(_KaraokeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTicker();
  }

  void _updateTicker() {
    final shouldTick = widget.isCurrent && context.read<JukeboxNotifier>().isPlaying;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.isCurrent
        ? context.read<JukeboxNotifier>().realtimePosition
        : Duration.zero;

    final color = widget.isCurrent ? widget.upcomingColor : widget.nextLineColor;
    final shadows = widget.isCurrent && !widget.compact
        ? const [
            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
            Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 0)),
          ]
        : null;

    final effectiveMaxLines = widget.maxLines ?? (widget.compact ? 1 : 2);

    if (widget.line.syllables.isEmpty) {
      return Text(
        widget.line.text,
        textAlign: TextAlign.center,
        maxLines: effectiveMaxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: widget.fontFamily,
          letterSpacing: 1,
          shadows: shadows,
        ),
      );
    }

    final spans = <TextSpan>[];
    for (int i = 0; i < widget.line.syllables.length; i++) {
      final syllable = widget.line.syllables[i];
      final nextTs = i + 1 < widget.line.syllables.length
          ? widget.line.syllables[i + 1].timestamp
          : widget.lineEndTimestamp;

      final isPast = position >= nextTs;
      final isActive = !isPast && position >= syllable.timestamp;

      Color syllableColor;
      List<Shadow>? syllableShadows = shadows;

      if (!widget.isCurrent) {
        syllableColor = widget.nextLineColor;
      } else if (isPast) {
        syllableColor = widget.highlightColor;
      } else if (isActive) {
        final totalUs = (nextTs - syllable.timestamp).inMicroseconds;
        final progress = totalUs > 0
            ? ((position - syllable.timestamp).inMicroseconds / totalUs).clamp(0.0, 1.0)
            : 1.0;
        syllableColor = Color.lerp(widget.upcomingColor, widget.highlightColor, progress)!;
        syllableShadows = [
          ...?shadows,
          Shadow(color: widget.highlightColor.withValues(alpha: 0.6 * progress), blurRadius: 8 * progress),
        ];
      } else {
        syllableColor = widget.upcomingColor;
      }

      spans.add(TextSpan(
        text: syllable.text,
        style: TextStyle(
          color: syllableColor,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: widget.fontFamily,
          letterSpacing: 1,
          shadows: syllableShadows,
        ),
      ));
    }

    return RichText(
      textAlign: TextAlign.center,
      maxLines: effectiveMaxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}
