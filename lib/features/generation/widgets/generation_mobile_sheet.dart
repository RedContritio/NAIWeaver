import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/client_diagnostics.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';

enum GenerationMobileTab { prompt, inputs, parameters }

/// One scroll owner for the complete mobile prompt form. The main prompt must
/// be able to leave the viewport so the keyboard does not permanently consume
/// most of the usable sheet height.
class GenerationMobilePromptPage extends StatelessWidget {
  const GenerationMobilePromptPage({
    super.key,
    required this.prompt,
    required this.settings,
  });

  final Widget prompt;
  final Widget settings;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: GenerationMobileSheet.promptScrollKey,
      physics: const ClampingScrollPhysics(),
      child: Column(children: [prompt, settings]),
    );
  }
}

/// Mobile-only shell for the generation controls.
///
/// The result stage and this sheet are the only two layout owners on the
/// mobile generation page. The sheet keeps its collapsed summary, tabs,
/// scrim, drag state, scrolling and safe-area padding inside one boundary so
/// no floating controls or permanent spacer blocks are needed around it.
class GenerationMobileSheet extends StatefulWidget {
  const GenerationMobileSheet({
    super.key,
    required this.compactPrompt,
    required this.compactActions,
    required this.prompt,
    required this.inputs,
    required this.parameters,
    required this.promptLabel,
    required this.inputsLabel,
    required this.parametersLabel,
    this.inputCount = 0,
  });

  static const double peekContentHeight = 56;

  /// Height of the collapsed sheet: the summary bar plus the bottom safe area
  /// seen from [context]. The sheet sizes itself with this. A layout that
  /// keeps its content clear of the sheet should resolve it in the context
  /// the sheet is built in, as `GenerationPageLayout.overlayReservedHeightOf`
  /// does, because a [Scaffold] body drops the safe area while the keyboard
  /// is up.
  static double collapsedHeightOf(BuildContext context) {
    return peekContentHeight + MediaQuery.viewPaddingOf(context).bottom;
  }

  static const compactKey = ValueKey<String>('generation-mobile-sheet-compact');
  static const panelKey = ValueKey<String>('generation-mobile-sheet-panel');
  static const tabsKey = ValueKey<String>('generation-mobile-sheet-tabs');
  static const promptPageKey = ValueKey<String>(
    'generation-mobile-sheet-prompt-page',
  );
  static const inputsPageKey = ValueKey<String>(
    'generation-mobile-sheet-inputs-page',
  );
  static const parametersPageKey = ValueKey<String>(
    'generation-mobile-sheet-parameters-page',
  );
  static const promptScrollKey = ValueKey<String>(
    'generation-mobile-sheet-prompt-scroll',
  );

  final Widget compactPrompt;
  final Widget compactActions;
  final Widget prompt;
  final Widget inputs;
  final Widget parameters;
  final String promptLabel;
  final String inputsLabel;
  final String parametersLabel;
  final int inputCount;

  @override
  State<GenerationMobileSheet> createState() => GenerationMobileSheetState();
}

