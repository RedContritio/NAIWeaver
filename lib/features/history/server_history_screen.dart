import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/gateway/backend_error_messages.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/services/backend_auth_api.dart';
import '../../core/services/backend_history_api.dart';
import '../../core/services/client_diagnostics.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vision_metrics.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/web_download.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/card_action_layout.dart';
import '../../core/widgets/ui/app_panel.dart';
import '../../core/widgets/ui/app_pill.dart';
import '../../core/widgets/ui/app_states.dart';
import '../../core/widgets/ui/overlay_action_button.dart';
import '../../l10n/app_localizations.dart';
import '../auth/backend_auth_notifier.dart';
import '../generation/providers/generation_notifier.dart';
import '../generation/services/metadata_import_service.dart';
import '../generation/widgets/generation_results_workspace.dart';
import '../generation/widgets/result_set_viewer.dart';

class ServerHistoryScreen extends StatefulWidget {
  const ServerHistoryScreen({super.key, this.api});

  final BackendHistoryApi? api;

  @override
  State<ServerHistoryScreen> createState() => _ServerHistoryScreenState();
}

class _ServerHistoryScreenState extends State<ServerHistoryScreen> {
  static const int _pageSize = 20;

  late final BackendHistoryApi _api;
  final ScrollController _scrollController = ScrollController();
  List<ServerHistoryItem> _items = const [];
  List<_HistoryEntry> _entries = const [];
  List<AuthUser> _users = const [];
  bool _usersLoaded = false;
  int? _selectedUserId;
  bool _filterInitialized = false;
  int _loadGeneration = 0;
  int _pageIndex = 0;
  int _totalItems = 0;
  bool _loading = true;
  Object? _error;
  int _errorPageIndex = 0;
  Timer? _thumbnailPreloadTimer;
  int _gridColumns = 2;
  double _gridMainExtent = 260;
  int _lastPreloadStart = -1;
  int _lastPreloadEnd = -1;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? BackendHistoryApi();
    _scrollController.addListener(_scheduleThumbnailPreload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _thumbnailPreloadTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Loads [pageIndex] (default: the current page). The page index only
  /// advances once the page has arrived, and a failure keeps what is shown.
  Future<void> _load({int? pageIndex}) async {
    final auth = context.read<BackendAuthNotifier>();
    final isAdmin = auth.user?.isAdmin == true;
    if (!_filterInitialized) {
      _selectedUserId = auth.user?.id;
      _filterInitialized = true;
    }
    final requestedPageIndex = math.max(0, pageIndex ?? _pageIndex);
    final loadGeneration = ++_loadGeneration;
    setState(() {
      if (isAdmin && _users.isEmpty) _users = [auth.user!];
      _loading = true;
      _error = null;
    });
    if (isAdmin && !_usersLoaded) unawaited(_loadUsers(auth.user!));
    try {
      final page = await _fetchPage(
        requestedPageIndex,
        userId: _selectedUserId,
        allUsers: isAdmin && _selectedUserId == null,
      );
      if (!mounted || loadGeneration != _loadGeneration) return;
      final pageChanged = page.pageIndex != _pageIndex;
      setState(() {
        _items = page.items;
        _entries = _HistoryEntry.fromItems(page.items);
        _totalItems = page.total;
        _pageIndex = page.pageIndex;
        _loading = false;
      });
      _lastPreloadStart = -1;
      _lastPreloadEnd = -1;
      if (pageChanged && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preloadVisibleThumbnails(force: true);
      });
    } catch (e) {
      if (!mounted || loadGeneration != _loadGeneration) return;
      setState(() {
        _error = e;
        _errorPageIndex = requestedPageIndex;
        _loading = false;
      });
    }
  }

