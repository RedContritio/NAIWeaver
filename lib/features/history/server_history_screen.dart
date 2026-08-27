import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/services/backend_auth_api.dart';
import '../../core/services/backend_history_api.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/web_download.dart';
import '../../core/widgets/confirm_dialog.dart';
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
  List<AuthUser> _users = const [];
  int? _selectedUserId;
  bool _filterInitialized = false;
  int _loadGeneration = 0;
  int _pageIndex = 0;
  int _totalItems = 0;
  bool _loading = true;
  String? _error;
  Timer? _thumbnailPreloadTimer;
  int _gridColumns = 2;
  double _gridMainExtent = 260;
  int _lastPreloadStart = -1;
  int _lastPreloadEnd = -1;

  List<_HistoryEntry> get _historyEntries => _HistoryEntry.fromItems(_items);

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

  Future<void> _load({int? pageIndex}) async {
    final auth = context.read<BackendAuthNotifier>();
    final isAdmin = auth.user?.isAdmin == true;
    if (!_filterInitialized) {
      _selectedUserId = auth.user?.id;
      _filterInitialized = true;
    }
    if (isAdmin &&
        auth.user != null &&
        !_users.any((user) => user.id == auth.user!.id)) {
      _users = [auth.user!, ..._users];
    }
    final selectedUserId = _selectedUserId;
    final nextPageIndex = math.max(0, pageIndex ?? _pageIndex);
    final loadGeneration = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _pageIndex = nextPageIndex;
    });
    try {
      List<AuthUser>? users;
      if (isAdmin) {
        users = await _api.fetchUsers();
      }
      var page = await _api.fetchHistoryPage(
        limit: _pageSize,
        offset: nextPageIndex * _pageSize,
        userId: selectedUserId,
        allUsers: isAdmin && selectedUserId == null,
      );
      if (page.items.isEmpty && page.total > 0 && nextPageIndex > 0) {
        final fallbackPageIndex = math.max(0, (page.total - 1) ~/ _pageSize);
        if (fallbackPageIndex != nextPageIndex) {
          page = await _api.fetchHistoryPage(
            limit: _pageSize,
            offset: fallbackPageIndex * _pageSize,
            userId: selectedUserId,
            allUsers: isAdmin && selectedUserId == null,
          );
        }
      }
      if (!mounted || loadGeneration != _loadGeneration) return;
      if (users != null) _users = users;
      _items = page.items;
      _totalItems = page.total;
      _pageIndex = page.pageIndex;
      _lastPreloadStart = -1;
      _lastPreloadEnd = -1;
    } catch (e) {
      if (loadGeneration != _loadGeneration) return;
      _error = e.toString();
    } finally {
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() => _loading = false);
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _preloadVisibleThumbnails(force: true);
        });
      }
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
    final entries = _historyEntries;
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
    final mobile = isMobile(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        elevation: 0,
        toolbarHeight: mobile ? 48 : 32,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: mobile ? 20 : 14,
            color: t.secondaryText,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l.serverHistoryTitle.toUpperCase(),
          style: TextStyle(
            color: t.headerText,
            fontSize: t.titleSize(mobile ? 12 : 10),
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        actions: [
          if (auth.user?.isAdmin == true)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: mobile ? 150 : 220),
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
                    setState(() {
                      _selectedUserId = value;
                      _pageIndex = 0;
                    });
                    _load(pageIndex: 0);
                  },
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.refresh,
              size: mobile ? 20 : 16,
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
    final t = context.t;
    if (_loading && _items.isEmpty) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(11)),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return _buildEmptyBody(context);
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                _gridColumns = ResultSetGridSpec.columnCount(width);
                _gridMainExtent = ResultSetGridSpec.rowExtent(width);
                final entries = _historyEntries;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _preloadVisibleThumbnails();
                });
                return GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(ResultSetGridSpec.padding),
                  physics: const AlwaysScrollableScrollPhysics(),
                  gridDelegate: ResultSetGridSpec.delegate,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final singleItem = entry.isBatch
                        ? null
                        : entry.items.single;
                    return _HistoryEntryCard(
                      entry: entry,
                      onOpen: () => _openEntry(entry),
                      onImport: entry.isBatch
                          ? () => _importBatch(entry.items)
                          : () async {
                              if (await _importItem(singleItem!) && mounted) {
                                Navigator.of(this.context).pop();
                              }
                            },
                      onDownload: entry.isBatch
                          ? () => _downloadBatch(entry.items)
                          : () => _downloadItem(singleItem!),
                      onDelete: entry.isBatch
                          ? () => _deleteBatch(entry.items)
                          : () => _deleteItem(singleItem!),
                    );
                  },
                );
              },
            ),
          ),
        ),
        _HistoryPaginationBar(
          pageIndex: _pageIndex,
          pageSize: _pageSize,
          totalItems: _totalItems,
          loading: _loading,
          onPrevious: _pageIndex <= 0
              ? null
              : () => _load(pageIndex: _pageIndex - 1),
          onNext: ((_pageIndex + 1) * _pageSize >= _totalItems)
              ? null
              : () => _load(pageIndex: _pageIndex + 1),
        ),
      ],
    );
  }

  Widget _buildEmptyBody(BuildContext context) {
    final t = context.t;
    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 96),
              Icon(Icons.history, size: 48, color: t.textDisabled),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  context.l.serverHistoryEmpty,
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(12),
                  ),
                ),
              ),
            ],
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
            onNext: null,
          ),
      ],
    );
  }

  int get _totalPages =>
      _totalItems <= 0 ? 1 : ((_totalItems + _pageSize - 1) ~/ _pageSize);

  Future<bool> _deleteItem(ServerHistoryItem item) async {
    final t = context.tRead;
    final confirm = await showConfirmDialog(
      context,
      title: context.l.commonDelete,
      message: context.l.serverHistoryDeleteConfirm,
      confirmLabel: context.l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (!mounted || confirm != true) return false;

    try {
      await _api.deleteHistoryItem(item.id);
      if (!mounted) return false;
      String entryKey(ServerHistoryItem candidate) {
        final batchId = candidate.batchId?.trim();
        return batchId == null || batchId.isEmpty ? candidate.id : batchId;
      }

      final batchKey = entryKey(item);
      final removesBatch =
          _items.where((candidate) => entryKey(candidate) == batchKey).length ==
          1;
      setState(() {
        _items = _items.where((candidate) => candidate.id != item.id).toList();
        if (removesBatch) _totalItems = math.max(0, _totalItems - 1);
      });
      if (_items.isEmpty && _pageIndex > 0) {
        final fallbackPageIndex = math.min(_pageIndex - 1, _totalPages - 1);
        unawaited(_load(pageIndex: fallbackPageIndex));
      }
      return true;
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
      return false;
    }
  }

  void _openEntry(_HistoryEntry entry) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, _) => _HistoryResultSetDialog(
        entry: entry,
        onImportItem: (item) async {
          final imported = await _importItem(item);
          if (!imported || !dialogContext.mounted || !mounted) return;
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pop();
        },
        onDownloadItem: _downloadItem,
        onDeleteItem: _deleteItem,
        onImportBatch: () => _importBatch(entry.items),
        onDownloadBatch: () => _downloadBatch(entry.items),
        onDeleteBatch: () async {
          if (await _deleteBatch(entry.items) && dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        },
      ),
    );
  }

  Future<bool> _importItem(ServerHistoryItem item) async {
    if (!item.hasImage) return false;
    try {
      final bytes = await _api.fetchImageBytes(item.id);
      if (!mounted) return false;
      final notifier = context.read<GenerationNotifier>();
      final result = await notifier.parseImageMetadataBytes(bytes);
      notifier.applyImportedMetadata(result, ImportCategory.values.toSet());
      // The history row is authoritative for the selected image's seed. PNG
      // metadata can be absent or incomplete after external processing.
      notifier.seedController.text = item.seed.toString();
      if (!mounted) return false;
      showAppSnackBar(context, context.l.serverHistoryImportSuccess);
      return true;
    } catch (_) {
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
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
    }
  }

  Future<void> _importBatch(List<ServerHistoryItem> items) async {
    final imageItem = items.where((item) => item.hasImage).firstOrNull;
    if (imageItem == null) {
      showErrorSnackBar(context, context.l.importNothingAvailable);
      return;
    }
    try {
      final bytes = await _api.fetchImageBytes(imageItem.id);
      if (!mounted) return;
      final notifier = context.read<GenerationNotifier>();
      final result = await notifier.parseImageMetadataBytes(bytes);
      final categories = ImportCategory.values.toSet()
        ..remove(ImportCategory.seed);
      notifier.applyImportedMetadata(result, categories);
      if (!mounted) return;
      showAppSnackBar(context, context.l.serverHistoryBatchImportSuccess);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context, context.l.importNothingAvailable);
      }
    }
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
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
    }
  }

  Future<bool> _deleteBatch(List<ServerHistoryItem> items) async {
    final batchId = items.first.batchId;
    if (batchId == null || batchId.isEmpty) return false;
    final t = context.tRead;
    final confirm = await showConfirmDialog(
      context,
      title: context.l.serverHistoryBatchDelete,
      message: context.l.serverHistoryBatchDeleteConfirm,
      confirmLabel: context.l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (!mounted || confirm != true) return false;

    try {
      await _api.deleteHistoryBatch(batchId);
      if (!mounted) return false;
      final ids = items.map((item) => item.id).toSet();
      setState(() {
        _items = _items.where((item) => !ids.contains(item.id)).toList();
        _totalItems = math.max(0, _totalItems - 1);
      });
      if (_items.isEmpty && _pageIndex > 0) {
        final fallbackPageIndex = math.min(_pageIndex - 1, _totalPages - 1);
        unawaited(_load(pageIndex: fallbackPageIndex));
      }
      return true;
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
      return false;
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
        height: 44,
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
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
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
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
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

  bool get isBatch {
    final batchId = lead.batchId?.trim();
    return batchId != null && batchId.isNotEmpty;
  }

  ServerHistoryItem get lead => items.first;
  ServerHistoryItem get cover =>
      items.where((item) => item.hasImage).firstOrNull ?? lead;

  static List<_HistoryEntry> fromItems(List<ServerHistoryItem> source) {
    final grouped = <String, List<ServerHistoryItem>>{};
    final keys = <String>[];
    for (final item in source) {
      final batchId = item.batchId?.trim();
      final key = batchId == null || batchId.isEmpty
          ? 'item:${item.id}'
          : 'batch:$batchId';
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

class _HistoryEntryCard extends StatefulWidget {
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
  State<_HistoryEntryCard> createState() => _HistoryEntryCardState();
}

class _HistoryEntryCardState extends State<_HistoryEntryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mobile = isMobile(context);
    final auth = context.watch<BackendAuthNotifier>();
    final admin = auth.user?.isAdmin == true;
    final entry = widget.entry;
    final lead = entry.lead;
    final cover = entry.cover;

    Widget card = Material(
      key: ValueKey<String>('history-entry-${entry.key}'),
      color: t.surfaceMid,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _HistoryEntryThumbnail(entry: entry),
            if (_hovered && !mobile)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: t.background.withValues(alpha: 0.75),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (lead.prompt.isNotEmpty)
                            Text(
                              lead.prompt,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: t.fontSize(9),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            admin && lead.username.isNotEmpty
                                ? '${lead.username} · ${cover.downloadFileName}'
                                : cover.downloadFileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textDisabled,
                              fontSize: t.fontSize(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (entry.isBatch)
              Positioned(
                left: 7,
                bottom: 7,
                child: _HistoryBatchBadge(count: entry.items.length),
              ),
            Positioned(
              top: 5,
              right: 5,
              child: _HistoryMoreButtonFrame(
                child: entry.isBatch
                    ? _HistoryBatchMenu(
                        hasImage: entry.items.any((item) => item.hasImage),
                        onImport: widget.onImport,
                        onDownload: widget.onDownload,
                        onDelete: widget.onDelete,
                      )
                    : _HistoryCardMenu(
                        item: lead,
                        onImport: widget.onImport,
                        onDownload: widget.onDownload,
                        onDelete: widget.onDelete,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mobile) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: card,
      );
    }
    return card;
  }
}

class _HistoryEntryThumbnail extends StatelessWidget {
  const _HistoryEntryThumbnail({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final items = entry.items.where((item) => item.hasImage).take(4).toList();
    if (items.isEmpty) return _PlaceholderIcon(status: entry.lead.status);
    if (!entry.isBatch || items.length == 1) return _image(items.first);
    if (items.length == 2) {
      return Row(
        children: [
          Expanded(child: _image(items[0])),
          const SizedBox(width: 1),
          Expanded(child: _image(items[1])),
        ],
      );
    }
    if (items.length == 3) {
      return Row(
        children: [
          Expanded(child: _image(items[0])),
          const SizedBox(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _image(items[1])),
                const SizedBox(height: 1),
                Expanded(child: _image(items[2])),
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
              Expanded(child: _image(items[0])),
              const SizedBox(width: 1),
              Expanded(child: _image(items[1])),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(items[2])),
              const SizedBox(width: 1),
              Expanded(child: _image(items[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _image(ServerHistoryItem item) {
    return ColoredBox(
      key: ValueKey<String>('history-collage-${entry.key}-${item.id}'),
      color: Colors.black,
      child: SizedBox.expand(
        child: Image.network(
          item.thumbnailUrl,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _PlaceholderIcon(status: item.status),
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
    final t = context.t;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_outlined, size: 12, color: t.accent),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: t.headerText,
                fontSize: t.fontSize(9),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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
    final mobile = isMobile(context);
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
          errorMessage: _items[index].errorMessage,
        ),
    ];
    final selectedItem = _items.singleWhere(
      (candidate) => candidate.id == _selectedId,
    );
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: ResultSetWorkspace(
          items: viewItems,
          selectedId: _selectedId,
          onSelect: (id) => setState(() => _selectedId = id),
          mobile: mobile,
          pulseAnimation: const AlwaysStoppedAnimation<double>(0),
          headerLeading: _HistoryViewerLeading(
            onClose: () => Navigator.of(context).pop(),
          ),
          headerTrailingBuilder: (context, mode) {
            if (mode == ResultSetWorkspaceMode.grid && widget.entry.isBatch) {
              return _HistoryMoreButtonFrame(
                child: _HistoryBatchMenu(
                  key: const ValueKey<String>('history-batch-actions'),
                  hasImage: _items.any((item) => item.hasImage),
                  onImport: widget.onImportBatch,
                  onDownload: widget.onDownloadBatch,
                  onDelete: widget.onDeleteBatch,
                ),
              );
            }
            return _HistoryMoreButtonFrame(
              child: _HistoryCardMenu(
                key: const ValueKey<String>('history-item-actions'),
                item: selectedItem,
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
            return _HistoryMoreButtonFrame(
              child: _HistoryCardMenu(
                key: ValueKey<String>('history-grid-item-actions-${item.id}'),
                item: item,
                onImport: () => widget.onImportItem(item),
                onDownload: () => widget.onDownloadItem(item),
                onDelete: () => _delete(item),
              ),
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
    return _HistoryIconButton(
      icon: Icons.close,
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: onClose,
    );
  }
}

class _HistoryMoreButtonFrame extends StatelessWidget {
  const _HistoryMoreButtonFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SizedBox(
      width: 32,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.background.withValues(alpha: 0.78),
          border: Border.all(color: t.borderSubtle),
          borderRadius: BorderRadius.circular(5),
        ),
        child: child,
      ),
    );
  }
}

class _HistoryCardMenu extends StatelessWidget {
  const _HistoryCardMenu({
    super.key,
    required this.item,
    required this.onImport,
    required this.onDownload,
    required this.onDelete,
  });

  final ServerHistoryItem item;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      color: t.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 148),
      icon: Icon(Icons.more_horiz, size: 14, color: t.headerText),
      iconSize: 14,
      splashRadius: 14,
      onSelected: (value) {
        if (value == 'import') {
          onImport();
        } else if (value == 'download') {
          onDownload();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        if (item.hasImage) ...[
          PopupMenuItem<String>(
            value: 'import',
            child: _HistoryMenuItem(
              icon: Icons.upload_outlined,
              label: context.l.serverHistoryImportParameters,
            ),
          ),
          PopupMenuItem<String>(
            value: 'download',
            child: _HistoryMenuItem(
              icon: Icons.download,
              label: context.l.serverHistoryDownload,
            ),
          ),
        ],
        PopupMenuItem<String>(
          value: 'delete',
          child: _HistoryMenuItem(
            icon: Icons.delete_outline,
            label: context.l.commonDelete,
            danger: true,
          ),
        ),
      ],
    );
  }
}

class _HistoryBatchMenu extends StatelessWidget {
  const _HistoryBatchMenu({
    super.key,
    required this.hasImage,
    required this.onImport,
    required this.onDownload,
    required this.onDelete,
  });

  final bool hasImage;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      color: t.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 176),
      icon: Icon(Icons.more_horiz, size: 16, color: t.headerText),
      iconSize: 16,
      splashRadius: 16,
      onSelected: (value) {
        if (value == 'import') {
          onImport();
        } else if (value == 'download') {
          onDownload();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        if (hasImage) ...[
          PopupMenuItem<String>(
            value: 'import',
            child: _HistoryMenuItem(
              icon: Icons.upload_outlined,
              label: context.l.serverHistoryBatchImportParameters,
            ),
          ),
          PopupMenuItem<String>(
            value: 'download',
            child: _HistoryMenuItem(
              icon: Icons.download,
              label: context.l.serverHistoryBatchDownload,
            ),
          ),
        ],
        PopupMenuItem<String>(
          value: 'delete',
          child: _HistoryMenuItem(
            icon: Icons.delete_outline,
            label: context.l.serverHistoryBatchDelete,
            danger: true,
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
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: t.fontSize(11),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HistoryIconButton extends StatelessWidget {
  const _HistoryIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.background.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(4),
      child: IconButton(
        icon: Icon(icon, size: 13, color: t.headerText),
        tooltip: tooltip,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        onPressed: onPressed,
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Center(
      child: Icon(
        status == 'failed' ? Icons.error_outline : Icons.hourglass_empty,
        color: status == 'failed' ? t.accentDanger : t.textDisabled,
        size: 28,
      ),
    );
  }
}
