import 'package:flutter/material.dart';

import '../../../core/services/client_diagnostics.dart';

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

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  late final TabController _tabController;

  double _extent = 0;
  double _minimumExtent = 0;
  double _middleExtent = 0;
  bool _initialized = false;
  double _lastLoggedExtent = -1;
  double _lastLoggedAvailableHeight = -1;
  double _lastLoggedViewInset = -1;

  bool get isExpanded => _extent > _minimumExtent + 0.025;

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
    super.dispose();
  }

  Future<void> collapse() {
    final media = mounted ? MediaQuery.maybeOf(context) : null;
    ClientDiagnostics.instance.record('generation_sheet_collapse_requested', {
      'extent': _extent,
      'view_insets_bottom': media?.viewInsets.bottom,
      'primary_focus_present': FocusManager.instance.primaryFocus != null,
    });
    FocusManager.instance.primaryFocus?.unfocus();
    return _animateTo(_minimumExtent);
  }

  Future<void> expand() => _animateTo(1);

  Future<void> openTab(GenerationMobileTab tab, {bool full = false}) async {
    ClientDiagnostics.instance.record('generation_sheet_tab_open_requested', {
      'tab_index': tab.index,
      'full': full,
      'extent': _extent,
    });
    _tabController.animateTo(tab.index);
    await _animateTo(full ? 1 : _middleExtent);
  }

  Future<void> _animateTo(double extent) async {
    if (!_sheetController.isAttached || extent <= 0) return;
    ClientDiagnostics.instance.record('generation_sheet_animation_started', {
      'from_extent': _extent,
      'to_extent': extent,
    });
    await _sheetController.animateTo(
      extent.clamp(_minimumExtent, 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    ClientDiagnostics.instance.record('generation_sheet_animation_finished', {
      'extent': _sheetController.size,
    });
  }

  void _updateExtent(DraggableScrollableNotification notification) {
    if ((notification.extent - _extent).abs() < 0.002) return;
    setState(() => _extent = notification.extent);
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
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom;

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
        final peekPixels = GenerationMobileSheet.peekContentHeight + safeBottom;
        final minimumExtent = (peekPixels / availableHeight).clamp(0.08, 0.45);
        final middlePixels = (availableHeight * 0.72).clamp(
          peekPixels + 120,
          availableHeight - 72,
        );
        final middleExtent = (middlePixels / availableHeight).clamp(
          minimumExtent + 0.08,
          0.9,
        );
        _minimumExtent = minimumExtent;
        _middleExtent = middleExtent;

        if (!_initialized) {
          _initialized = true;
          _extent = minimumExtent;
        } else if (_extent < minimumExtent) {
          _extent = minimumExtent;
        }

        final expanded = isExpanded;
        final expansionProgress =
            ((_extent - minimumExtent) / (middleExtent - minimumExtent)).clamp(
              0.0,
              1.0,
            );

        return Stack(
          children: [
            if (expanded)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: collapse,
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: 0.42 * expansionProgress,
                    ),
                  ),
                ),
              ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                _updateExtent(notification);
                return false;
              },
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: minimumExtent,
                minChildSize: minimumExtent,
                maxChildSize: 1,
                snap: true,
                snapSizes: [middleExtent],
                snapAnimationDuration: const Duration(milliseconds: 220),
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) {
                  return Material(
                    key: GenerationMobileSheet.panelKey,
                    color: t.colorScheme.surface,
                    elevation: 18,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      side: BorderSide(
                        color: t.dividerColor.withValues(alpha: 0.75),
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, sheetConstraints) {
                        return ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          children: [
                            SizedBox(
                              height: sheetConstraints.maxHeight,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height:
                                        GenerationMobileSheet.peekContentHeight,
                                    child: _buildHeader(context, expanded),
                                  ),
                                  if (expanded)
                                    Expanded(
                                      child: TabBarView(
                                        controller: _tabController,
                                        children: [
                                          RepaintBoundary(
                                            child: KeyedSubtree(
                                              key: GenerationMobileSheet
                                                  .promptPageKey,
                                              child: widget.prompt,
                                            ),
                                          ),
                                          RepaintBoundary(
                                            child: KeyedSubtree(
                                              key: GenerationMobileSheet
                                                  .inputsPageKey,
                                              child: widget.inputs,
                                            ),
                                          ),
                                          RepaintBoundary(
                                            child: KeyedSubtree(
                                              key: GenerationMobileSheet
                                                  .parametersPageKey,
                                              child: widget.parameters,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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

  Widget _buildHeader(BuildContext context, bool expanded) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 7),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: 0.28),
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${widget.inputCount}',
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.image_outlined,
                                    size: 13,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${widget.inputCount}',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
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