class GenerationMobileSheetState extends State<GenerationMobileSheet>
    with SingleTickerProviderStateMixin {
  static const _tabSwitchDuration = Duration(milliseconds: 160);
  static const _sheetAnimationDuration = Duration(milliseconds: 260);
  static const _snapAnimationDuration = Duration(milliseconds: 220);

  /// How far past its collapsed size the sheet has to be before it counts as
  /// open: the scrim appears and the header turns into the tab bar.
  static const double _expandedThreshold = 0.025;
  static const double _scrimOpacity = 0.42;

  // The middle stop sits at [_middleFraction] of the height, but must show at
  // least [_middleMinBodyHeight] of tab content, leave at least
  // [_middleMinResultsHeight] of the results visible, and stay clear of both
  // ends. When the viewport is too short for all of that, there is no middle
  // stop and opening a tab goes straight to full height.
  static const double _middleFraction = 0.72;
  static const double _middleMaxExtent = 0.9;
  static const double _middleMinBodyHeight = 120;
  static const double _middleMinResultsHeight = 72;
  static const double _minimumSnapGap = 0.08;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  late final TabController _tabController;

  /// The sheet size as last reported by the sheet. Only the widgets that
  /// depend on it listen: rebuilding the [DraggableScrollableSheet] itself
  /// replaces its extent, which is not something to do on every drag frame.
  final ValueNotifier<double> _extent = ValueNotifier<double>(0);
  final ValueNotifier<bool> _expanded = ValueNotifier<bool>(false);

  /// Wraps the tab pages so the sheet can tell whether focus is inside them.
  final FocusNode _pagesFocusNode = FocusNode(
    debugLabel: 'GenerationMobileSheet pages',
    canRequestFocus: false,
    skipTraversal: true,
  );

  double _minimumExtent = 1;
  double _middleExtent = 1;

  /// Passed to [DraggableScrollableSheet.snapSizes]. The sheet compares it by
  /// identity whenever it is rebuilt and, when it differs, snaps after the
  /// frame, cancelling any drag in progress. It is therefore only replaced
  /// when the middle stop actually moves.
  List<double> _snapSizes = const <double>[];

  double _lastLoggedExtent = -1;
  double _lastLoggedAvailableHeight = -1;
  double _lastLoggedViewInset = -1;

  bool get isExpanded => _expanded.value;

  double get _currentExtent =>
      _sheetController.isAttached ? _sheetController.size : _minimumExtent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      animationDuration: _tabSwitchDuration,
    );
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _tabController.dispose();
    _extent.dispose();
    _expanded.dispose();
    _pagesFocusNode.dispose();
    super.dispose();
  }

  Future<void> collapse() {
    if (!mounted) return Future<void>.value();
    ClientDiagnostics.instance.record('generation_sheet_collapse_requested', {
      'extent': _currentExtent,
      'view_insets_bottom': MediaQuery.maybeOf(context)?.viewInsets.bottom,
      'primary_focus_present': FocusManager.instance.primaryFocus != null,
    });
    FocusManager.instance.primaryFocus?.unfocus();
    return _animateTo(_minimumExtent);
  }

  Future<void> expand() => _animateTo(1);

  Future<void> openTab(GenerationMobileTab tab, {bool full = false}) async {
    if (!mounted) return;
    ClientDiagnostics.instance.record('generation_sheet_tab_open_requested', {
      'tab_index': tab.index,
      'full': full,
      'extent': _currentExtent,
    });
    _tabController.animateTo(tab.index);
    // Focusing the prompt lands here too, so never pull back a sheet that is
    // already open further than asked. Animating to its own size still stops
    // a collapse that is running.
    await _animateTo(math.max(full ? 1 : _middleExtent, _currentExtent));
  }

  Future<void> _animateTo(double extent) async {
    if (!mounted || !_sheetController.isAttached) return;
    ClientDiagnostics.instance.record('generation_sheet_animation_started', {
      'from_extent': _sheetController.size,
      'to_extent': extent,
    });
    await _sheetController.animateTo(
      extent.clamp(_minimumExtent, 1.0),
      duration: _sheetAnimationDuration,
      curve: Curves.easeOutCubic,
    );
    // The sheet may have left the tree meanwhile, for example when the window
    // widens past the mobile layout or cascade playback takes over.
    if (!mounted || !_sheetController.isAttached) return;
    ClientDiagnostics.instance.record('generation_sheet_animation_finished', {
      'extent': _sheetController.size,
    });
  }

  void _setExtent(double extent) {
    _extent.value = extent;
    final expanded = extent > _minimumExtent + _expandedThreshold;
    if (expanded == _expanded.value) return;
    _expanded.value = expanded;
    // The pages stay mounted behind the summary bar, so a field in them keeps
    // its focus when the sheet is dragged closed. Do not leave the keyboard
    // up for a field that can no longer be seen.
    if (!expanded && _pagesFocusNode.hasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  bool _handleSheetNotification(DraggableScrollableNotification notification) {
    _setExtent(notification.extent);
    if ((notification.extent - _lastLoggedExtent).abs() >= 0.1 ||
        notification.extent == notification.minExtent ||
        notification.extent == notification.maxExtent) {
      _lastLoggedExtent = notification.extent;
      ClientDiagnostics.instance.record('generation_sheet_extent_changed', {
        'extent': notification.extent,
        'minimum_extent': notification.minExtent,
        'maximum_extent': notification.maxExtent,
      });
    }
    return false;
  }

  /// Resolves the collapsed and middle stops for [availableHeight]. Never
  /// throws: a viewport shorter than [collapsedHeight] (a landscape phone
  /// with the keyboard up, a split screen) pins the sheet to full height.
  static ({double minimum, double middle}) _extentsFor(
    double availableHeight,
    double collapsedHeight,
  ) {
    if (availableHeight <= collapsedHeight) {
      return (minimum: 1.0, middle: 1.0);
    }
    final minimum = collapsedHeight / availableHeight;
    final lowest = math.max(
      (collapsedHeight + _middleMinBodyHeight) / availableHeight,
      minimum + _minimumSnapGap,
    );
    final highest = math.min(
      (availableHeight - _middleMinResultsHeight) / availableHeight,
      _middleMaxExtent,
    );
    final middle = lowest <= highest
        ? _middleFraction.clamp(lowest, highest)
        : 1.0;
    return (minimum: minimum, middle: middle);
  }

  void _applyExtents(double minimum, double middle) {
    if (minimum == _minimumExtent && middle == _middleExtent) return;
    // Judged by the old stops, before they change.
    final wasCollapsed = !_expanded.value;
    if (middle != _middleExtent) {
      _snapSizes = middle < 1 ? <double>[middle] : const <double>[];
    }
    _minimumExtent = minimum;
    _middleExtent = middle;
    // Once moved, the sheet keeps its old fraction of the new height (only
    // clamped into the new range) and does not notify. After it has been
    // laid out with the new range, put a collapsed sheet back on its
    // collapsed size, which is exactly what the page reserves for it, and
    // bring the listeners up to date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetController.isAttached) return;
      if (wasCollapsed && _sheetController.size != _minimumExtent) {
        _sheetController.jumpTo(_minimumExtent);
      }
      _setExtent(_sheetController.size);
    });
  }

  double _expansionProgress(double extent) {
    final span = _middleExtent - _minimumExtent;
    if (span <= 0) return 1;
    return ((extent - _minimumExtent) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom;
    final collapsedHeight = GenerationMobileSheet.collapsedHeightOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        if ((availableHeight - _lastLoggedAvailableHeight).abs() >= 1 ||
            (media.viewInsets.bottom - _lastLoggedViewInset).abs() >= 1) {
          _lastLoggedAvailableHeight = availableHeight;
          _lastLoggedViewInset = media.viewInsets.bottom;
          ClientDiagnostics.instance
              .record('generation_sheet_viewport_changed', {
                'available_height': availableHeight,
                'view_insets_bottom': media.viewInsets.bottom,
                'view_padding_bottom': safeBottom,
              });
        }
        final extents = _extentsFor(availableHeight, collapsedHeight);
        _applyExtents(extents.minimum, extents.middle);

        return Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _expanded,
                builder: (context, expanded, _) {
                  if (!expanded) return const SizedBox.shrink();
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: collapse,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _extent,
                      builder: (context, extent, _) => ColoredBox(
                        color: Colors.black.withValues(
                          alpha: _scrimOpacity * _expansionProgress(extent),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: _handleSheetNotification,
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _minimumExtent,
                minChildSize: _minimumExtent,
                maxChildSize: 1,
                snap: true,
                snapSizes: _snapSizes,
                snapAnimationDuration: _snapAnimationDuration,
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) {
                  // Built once per sheet build: the layout builder below runs
                  // on every drag frame and reuses these instances untouched.
                  final header = ValueListenableBuilder<bool>(
                    valueListenable: _expanded,
                    builder: (context, expanded, _) =>
                        _buildHeader(t, expanded),
                  );
                  final pages = _buildPages(context);
                  return Material(
                    key: GenerationMobileSheet.panelKey,
                    color: t.surfaceHigh,
                    elevation: 18,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      side: BorderSide(color: t.borderStrong),
                    ),
                    child: LayoutBuilder(
                      builder: (context, sheetConstraints) {
                        return ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          children: [
                            SizedBox(
                              // Never shorter than the summary bar: a viewport
                              // below that height scrolls the sheet content
                              // instead of overflowing it.
                              height: math.max(
                                sheetConstraints.maxHeight,
                                collapsedHeight,
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height:
                                        GenerationMobileSheet.peekContentHeight,
                                    child: header,
                                  ),
                                  Expanded(child: pages),
                                  SizedBox(height: safeBottom),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// The tab pages stay mounted while the sheet is collapsed. They are
  /// squeezed to zero height under the summary bar, which keeps them out of
  /// sight, hit testing and the semantics tree, while their state, scroll
  /// positions and native text areas (with their undo history) survive the
  /// collapse that follows every generation.
  Widget _buildPages(BuildContext context) {
    Widget page(Key key, Widget child) {
      return _KeepAlivePage(
        child: RepaintBoundary(
          child: KeyedSubtree(key: key, child: child),
        ),
      );
    }

    return Focus(
      focusNode: _pagesFocusNode,
      // The sheet already keeps its content above the bottom safe area (see
      // the spacer below the pages), so the pages must not pad for it again.
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        // Every page owns its scroll position. The route's primary controller
        // would otherwise end up attached to all three kept-alive pages.
        child: PrimaryScrollController.none(
          child: TabBarView(
            controller: _tabController,
            children: [
              page(GenerationMobileSheet.promptPageKey, widget.prompt),
              page(GenerationMobileSheet.inputsPageKey, widget.inputs),
              page(GenerationMobileSheet.parametersPageKey, widget.parameters),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(VisionTokens t, bool expanded) {
    return Column(
      children: [
        const SizedBox(height: 7),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: t.textDisabled,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: expanded
                ? TabBar(
                    key: GenerationMobileSheet.tabsKey,
                    controller: _tabController,
                    onTap: (_) {
                      if (!isExpanded) _animateTo(_middleExtent);
                    },
                    dividerHeight: 0,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: [
                      Tab(text: widget.promptLabel),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.inputsLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.inputCount > 0) ...[
                              const SizedBox(width: 5),
                              _InputCountBadge(count: widget.inputCount),
                            ],
                          ],
                        ),
                      ),
                      Tab(text: widget.parametersLabel),
                    ],
                  )
                : InkWell(
                    key: GenerationMobileSheet.compactKey,
                    onTap: () => openTab(GenerationMobileTab.prompt),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 8, 5),
                      child: Row(
                        children: [
                          Expanded(child: widget.compactPrompt),
                          if (widget.inputCount > 0) ...[
                            const SizedBox(width: 6),
                            _InputCountBadge(
                              count: widget.inputCount,
                              icon: Icons.image_outlined,
                            ),
                          ],
                          const SizedBox(width: 8),
                          widget.compactActions,
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Keeps a tab page alive while another tab is shown, so switching tabs does
/// not rebuild it from scratch either.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Active reference-input counter, shared by the compact bar (with an icon,
/// since the bar has no label) and the inputs tab label.
class _InputCountBadge extends StatelessWidget {
  const _InputCountBadge({required this.count, this.icon});

  final int count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: t.accent),
            const SizedBox(width: 3),
          ],
          Text(
            '$count',
            style: TextStyle(
              color: t.accent,
              fontSize: t.fontSize(10),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
