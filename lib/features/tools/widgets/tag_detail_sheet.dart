import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/tag_service.dart';
import '../../../core/services/wiki_service.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/ui/app_sheet.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/tag_category_color.dart';

/// Detail sheet for a single tag — shows the Danbooru wiki description,
/// other_names chips, and tappable [[wiki_link]] spans that re-open the
/// sheet for the linked tag (so users can navigate the tag graph).
///
/// Wiki content is © Danbooru contributors, CC-BY-SA-4.0.
/// See Tags/LICENSE-WIKI.txt.
class TagDetailSheet extends StatefulWidget {
  final DanbooruTag tag;

  const TagDetailSheet({super.key, required this.tag});

  /// Show as a modal bottom sheet (mobile) or right-side panel (desktop).
  static Future<void> show(BuildContext context, DanbooruTag tag) {
    final compact = windowSizeClassOf(context) == WindowSizeClass.compact;
    return showAppSheet<void>(
      context: context,
      draggable: true,
      // Open higher on compact windows — there's less vertical room to spare.
      initialSize: compact ? 0.85 : 0.7,
      minSize: 0.4,
      maxSize: 0.95,
      builder: (_) => TagDetailSheet(tag: tag),
    );
  }

  @override
  State<TagDetailSheet> createState() => _TagDetailSheetState();
}

class _TagDetailSheetState extends State<TagDetailSheet> {
  late Future<WikiEntry?> _entryFuture;

  @override
  void initState() {
    super.initState();
    _entryFuture = _load();
  }

  Future<WikiEntry?> _load() async {
    final wiki = context.read<WikiService>();
    await wiki.ensureLoaded();
    return wiki.lookup(widget.tag.tag);
  }

