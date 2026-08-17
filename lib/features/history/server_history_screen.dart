import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
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

class ServerHistoryScreen extends StatefulWidget {
  const ServerHistoryScreen({super.key});

  @override
  State<ServerHistoryScreen> createState() => _ServerHistoryScreenState();
}

class _ServerHistoryScreenState extends State<ServerHistoryScreen> {
  final BackendHistoryApi _api = BackendHistoryApi();
  final ScrollController _scrollController = ScrollController();
  List<ServerHistoryItem> _items = const [];
  List<AuthUser> _users = const [];
  int? _selectedUserId;
  bool _loading = true;
  String? _error;
  Timer? _thumbnailPreloadTimer;
  int _gridColumns = 2;
  double _gridMainExtent = 260;
  int _lastPreloadStart = -1;
  int _lastPreloadEnd = -1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleThumbnailPreload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _thumbnailPreloadTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<BackendAuthNotifier>();
      if (auth.user?.isAdmin == true) {
        _users = await _api.fetchUsers();
      }
      _items = await _api.fetchHistory(userId: _selectedUserId);
      _lastPreloadStart = -1;
      _lastPreloadEnd = -1;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
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
    if (!mounted || _items.isEmpty) return;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final firstRow = _gridMainExtent <= 0
        ? 0
        : math.max(0, offset ~/ _gridMainExtent);
    var start = firstRow * _gridColumns;
    if (start < 0) start = 0;
    if (start > _items.length) start = _items.length;
    final end = math.min(_items.length, start + 20);
    if (!force && start == _lastPreloadStart && end == _lastPreloadEnd) {
      return;
    }
    _lastPreloadStart = start;
    _lastPreloadEnd = end;
    for (var i = start; i < end; i += 1) {
      final item = _items[i];
      if (!item.hasImage) continue;
      unawaited(
        precacheImage(
          NetworkImage(item.thumbnailUrl),
          context,
        ).catchError((_) {}),
      );
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
                    setState(() => _selectedUserId = value);
                    _load();
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
            onPressed: _loading ? null : _load,
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 96),
          Icon(Icons.history, size: 48, color: t.textDisabled),
          const SizedBox(height: 16),
          Center(
            child: Text(
              context.l.serverHistoryEmpty,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(12)),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1500
              ? 5
              : width >= 1100
              ? 4
              : width >= 760
              ? 3
              : 2;
          final tileWidth = (width - 24 - (columns - 1) * 12) / columns;
          _gridColumns = columns;
          _gridMainExtent = tileWidth / 0.72 + 12;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _preloadVisibleThumbnails();
          });
          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) =>
                _HistoryCard(item: _items[index], onDelete: _deleteItem),
          );
        },
      ),
    );
  }

  Future<void> _deleteItem(ServerHistoryItem item) async {
    final t = context.tRead;
    final confirm = await showConfirmDialog(
      context,
      title: context.l.commonDelete,
      message: context.l.serverHistoryDeleteConfirm,
      confirmLabel: context.l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (!mounted || confirm != true) return;

    try {
      await _api.deleteHistoryItem(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((candidate) => candidate.id != item.id).toList();
      });
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
    }
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.onDelete});

  final ServerHistoryItem item;
  final ValueChanged<ServerHistoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final auth = context.watch<BackendAuthNotifier>();
    final admin = auth.user?.isAdmin == true;
    return Material(
      color: t.surfaceMid,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.hasImage ? () => _openImage(context) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: t.borderSubtle,
                    child: item.hasImage
                        ? Image.network(
                            item.thumbnailUrl,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) =>
                                _PlaceholderIcon(status: item.status),
                          )
                        : _PlaceholderIcon(status: item.status),
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.hasImage) ...[
                          _HistoryIconButton(
                            icon: Icons.download,
                            tooltip: context.l.mainSave,
                            onPressed: () => _downloadImage(context),
                          ),
                          const SizedBox(width: 4),
                        ],
                        _HistoryIconButton(
                          icon: Icons.delete_outline,
                          tooltip: context.l.commonDelete,
                          danger: true,
                          onPressed: () => onDelete(item),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (admin && item.username.isNotEmpty) ...[
                    Text(
                      item.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.accent,
                        fontSize: t.fontSize(9),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    item.prompt.isEmpty ? item.status : item.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(11),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.width}x${item.height}  ${item.steps} steps  seed ${item.seed}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.createdAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textMinimal,
                      fontSize: t.fontSize(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openImage(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, _) => _HistoryImageViewer(
        item: item,
        onDownload: () => _downloadImage(context),
      ),
    );
  }

  Future<void> _downloadImage(BuildContext context) async {
    try {
      final response = await Dio().get<List<int>>(
        item.imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('empty image response');
      }
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      final ok = downloadBytes(bytes, item.downloadFileName);
      if (!ok) {
        throw StateError('browser download is unavailable');
      }
      if (context.mounted) {
        showAppSnackBar(
          context,
          context.l.gallerySavedTo(item.downloadFileName),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
    }
  }
}

class _HistoryImageViewer extends StatelessWidget {
  const _HistoryImageViewer({required this.item, required this.onDownload});

  final ServerHistoryItem item;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    item.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.network(
                            item.thumbnailUrl,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.low,
                          ),
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      );
                    },
                    errorBuilder: (_, _, _) =>
                        _PlaceholderIcon(status: item.status),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            right: 8,
            child: _HistoryIconButton(
              icon: Icons.download,
              tooltip: context.l.mainSave,
              onPressed: onDownload,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryIconButton extends StatelessWidget {
  const _HistoryIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.background.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(4),
      child: IconButton(
        icon: Icon(
          icon,
          size: 13,
          color: danger ? t.accentDanger : t.headerText,
        ),
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
