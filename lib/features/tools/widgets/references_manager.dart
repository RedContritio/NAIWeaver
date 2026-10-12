import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/ui/app_tabs.dart';
import '../../director_ref/widgets/director_ref_manager.dart';
import '../../vibe_transfer/widgets/vibe_transfer_manager.dart';

class ReferencesManager extends StatefulWidget {
  const ReferencesManager({super.key});

  @override
  State<ReferencesManager> createState() => _ReferencesManagerState();
}

class _ReferencesManagerState extends State<ReferencesManager> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    return Column(
      children: [
        Container(
          key: const ValueKey<String>('references-tab-toolbar'),
          color: t.surfaceMid,
          child: AppTabBar<int>(
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
            options: [
              AppOption(value: 0, label: l.refPreciseReferences),
              AppOption(value: 1, label: l.refVibeTransfer),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [DirectorRefManager(), VibeTransferManager()],
          ),
        ),
      ],
    );
  }
}