  /// A page past the end (rows were deleted since) falls back to the last
  /// page that still has rows.
  Future<ServerHistoryPage> _fetchPage(
    int pageIndex, {
    required int? userId,
    required bool allUsers,
  }) async {
    Future<ServerHistoryPage> fetch(int index) => _api.fetchHistoryPage(
      limit: _pageSize,
      offset: index * _pageSize,
      userId: userId,
      allUsers: allUsers,
    );
    final page = await fetch(pageIndex);
    if (page.items.isEmpty && page.total > 0 && pageIndex > 0) {
      final lastPageIndex = (page.total - 1) ~/ _pageSize;
      if (lastPageIndex != pageIndex) return fetch(lastPageIndex);
    }
    return page;
  }

  /// The user filter is a convenience: without the list the history itself
  /// still loads.
  Future<void> _loadUsers(AuthUser self) async {
    try {
      final users = await _api.fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _usersLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _users = [self]);
      showErrorSnackBar(context, context.l.serverHistoryUsersUnavailable);
    }
  }

  void _scheduleThumbnailPreload() {
    _thumbnailPreloadTimer?.cancel();
    _thumbnailPreloadTimer = Timer(
      const Duration(milliseconds: 120),
      _preloadVisibleThumbnails,
    );
  }

  void _preloadVisibleThumbnails({bool force = false}) {
    final entries = _entries;
    if (!mounted || entries.isEmpty) return;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final firstRow = _gridMainExtent <= 0
        ? 0
        : math.max(0, offset ~/ _gridMainExtent);
    var start = firstRow * _gridColumns;
    if (start < 0) start = 0;
    if (start > entries.length) start = entries.length;
    final end = math.min(entries.length, start + 20);
    if (!force && start == _lastPreloadStart && end == _lastPreloadEnd) {
      return;
    }
    _lastPreloadStart = start;
    _lastPreloadEnd = end;
    for (var i = start; i < end; i += 1) {
      for (final item
          in entries[i].items.where((item) => item.hasImage).take(4)) {
        unawaited(
          precacheImage(
            NetworkImage(item.thumbnailUrl),
            context,
            onError: (_, _) {},
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<BackendAuthNotifier>();
    final t = context.t;
    final touch = windowSizeClassOf(context).isTouchSized;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        elevation: 0,
        toolbarHeight: context.touchSize,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: touch ? VisionMetrics.iconLarge : VisionMetrics.iconMedium,
            color: t.secondaryText,
          ),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l.serverHistoryTitle.toUpperCase(),
          style: TextStyle(
            color: t.headerText,
            fontSize: t.titleSize(touch ? 12 : 10),
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        actions: [
          if (auth.user?.isAdmin == true)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: touch ? 150 : 220),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _selectedUserId,
                  isExpanded: true,
                  dropdownColor: t.surfaceHigh,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: t.fontSize(10),
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(context.l.serverHistoryAllUsers),
                    ),
                    ..._users.map(
                      (user) => DropdownMenuItem<int?>(
                        value: user.id,
                        child: Text(user.username),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedUserId = value);
                    _load(pageIndex: 0);
                  },
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.refresh,
              size: touch ? VisionMetrics.iconLarge : VisionMetrics.iconMedium,
              color: t.secondaryText,
            ),
            tooltip: context.l.serverHistoryRefresh,
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const LoadingState();
    }
    final error = _error;
    if (error != null && _items.isEmpty && _totalItems == 0) {
      return Column(children: [_buildErrorBanner(context, error)]);
    }
    return Column(
      children: [
        if (error != null) _buildErrorBanner(context, error),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: _entries.isEmpty
                ? _buildEmptyList(context)
                : _buildGrid(context),
          ),
        ),
        if (_totalItems > 0)
          _HistoryPaginationBar(
            pageIndex: _pageIndex,
            pageSize: _pageSize,
            totalItems: _totalItems,
            loading: _loading,
            onPrevious: _pageIndex <= 0
                ? null
                : () => _load(pageIndex: _pageIndex - 1),
            onNext: (_pageIndex + 1) * _pageSize >= _totalItems
                ? null
                : () => _load(pageIndex: _pageIndex + 1),
          ),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context, Object error) {
    return Padding(
      padding: const EdgeInsets.all(VisionMetrics.space8),
      child: ErrorBanner(
        message: context.l.serverHistoryLoadFailed(
          backendErrorMessage(context.l, error),
        ),
        retryLabel: context.l.serverHistoryRetry,
        onRetry: _loading ? null : () => _load(pageIndex: _errorPageIndex),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _gridColumns = ResultSetGridSpec.columnCount(width);
        _gridMainExtent = ResultSetGridSpec.rowExtent(width);
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(ResultSetGridSpec.padding),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: ResultSetGridSpec.delegate,
          itemCount: _entries.length,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return _HistoryEntryCard(
              entry: entry,
              onOpen: () => _openEntry(entry),
              onImport: () async {
                if (await _importEntry(entry) && mounted) {
                  Navigator.of(this.context).pop(true);
                }
              },
              onDownload: () => _downloadEntry(entry),
              onDelete: () => _deleteEntry(entry),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyList(BuildContext context) {
    // A scrollable root keeps pull-to-refresh working on an empty page.
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: EmptyState(
              icon: Icons.history,
              message: context.l.serverHistoryEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _deleteEntry(_HistoryEntry entry) =>
      entry.isBatch ? _deleteBatch(entry.items) : _deleteItem(entry.lead);

  Future<bool> _importEntry(_HistoryEntry entry) =>
      entry.isBatch ? _importBatch(entry.items) : _importItem(entry.lead);

  void _downloadEntry(_HistoryEntry entry) =>
      entry.isBatch ? _downloadBatch(entry.items) : _downloadItem(entry.lead);

  Future<bool> _deleteItem(ServerHistoryItem item) => _confirmAndDelete(
    title: context.l.commonDelete,
    message: context.l.serverHistoryDeleteConfirm,
    delete: () => _api.deleteHistoryItem(item.id),
  );

  Future<bool> _deleteBatch(List<ServerHistoryItem> items) {
    final batchId = items.first.batchId;
    if (batchId == null || batchId.isEmpty) return Future.value(false);
    return _confirmAndDelete(
      title: context.l.serverHistoryBatchDelete,
      message: context.l.serverHistoryBatchDeleteConfirm,
      delete: () => _api.deleteHistoryBatch(batchId),
    );
  }

  /// Deletes, then re-reads the current page: the server pages by offset, so
  /// trimming the local list would skip a batch on the next page. A page the
  /// delete emptied falls back to the previous one in [_fetchPage].
  Future<bool> _confirmAndDelete({
    required String title,
    required String message,
    required Future<void> Function() delete,
  }) async {
    final confirm = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: context.l.commonDelete,
      cancelLabel: context.l.commonCancel,
    );
    if (!mounted || confirm != true) return false;
    try {
      await delete();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          context.l.serverHistoryDeleteFailed(
            backendErrorMessage(context.l, e),
          ),
        );
      }
      return false;
    }
    if (mounted) await _load();
    return true;
  }

  void _openEntry(_HistoryEntry entry) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: context.tRead.background,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, _) => _HistoryResultSetDialog(
        entry: entry,
        onImportItem: (item) async {
          final imported = await _importItem(item);
          if (!imported || !dialogContext.mounted || !mounted) return;
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pop(true);
        },
        onDownloadItem: _downloadItem,
        onDeleteItem: _deleteItem,
        onImportBatch: () async {
          final imported = await _importBatch(entry.items);
          if (!imported || !dialogContext.mounted || !mounted) return;
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pop(true);
        },
        onDownloadBatch: () => _downloadBatch(entry.items),
        onDeleteBatch: () async {
          if (await _deleteBatch(entry.items) && dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        },
      ),
    );
  }

  Future<bool> _importItem(ServerHistoryItem item) =>
      _importParameters(item, batch: false);

  Future<bool> _importParameters(
    ServerHistoryItem item, {
    required bool batch,
  }) async {
    var stage = 'resolve_notifier';
    final diagnostics = ClientDiagnostics.instance;
    diagnostics.record('history_parameter_import_started', {
      'batch': batch,
      'record_id': item.id,
      'record_prompt_length': item.prompt.length,
      'request_present': item.request != null,
    });
    try {
      final notifier = context.read<GenerationNotifier>();
      stage = 'parse_parameters';
      final result = notifier.parseHistoryParameters(item);
      diagnostics.record('history_parameter_import_parsed', {
        'batch': batch,
        'prompt_length': result.prompt.length,
        'negative_length': result.negativePrompt.length,
        'character_count': result.characters.length,
      });
      stage = 'apply_parameters';
      final categories = ImportCategory.values.toSet();
      if (batch) categories.remove(ImportCategory.seed);
      notifier.applyImportedMetadata(result, categories);
      if (!batch) notifier.seedController.text = item.seed.toString();
      diagnostics.record('history_parameter_import_applied', {
        'batch': batch,
        'prompt_length': notifier.promptController.text.length,
        'negative_length': notifier.negativePromptController.text.length,
      });
      if (!mounted) return false;
      stage = 'show_success';
      showAppSnackBar(
        context,
        batch
            ? context.l.serverHistoryBatchImportSuccess
            : context.l.serverHistoryImportSuccess,
      );
      return true;
    } catch (error, stack) {
      diagnostics.record('history_parameter_import_failed', {
        'batch': batch,
        'stage': stage,
        'error_type': error.runtimeType.toString(),
        'error_category': switch (error) {
          ProviderNotFoundException() => 'provider_not_found',
          FormatException() => 'format',
          TypeError() => 'type',
          StateError() => 'state',
          _ => 'other',
        },
        // Stack frames identify the failing code without recording parameters.
        for (final (index, frame)
            in stack.toString().split('\n').take(8).indexed)
          'stack_frame_$index': frame,
      });
      if (mounted) {
        showErrorSnackBar(context, context.l.importNothingAvailable);
      }
      return false;
    }
  }

  Future<void> _downloadItem(ServerHistoryItem item) async {
    if (!item.hasImage) return;
    try {
      final bytes = await _api.fetchImageBytes(item.id);
      final ok = downloadBytes(bytes, item.downloadFileName);
      if (!ok) throw StateError('browser download is unavailable');
      if (mounted) {
        showAppSnackBar(
          context,
          context.l.gallerySavedTo(item.downloadFileName),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          context.l.galleryExportFailed(backendErrorMessage(context.l, e)),
        );
      }
    }
  }

  Future<bool> _importBatch(List<ServerHistoryItem> items) async {
    final item = items.firstOrNull;
    if (item == null) {
      showErrorSnackBar(context, context.l.importNothingAvailable);
      return false;
    }
    return _importParameters(item, batch: true);
  }

  Future<void> _downloadBatch(List<ServerHistoryItem> items) async {
    final imageItems = items.where((item) => item.hasImage).toList();
    if (imageItems.isEmpty) return;
    try {
      final images = await Future.wait(
        imageItems.map(
          (item) async => (item, await _api.fetchImageBytes(item.id)),
        ),
      );
      final archive = Archive();
      for (final (item, bytes) in images) {
        archive.addFile(
          ArchiveFile(item.downloadFileName, bytes.length, bytes),
        );
      }
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final batchId = items.first.batchId ?? items.first.id;
      final fileName = 'NAIWeaver_batch_$batchId.zip';
      final ok = downloadBytes(bytes, fileName, mimeType: 'application/zip');
      if (!ok) throw StateError('browser download is unavailable');
      if (mounted) {
        showAppSnackBar(context, context.l.gallerySavedTo(fileName));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          context.l.galleryExportFailed(backendErrorMessage(context.l, e)),
        );
      }
    }
  }
}