  Future<void> _openLinkedTag(String tagName) async {
    final tagService = context.read<TagService>();
    final wiki = context.read<WikiService>();
    final navigator = Navigator.of(context);
    // Capture before any await — navigator.context survives this sheet's pop.
    final navigatorContext = navigator.context;

    final libraryHit = tagService.tags
        .where((t) => t.tag.toLowerCase() == tagName.toLowerCase())
        .firstOrNull;

    // Make sure the wiki asset is loaded before we decide whether we have an
    // entry. ensureLoaded() is a no-op once loaded.
    await wiki.ensureLoaded();
    final wikiHit = wiki.lookup(tagName);

    // If we have neither a library entry nor a wiki entry, the in-app sheet
    // would render an empty state — better to open the source page directly.
    if (libraryHit == null && wikiHit == null) {
      final slug = tagName.replaceAll(' ', '_');
      await launchUrl(
        Uri.parse('https://danbooru.donmai.us/wiki_pages/$slug'),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    final target = libraryHit ?? DanbooruTag(tag: tagName, count: 0);
    navigator.pop();
    // ignore: use_build_context_synchronously
    Future.microtask(() => TagDetailSheet.show(navigatorContext, target));
  }

  Future<void> _openOnDanbooru() async {
    final slug = widget.tag.tag.replaceAll(' ', '_');
    final uri = Uri.parse('https://danbooru.donmai.us/wiki_pages/$slug');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tag = widget.tag;
    final color = tagCategoryColor(t, tag.typeName);
    final mobile = windowSizeClassOf(context) == WindowSizeClass.compact;
    final l = context.l;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(t, tag, color, mobile),
        Divider(height: 1, color: t.textMinimal),
        FutureBuilder<WikiEntry?>(
          future: _entryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(VisionMetrics.space24),
                child: LoadingState(),
              );
            }
            final entry = snapshot.data;
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                VisionMetrics.space16,
                VisionMetrics.space12,
                VisionMetrics.space16,
                VisionMetrics.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry?.otherNames.isNotEmpty ?? false) ...[
                    _otherNamesChips(entry!.otherNames, t, color, mobile),
                    const SizedBox(height: VisionMetrics.space16),
                  ],
                  if (entry == null || entry.description.isEmpty)
                    _emptyState(t, l)
                  else
                    _markdown(entry.description, t, color, mobile),
                  const SizedBox(height: VisionMetrics.space24),
                  _footer(t, l),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _header(VisionTokens t, DanbooruTag tag, Color color, bool mobile) {
    final l = context.l;
    // On mobile, slightly smaller title font + wrap up to 2 lines for long
    // copyright/character tags; on desktop keep the larger one-line look.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VisionMetrics.space16,
        VisionMetrics.space8,
        VisionMetrics.space8,
        VisionMetrics.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.tag,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: color,
                    fontSize: t.fontSize(16),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: VisionMetrics.space4),
                Row(
                  children: [
                    _CategoryBadge(
                      label: tag.typeName.toUpperCase(),
                      color: color,
                    ),
                    if (tag.count > 0) ...[
                      const SizedBox(width: VisionMetrics.space8),
                      Text(
                        NumberFormat.compact().format(tag.count),
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: t.fontSize(10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          ManagerIconButton(
            icon: Icons.open_in_new,
            tooltip: l.tagDetailViewOnDanbooru,
            onPressed: _openOnDanbooru,
          ),
          ManagerIconButton(
            icon: Icons.close,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _otherNamesChips(
    List<String> names,
    VisionTokens t,
    Color color,
    bool mobile,
  ) {
    return Wrap(
      spacing: VisionMetrics.space4,
      runSpacing: VisionMetrics.space4,
      children: names.map((n) {
        return ConstrainedBox(
          // Cap chip width so a freakishly long alias can't blow out the row.
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: VisionMetrics.space8,
              vertical: mobile ? VisionMetrics.space8 : VisionMetrics.space4,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: VisionMetrics.opacityHover),
              border: Border.all(
                color: color.withValues(alpha: VisionMetrics.opacityScrim),
              ),
              borderRadius: BorderRadius.circular(VisionMetrics.radius8),
            ),
            child: Text(
              n,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _emptyState(VisionTokens t, AppLocalizations l) {
    return EmptyState(
      icon: Icons.description_outlined,
      message: l.tagDetailNoWiki,
      action: TextButton(
        onPressed: _openOnDanbooru,
        child: Text(
          l.tagDetailCheckDanbooru,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
        ),
      ),
    );
  }

  Widget _markdown(String body, VisionTokens t, Color color, bool mobile) {
    return MarkdownBody(
      data: body,
      // Selectable text on mobile blocks single-tap on inline spans — long-press
      // to select wins the gesture race against tap, so links become hard to
      // hit. Desktop keeps selection.
      selectable: !mobile,
      onTapLink: (text, href, title) {
        if (href == null) return;
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [_WikiLinkSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
      builders: {
        'wikilink': _WikiLinkBuilder(
          color: color,
          onTap: _openLinkedTag,
          mobile: mobile,
        ),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: t.textPrimary,
          fontSize: t.fontSize(11),
          height: 1.5,
        ),
        h1: TextStyle(
          color: t.textPrimary,
          fontSize: t.headerSize(15),
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: t.textPrimary,
          fontSize: t.headerSize(14),
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: t.textPrimary,
          fontSize: t.headerSize(13),
          fontWeight: FontWeight.bold,
        ),
        h4: TextStyle(
          color: t.textPrimary,
          fontSize: t.headerSize(12),
          fontWeight: FontWeight.bold,
        ),
        h5: TextStyle(
          color: t.textSecondary,
          fontSize: t.headerSize(11),
          fontWeight: FontWeight.bold,
        ),
        h6: TextStyle(
          color: t.textSecondary,
          fontSize: t.headerSize(10),
          fontWeight: FontWeight.bold,
        ),
        em: TextStyle(color: t.textSecondary, fontStyle: FontStyle.italic),
        strong: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
        code: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: t.fontSize(10),
          backgroundColor: color.withValues(alpha: VisionMetrics.opacityHover),
        ),
        codeblockDecoration: BoxDecoration(
          color: color.withValues(alpha: VisionMetrics.opacityHover),
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        ),
        blockquote: TextStyle(
          color: t.textSecondary,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: color.withValues(alpha: VisionMetrics.opacityDisabled),
              width: 3,
            ),
          ),
        ),
        listBullet: TextStyle(
          color: color.withValues(alpha: VisionMetrics.opacityScrim),
          fontSize: t.fontSize(11),
        ),
        a: TextStyle(color: color, decoration: TextDecoration.underline),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.textMinimal, width: 1)),
        ),
      ),
    );
  }

  Widget _footer(VisionTokens t, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.only(top: VisionMetrics.space8),
      child: Text(
        l.tagDetailLicense,
        style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: VisionMetrics.opacityPressed),
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VisionMetrics.space4,
          vertical: VisionMetrics.radius2,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: t.fontSize(8),
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// --- Custom inline syntax for [[target|label]] ---------------------------

class _WikiLinkSyntax extends md.InlineSyntax {
  // Match [[target|label]] where target may contain spaces but neither | nor ]
  _WikiLinkSyntax() : super(r'\[\[([^\[\]|]+?)\|([^\[\]]*?)\]\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final target = match.group(1) ?? '';
    final label = (match.group(2) ?? '').isEmpty ? target : match.group(2)!;
    final el = md.Element.text('wikilink', label);
    el.attributes['target'] = target;
    parser.addNode(el);
    return true;
  }
}

class _WikiLinkBuilder extends MarkdownElementBuilder {
  final Color color;
  final void Function(String) onTap;
  final bool mobile;

  _WikiLinkBuilder({
    required this.color,
    required this.onTap,
    required this.mobile,
  });

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final target = element.attributes['target'] ?? '';
    final label = element.textContent;
    final child = Text(
      label,
      style: (preferredStyle ?? const TextStyle()).copyWith(
        color: color,
        decoration: TextDecoration.underline,
        decorationColor: color.withValues(alpha: VisionMetrics.opacityScrim),
      ),
    );
    // On mobile, pad the hit area vertically so single-line links get a
    // realistic touch target without disrupting line wrapping. Padding here
    // expands the GestureDetector, not the visible underline.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(target),
      child: mobile
          ? Padding(
              padding: const EdgeInsets.symmetric(
                vertical: VisionMetrics.space4,
              ),
              child: child,
            )
          : child,
    );
  }
}