class _HistoryPaginationBar extends StatelessWidget {
  const _HistoryPaginationBar({
    required this.pageIndex,
    required this.pageSize,
    required this.totalItems,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
  });

  final int pageIndex;
  final int pageSize;
  final int totalItems;
  final bool loading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final localizations = MaterialLocalizations.of(context);
    final safePageSize = math.max(1, pageSize);
    final totalPages = totalItems <= 0
        ? 1
        : ((totalItems + safePageSize - 1) ~/ safePageSize);
    final safePageIndex = math.min(
      math.max(0, pageIndex),
      math.max(0, totalPages - 1),
    );
    final start = totalItems <= 0 ? 0 : safePageIndex * safePageSize + 1;
    final end = totalItems <= 0
        ? 0
        : math.min(totalItems, (safePageIndex + 1) * safePageSize);
    final pageText =
        '${safePageIndex + 1} / $totalPages · $start-$end / $totalItems';

    return Material(
      color: t.background,
      child: Container(
        height: context.hitSize + VisionMetrics.space4,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.borderSubtle)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.chevron_left, size: 18, color: t.headerText),
                  tooltip: localizations.previousPageTooltip,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: context.hitSize,
                    minHeight: context.hitSize,
                  ),
                  onPressed: loading ? null : onPrevious,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  pageText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(11),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.accent,
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: t.headerText,
                        ),
                        tooltip: localizations.nextPageTooltip,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: context.hitSize,
                          minHeight: context.hitSize,
                        ),
                        onPressed: onNext,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry({required this.key, required this.items});

  final String key;
  final List<ServerHistoryItem> items;

  bool get isBatch => lead.isBatch;

  /// Items of one multi-image batch share an entry; a single image (a batch
  /// of one) is its own.
  static String keyOf(ServerHistoryItem item) {
    final batchId = item.batchId?.trim();
    return item.isBatch && batchId != null && batchId.isNotEmpty
        ? 'batch:$batchId'
        : 'item:${item.id}';
  }

  ServerHistoryItem get lead => items.first;
  ServerHistoryItem get cover =>
      items.where((item) => item.hasImage).firstOrNull ?? lead;

  static List<_HistoryEntry> fromItems(List<ServerHistoryItem> source) {
    final grouped = <String, List<ServerHistoryItem>>{};
    final keys = <String>[];
    for (final item in source) {
      final key = keyOf(item);
      if (!grouped.containsKey(key)) keys.add(key);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return keys
        .map((key) {
          final items = List<ServerHistoryItem>.of(grouped[key]!);
          items.sort((a, b) {
            final aIndex = a.batchIndex;
            final bIndex = b.batchIndex;
            if (aIndex == null && bIndex == null) return 0;
            if (aIndex == null) return 1;
            if (bIndex == null) return -1;
            return aIndex.compareTo(bIndex);
          });
          return _HistoryEntry(key: key, items: items);
        })
        .toList(growable: false);
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({
    required this.entry,
    required this.onOpen,
    required this.onImport,
    required this.onDownload,
    required this.onDelete,
  });

  final _HistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Material(
      key: ValueKey<String>('history-entry-${entry.key}'),
      color: t.surfaceMid,
      borderRadius: BorderRadius.circular(VisionMetrics.radius8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: CardActionLayout(
          content: _HistoryEntryThumbnail(entry: entry),
          badge: entry.isBatch
              ? _HistoryBatchBadge(count: entry.items.length)
              : null,
          action: _HistoryMenu(
            batch: entry.isBatch,
            hasImage: entry.items.any((item) => item.hasImage),
            deletable: !entry.items.any((item) => item.isActive),
            onImport: onImport,
            onDownload: onDownload,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }
}

class _HistoryEntryThumbnail extends StatelessWidget {
  const _HistoryEntryThumbnail({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final items = entry.items.where((item) => item.hasImage).take(4).toList();
    if (items.isEmpty) return _PlaceholderIcon(item: entry.lead);
    if (!entry.isBatch || items.length == 1) {
      return _image(context, items.first);
    }
    if (items.length == 2) {
      return Row(
        children: [
          Expanded(child: _image(context, items[0])),
          const SizedBox(width: 1),
          Expanded(child: _image(context, items[1])),
        ],
      );
    }
    if (items.length == 3) {
      return Row(
        children: [
          Expanded(child: _image(context, items[0])),
          const SizedBox(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _image(context, items[1])),
                const SizedBox(height: 1),
                Expanded(child: _image(context, items[2])),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(context, items[0])),
              const SizedBox(width: 1),
              Expanded(child: _image(context, items[1])),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(context, items[2])),
              const SizedBox(width: 1),
              Expanded(child: _image(context, items[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _image(BuildContext context, ServerHistoryItem item) {
    return ColoredBox(
      key: ValueKey<String>('history-collage-${entry.key}-${item.id}'),
      color: context.t.background,
      child: SizedBox.expand(
        child: Image.network(
          item.thumbnailUrl,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _PlaceholderIcon(item: item),
        ),
      ),
    );
  }
}

class _HistoryBatchBadge extends StatelessWidget {
  const _HistoryBatchBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppPill(icon: Icons.layers_outlined, text: '$count', dense: true);
  }
}

class _HistoryResultSetDialog extends StatefulWidget {
  const _HistoryResultSetDialog({
    required this.entry,
    required this.onImportItem,
    required this.onDownloadItem,
    required this.onDeleteItem,
    required this.onImportBatch,
    required this.onDownloadBatch,
    required this.onDeleteBatch,
  });

  final _HistoryEntry entry;
  final Future<void> Function(ServerHistoryItem) onImportItem;
  final Future<void> Function(ServerHistoryItem) onDownloadItem;
  final Future<bool> Function(ServerHistoryItem) onDeleteItem;
  final VoidCallback onImportBatch;
  final VoidCallback onDownloadBatch;
  final VoidCallback onDeleteBatch;

  @override
  State<_HistoryResultSetDialog> createState() =>
      _HistoryResultSetDialogState();
}

class _HistoryResultSetDialogState extends State<_HistoryResultSetDialog> {
  late final List<ServerHistoryItem> _items = List.of(widget.entry.items);
  late String _selectedId = _items.first.id;

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final t = context.t;
    final compact = windowSizeClassOf(context) == WindowSizeClass.compact;
    final viewItems = <ResultSetViewItem>[
      for (var index = 0; index < _items.length; index += 1)
        ResultSetViewItem(
          id: _items[index].id,
          position: index + 1,
          count: _items.length,
          previewImage: _items[index].hasImage
              ? NetworkImage(_items[index].imageUrl)
              : null,
          thumbnailImage: _items[index].hasImage
              ? NetworkImage(_items[index].thumbnailUrl)
              : null,
          imageUrl: _items[index].hasImage ? _items[index].imageUrl : null,
          width: _items[index].width,
          height: _items[index].height,
          seed: _items[index].seed,
          infoTitle: _items[index].prompt,
          infoSubtitle: _items[index].downloadFileName,
          isGenerating:
              _items[index].status == 'queued' ||
              _items[index].status == 'running',
          errorMessage: _historyFailureMessage(context.l, _items[index]),
        ),
    ];
    final selectedItem = _items.singleWhere(
      (candidate) => candidate.id == _selectedId,
    );
    return Material(
      color: t.background,
      child: SafeArea(
        child: ResultSetWorkspace(
          items: viewItems,
          selectedId: _selectedId,
          onSelect: (id) => setState(() => _selectedId = id),
          mobile: compact,
          pulseAnimation: const AlwaysStoppedAnimation<double>(0),
          headerLeading: _HistoryViewerLeading(
            onClose: () => Navigator.of(context).pop(),
          ),
          headerTrailingBuilder: (context, mode) {
            if (mode == ResultSetWorkspaceMode.grid && widget.entry.isBatch) {
              return CardActionFrame(
                child: _HistoryMenu(
                  key: const ValueKey<String>('history-batch-actions'),
                  batch: true,
                  hasImage: _items.any((item) => item.hasImage),
                  deletable: !_items.any((item) => item.isActive),
                  onImport: widget.onImportBatch,
                  onDownload: widget.onDownloadBatch,
                  onDelete: widget.onDeleteBatch,
                ),
              );
            }
            return CardActionFrame(
              child: _HistoryMenu(
                key: const ValueKey<String>('history-item-actions'),
                batch: false,
                hasImage: selectedItem.hasImage,
                deletable: !selectedItem.isActive,
                onImport: () => widget.onImportItem(selectedItem),
                onDownload: () => widget.onDownloadItem(selectedItem),
                onDelete: () => _delete(selectedItem),
              ),
            );
          },
          gridItemTrailingBuilder: (context, viewItem) {
            final item = _items.singleWhere(
              (candidate) => candidate.id == viewItem.id,
            );
            return _HistoryMenu(
              key: ValueKey<String>('history-grid-item-actions-${item.id}'),
              batch: false,
              hasImage: item.hasImage,
              deletable: !item.isActive,
              onImport: () => widget.onImportItem(item),
              onDownload: () => widget.onDownloadItem(item),
              onDelete: () => _delete(item),
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(ServerHistoryItem item) async {
    if (!await widget.onDeleteItem(item) || !mounted) return;
    setState(() {
      _items.removeWhere((candidate) => candidate.id == item.id);
      if (_items.isNotEmpty && !_items.any((item) => item.id == _selectedId)) {
        _selectedId = _items.first.id;
      }
    });
    if (_items.isEmpty && mounted) Navigator.of(context).pop();
  }
}

class _HistoryViewerLeading extends StatelessWidget {
  const _HistoryViewerLeading({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return OverlayActionButton(
      icon: Icons.close,
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: onClose,
    );
  }
}

/// The actions of one history card or viewer item; [batch] switches to the
/// whole-batch wording. A queued or running item cannot be deleted (the
/// gateway answers 409 `task_active`), so the entry says why it is disabled.
class _HistoryMenu extends StatelessWidget {
  const _HistoryMenu({
    super.key,
    required this.batch,
    required this.hasImage,
    required this.deletable,
    required this.onImport,
    required this.onDownload,
    required this.onDelete,
  });

  final bool batch;
  final bool hasImage;
  final bool deletable;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    const iconSize = VisionMetrics.iconMedium;
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      color: t.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VisionMetrics.radius8),
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: batch ? 176 : 148),
      icon: Icon(Icons.more_horiz, size: iconSize, color: t.headerText),
      iconSize: iconSize,
      splashRadius: iconSize,
      onCanceled: () =>
          ClientDiagnostics.instance.record('history_menu_cancelled'),
      onSelected: (value) {
        ClientDiagnostics.instance.record('history_menu_action', {
          'action': value,
        });
        if (value == 'import') {
          onImport();
        } else if (value == 'download') {
          onDownload();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'import',
          child: _HistoryMenuItem(
            icon: Icons.upload_outlined,
            label: batch
                ? l.serverHistoryBatchImportParameters
                : l.serverHistoryImportParameters,
          ),
        ),
        if (hasImage)
          PopupMenuItem<String>(
            value: 'download',
            child: _HistoryMenuItem(
              icon: Icons.download,
              label: batch
                  ? l.serverHistoryBatchDownload
                  : l.serverHistoryDownload,
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: deletable,
          child: deletable
              ? _HistoryMenuItem(
                  icon: Icons.delete_outline,
                  label: batch ? l.serverHistoryBatchDelete : l.commonDelete,
                  danger: true,
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: _HistoryMenuItem(
                    icon: Icons.hourglass_empty,
                    label: l.serverHistoryDeleteActive,
                  ),
                ),
        ),
      ],
    );
  }
}

class _HistoryMenuItem extends StatelessWidget {
  const _HistoryMenuItem({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = danger ? t.accentDanger : t.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: t.fontSize(11),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon({required this.item});

  final ServerHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final reason = _historyFailureMessage(context.l, item);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              reason != null ? Icons.error_outline : Icons.hourglass_empty,
              color: reason != null ? t.accentDanger : t.textDisabled,
              size: 28,
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Text(
                reason,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: t.fontSize(9),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Why an item failed, localized from its contract `error_code`; null while
/// it has not failed.
String? _historyFailureMessage(AppLocalizations l, ServerHistoryItem item) {
  if (item.status == 'cancelled' && item.errorCode == null) {
    return l.serverHistoryItemCancelled;
  }
  return taskItemFailureMessage(l, item.status, item.errorCode);
}
